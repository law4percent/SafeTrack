# SafeTrack/server/services/silence_monitor.py
#
# Silence (heartbeat) monitor — cron-based, runs every 5 minutes.
# No Dart equivalent — this check requires an always-on process.
#
# Responsibilities:
#   - Checks lastUpdate of each enabled device's deviceStatus
#   - If now - lastUpdate > SILENCE_THRESHOLD_MINUTES during school hours
#     → writes 'silent' alert to alertLogs
#     → sends FCM push to parent
#   - Re-alerts every SILENCE_REALER_COOLDOWN_MINUTES if device stays silent
#
# Guards:
#   - deviceEnabled == false    → skip device
#   - sos == true               → skip (parent already knows, SOS is the alert)
#   - outside school hours      → skip
#   - re-alert cooldown active  → skip (RTDB-backed, 30 min)
#
# Rule: This module raises exceptions to caller (main.py).
#       It does NOT import logger directly.
#
# RTDB paths read:
#   linkedDevices/{uid}/devices/{code}
#   linkedDevices/{uid}/devices/{code}/deviceStatus   ← lastUpdate, sos
#   users/{uid}/fcmToken
#   serverCooldowns/{uid}/{code}/lastSilentAlert
#
# RTDB paths written:
#   alertLogs/{uid}/{code}/{pushId}
#   serverCooldowns/{uid}/{code}/lastSilentAlert

import time
from datetime import datetime, timedelta

import firebase_admin.db as rtdb

from config import (
    SILENCE_THRESHOLD_MINUTES,
    SILENCE_REALER_COOLDOWN_MINUTES,
    PATH_LINKED_DEVICES,
    PATH_ALERT_LOGS,
    PATH_SERVER_COOLDOWNS,
    PATH_USERS,
    TIMEZONE,
)
from utils.fcm_sender import send_alert


# ── Internal helpers ──────────────────────────────────────────────────────────

def _is_sos(val) -> bool:
    """Handle sos field as bool or string."""
    return val is True or str(val).lower() == 'true'


def _is_enabled(val) -> bool:
    """deviceEnabled stored as string 'true'/'false'."""
    return str(val).lower() == 'true'


def _parse_hhmm(hhmm: str):
    """Parse 'HH:MM' string into (hour, minute) tuple. Returns None if invalid."""
    if not hhmm:
        return None
    parts = hhmm.split(':')
    if len(parts) != 2:
        return None
    try:
        return (int(parts[0]), int(parts[1]))
    except ValueError:
        return None


def _is_within_school_hours(time_in_hm: tuple, time_out_hm: tuple) -> bool:
    """Return True if current PHT time is within school hours."""
    now  = datetime.now(TIMEZONE)
    h, m = now.hour, now.minute

    now_mins = h * 60 + m
    in_mins  = time_in_hm[0]  * 60 + time_in_hm[1]
    out_mins = time_out_hm[0] * 60 + time_out_hm[1]

    return in_mins <= now_mins <= out_mins


def _now_ms() -> int:
    return int(time.time() * 1000)


def _get_fcm_token(uid: str) -> str:
    """
    Fetch FCM token from users/{uid}/fcmToken.
    Raises RuntimeError if missing so main.py can log it visibly.
    Token is saved by the app on login via authStateChanges() listener.
    """
    snap = rtdb.reference(f"{PATH_USERS}/{uid}/fcmToken").get()
    if snap and isinstance(snap, str) and snap.strip():
        return snap.strip()
    raise RuntimeError(
        f"[SilenceMonitor] FCM token missing for uid={uid} — "
        f"push not sent. Parent must open app once to register token."
    )


def _is_realer_cooldown_active(uid: str, device_code: str) -> bool:
    """
    Check RTDB-backed re-alert cooldown for silence alerts.
    Path: serverCooldowns/{uid}/{device_code}/lastSilentAlert
    Returns True if cooldown is still active (should skip).
    """
    path          = f"{PATH_SERVER_COOLDOWNS}/{uid}/{device_code}/lastSilentAlert"
    last_alert_ms = rtdb.reference(path).get()

    if not last_alert_ms:
        return False

    elapsed_ms  = _now_ms() - int(last_alert_ms)
    cooldown_ms = SILENCE_REALER_COOLDOWN_MINUTES * 60 * 1000
    return elapsed_ms < cooldown_ms


def _set_realer_cooldown(uid: str, device_code: str):
    """Write current timestamp to RTDB silence cooldown path."""
    path = f"{PATH_SERVER_COOLDOWNS}/{uid}/{device_code}/lastSilentAlert"
    rtdb.reference(path).set(_now_ms())


def _save_alert(
    uid        : str,
    device_code: str,
    child_name : str,
    message    : str,
):
    """Write silent alert to alertLogs and send FCM push."""
    # Write to RTDB
    rtdb.reference(f"{PATH_ALERT_LOGS}/{uid}/{device_code}").push({
        "type"     : "silent",
        "childName": child_name,
        "message"  : message,
        "timestamp": {".sv": "timestamp"},
    })

    # Send FCM push
    try:
        fcm_token = _get_fcm_token(uid)
        send_alert(
            fcm_token   = fcm_token,
            alert_type  = "silent",
            child_name  = child_name,
            device_code = device_code,
            message     = message,
        )
    except RuntimeError:
        raise


# ── Per-device silence check ──────────────────────────────────────────────────

def _check_device(
    uid        : str,
    device_code: str,
    child_name : str,
    time_in_hm : tuple,
    time_out_hm: tuple,
    device_data: dict,
):
    """
    Run silence check for one device.

    Uses deviceStatus/lastUpdate — written by firmware on every transmission.
    This is the most reliable field for heartbeat checking because:
      - It is a server timestamp (not device clock)
      - It is always written regardless of GPS validity
      - It exists in deviceStatus so we don't need to scan deviceLogs
    """
    # Guard 1: Outside school hours → skip
    if not _is_within_school_hours(time_in_hm, time_out_hm):
        return

    # Read deviceStatus from the already-fetched device_data
    device_status = device_data.get('deviceStatus', {})
    if not isinstance(device_status, dict):
        return

    # Guard 2: SOS active → skip
    # Parent already knows about the emergency via SOS alert.
    # A silence alert on top of SOS would be noise.
    if _is_sos(device_status.get('sos', False)):
        return

    # Guard 3: Re-alert cooldown active → skip
    if _is_realer_cooldown_active(uid, device_code):
        return

    # Read lastUpdate from deviceStatus
    last_update_raw = device_status.get('lastUpdate')
    if not last_update_raw:
        # No lastUpdate at all — device has never transmitted
        # Don't alert: device may just be setting up
        return

    try:
        last_update_ms = int(last_update_raw)
    except (TypeError, ValueError):
        return

    if last_update_ms == 0:
        return

    # Calculate silence duration
    now_ms          = _now_ms()
    silence_ms      = now_ms - last_update_ms
    threshold_ms    = SILENCE_THRESHOLD_MINUTES * 60 * 1000

    if silence_ms < threshold_ms:
        # Device is transmitting normally
        return

    # Device is silent — calculate human-readable duration
    silence_minutes = silence_ms // 60000
    silence_str     = (
        f"{silence_minutes} minute{'s' if silence_minutes != 1 else ''}"
    )

    # Set cooldown before sending to prevent race on concurrent cron runs
    _set_realer_cooldown(uid, device_code)

    message = (
        f"{child_name}'s device has not sent any data for {silence_str}. "
        f"The device may be off, out of battery, or without signal. "
        f"Please check on {child_name} immediately."
    )

    _save_alert(
        uid         = uid,
        device_code = device_code,
        child_name  = child_name,
        message     = message,
    )


# ── Public API ────────────────────────────────────────────────────────────────

def run_silence_checks():
    """
    Entry point called by main.py cron every 5 minutes.
    Fetches all users and their enabled devices, runs silence check.

    Raises:
        RuntimeError: if RTDB fetch fails — caught and logged by main.py
    """
    snap = rtdb.reference(PATH_LINKED_DEVICES).get()
    if not snap or not isinstance(snap, dict):
        return

    for uid, user_data in snap.items():
        if not isinstance(user_data, dict):
            continue

        devices = user_data.get('devices', {})
        if not isinstance(devices, dict):
            continue

        for device_code, device_data in devices.items():
            if not isinstance(device_data, dict):
                continue

            # Guard: deviceEnabled
            if not _is_enabled(device_data.get('deviceEnabled', 'false')):
                continue

            child_name   = str(device_data.get('childName', 'Unknown'))
            time_in_str  = str(device_data.get('schoolTimeIn', ''))
            time_out_str = str(device_data.get('schoolTimeOut', ''))

            time_in_hm  = _parse_hhmm(time_in_str)
            time_out_hm = _parse_hhmm(time_out_str)

            # Guard: skip if no schedule
            if not time_in_hm or not time_out_hm:
                continue

            # Each device check is independent
            try:
                _check_device(
                    uid         = str(uid),
                    device_code = str(device_code),
                    child_name  = child_name,
                    time_in_hm  = time_in_hm,
                    time_out_hm = time_out_hm,
                    device_data = device_data,
                )
            except Exception as e:
                raise RuntimeError(
                    f"[SilenceMonitor] Check failed for "
                    f"{device_code} (uid={uid}): {e}"
                ) from e