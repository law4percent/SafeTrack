# SafeTrack/server/services/behavior_monitor.py
#
# Behavior monitor — cron-based, runs every 5 minutes.
# Port of behavior_monitor_service.dart adapted for always-on Python server.
#
# Responsibilities:
#   - Checks all linked devices against school schedule
#   - Fires 'late', 'absent', 'anomaly' alerts when conditions are met
#   - Writes to alertLogs + sends FCM push to parent
#
# Guards (ported from behavior_monitor_service.dart):
#   - deviceEnabled == false    → skip device
#   - locationType != 'gps'     → skip cached logs
#   - sos == true               → skip log entry
#   - schoolTimeIn/Out missing  → skip device (no schedule)
#   - _not_yet_fired_today()    → skip if already fired today (RTDB-backed)
#
# Rule: This module raises exceptions to caller (main.py).
#       It does NOT import logger directly.
#
# RTDB paths read:
#   linkedDevices/{uid}/devices/{code}
#   deviceLogs/{uid}/{code}        (limitToLast 200, scoped to today)
#   alertLogs/{uid}/{code}         (scoped to today, for dedup)
#   users/{uid}/fcmToken
#
# RTDB paths written:
#   alertLogs/{uid}/{code}/{pushId}

from datetime import datetime, timedelta

import firebase_admin.db as rtdb

from config import (
    BEHAVIOR_LOG_LIMIT,
    LATE_GRACE_PERIOD_MINUTES,
    ANOMALY_NIGHT_HOUR,
    ANOMALY_EARLY_HOUR,
    PATH_LINKED_DEVICES,
    PATH_DEVICE_LOGS,
    PATH_ALERT_LOGS,
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
    """
    Parse 'HH:MM' string into (hour, minute) tuple.
    Returns None if invalid.
    Port of BehaviorMonitorService._parseHHMM()
    """
    if not hhmm:
        return None
    parts = hhmm.split(':')
    if len(parts) != 2:
        return None
    try:
        return (int(parts[0]), int(parts[1]))
    except ValueError:
        return None


def _fmt(dt: datetime) -> str:
    """
    Format datetime as 'HH:MM'.
    Port of BehaviorMonitorService._fmt()
    """
    return dt.strftime('%H:%M')


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
        f"[BehaviorMonitor] FCM token missing for uid={uid} — "
        f"push not sent. Parent must open app once to register token."
    )


def _not_yet_fired_today(uid: str, device_code: str, alert_type: str) -> bool:
    """
    Check if this alert type has already fired today for this device.
    Queries alertLogs scoped to today — O(alerts today) not O(all time).
    Port of BehaviorMonitorService._notYetFiredToday()

    Returns True if NOT yet fired (safe to fire).
    Returns False if already fired today (skip).
    """
    now         = datetime.now(TIMEZONE)
    today_start = datetime(now.year, now.month, now.day,
                           tzinfo=TIMEZONE).timestamp() * 1000
    today_end   = today_start + 86400000  # +24 hours in ms

    try:
        snap = (
            rtdb.reference(f"{PATH_ALERT_LOGS}/{uid}/{device_code}")
            .order_by_child('timestamp')
            .start_at(today_start)
            .get()
        )

        if not snap or not isinstance(snap, dict):
            return True

        for entry in snap.values():
            if not isinstance(entry, dict):
                continue
            if entry.get('type') != alert_type:
                continue
            ts = entry.get('timestamp')
            if ts is None:
                continue
            try:
                ts_int = int(ts)
                if today_start <= ts_int < today_end:
                    return False  # already fired today
            except (TypeError, ValueError):
                continue

        return True  # not yet fired

    except Exception:
        return True  # fail-open: allow check on error


def _save_alert(
    uid        : str,
    device_code: str,
    child_name : str,
    alert_type : str,
    message    : str,
):
    """
    Write alert to alertLogs and send FCM push.
    Port of BehaviorMonitorService._fireAlert()
    """
    # Write to RTDB
    rtdb.reference(f"{PATH_ALERT_LOGS}/{uid}/{device_code}").push({
        "type"     : alert_type,
        "childName": child_name,
        "message"  : message,
        "timestamp": {".sv": "timestamp"},
    })

    # Send FCM push
    try:
        fcm_token = _get_fcm_token(uid)
        send_alert(
            fcm_token   = fcm_token,
            alert_type  = alert_type,
            child_name  = child_name,
            device_code = device_code,
            message     = message,
        )
    except RuntimeError as e:
        # Token missing — alert still written to RTDB, only push is skipped.
        # main.py will log this. Parent will see it in AlertScreen on next open.
        raise


# ── Per-device check ──────────────────────────────────────────────────────────

def _check_device(
    uid        : str,
    device_code: str,
    child_name : str,
    time_in_hm : tuple,
    time_out_hm: tuple,
):
    """
    Run all behavior checks for one device.
    Port of BehaviorMonitorService._checkDevice()
    """
    now = datetime.now(TIMEZONE)

    # Build today's schedule datetimes
    today_in = now.replace(
        hour=time_in_hm[0], minute=time_in_hm[1],
        second=0, microsecond=0
    )
    today_out = now.replace(
        hour=time_out_hm[0], minute=time_out_hm[1],
        second=0, microsecond=0
    )
    grace_end = today_in + timedelta(minutes=LATE_GRACE_PERIOD_MINUTES)

    # Fetch last 200 logs for this device
    raw_logs = (
        rtdb.reference(f"{PATH_DEVICE_LOGS}/{uid}/{device_code}")
        .order_by_key()
        .limit_to_last(BEHAVIOR_LOG_LIMIT)
        .get()
    )

    today_logs         = []
    school_hour_gps_logs = []

    if raw_logs and isinstance(raw_logs, dict):
        for log in raw_logs.values():
            if not isinstance(log, dict):
                continue

            # Use lastUpdate (firmware field, same value as timestamp)
            ts = log.get('lastUpdate') or log.get('timestamp')
            if not ts:
                continue
            try:
                ts_int = int(ts)
            except (TypeError, ValueError):
                continue

            log_dt = datetime.fromtimestamp(ts_int / 1000, tz=TIMEZONE)

            # Only today's logs
            if (log_dt.year  != now.year  or
                log_dt.month != now.month or
                log_dt.day   != now.day):
                continue

            # GPS-only + SOS exclusion
            location_type = str(log.get('locationType', 'cached'))
            is_gps        = location_type == 'gps'
            is_sos        = _is_sos(log.get('sos', False))

            if not is_gps or is_sos:
                continue

            today_logs.append((log_dt, log))

            # School hour GPS logs
            if today_in < log_dt < today_out:
                school_hour_gps_logs.append((log_dt, log))

    # ── CHECK 1: Absent ──────────────────────────────────────────────────────
    # No GPS pings at all during school hours after grace period
    if (now > grace_end and
            now < today_out and
            not school_hour_gps_logs and
            _not_yet_fired_today(uid, device_code, 'absent')):

        _save_alert(
            uid         = uid,
            device_code = device_code,
            child_name  = child_name,
            alert_type  = 'absent',
            message     = (
                f"{child_name} has not been detected during school hours today "
                f"({_fmt(today_in)} – {_fmt(today_out)}). "
                f"They may be absent. Please verify."
            ),
        )

    # ── CHECK 2: Late ────────────────────────────────────────────────────────
    # Has GPS pings during school hours but first one is after grace end
    if (school_hour_gps_logs and
            _not_yet_fired_today(uid, device_code, 'late')):

        # Sort by datetime ascending — find first school-hour ping
        sorted_logs = sorted(school_hour_gps_logs, key=lambda x: x[0])
        first_dt    = sorted_logs[0][0]

        if first_dt > grace_end:
            late_by = int((first_dt - today_in).total_seconds() / 60)
            _save_alert(
                uid         = uid,
                device_code = device_code,
                child_name  = child_name,
                alert_type  = 'late',
                message     = (
                    f"{child_name}'s device was first detected at {_fmt(first_dt)}, "
                    f"which is {late_by} minutes after school start time "
                    f"({_fmt(today_in)}). They may have arrived late."
                ),
            )

    # ── CHECK 3: Anomaly ─────────────────────────────────────────────────────
    # Movement detected at suspicious hours (after 22:00 or before 05:00)
    if _not_yet_fired_today(uid, device_code, 'anomaly'):
        anomaly_logs = [
            (dt, log) for dt, log in today_logs
            if dt.hour >= ANOMALY_NIGHT_HOUR or dt.hour < ANOMALY_EARLY_HOUR
        ]

        if anomaly_logs:
            first_dt = sorted(anomaly_logs, key=lambda x: x[0])[0][0]
            _save_alert(
                uid         = uid,
                device_code = device_code,
                child_name  = child_name,
                alert_type  = 'anomaly',
                message     = (
                    f"{child_name}'s device detected movement at {_fmt(first_dt)}, "
                    f"which is outside normal school hours. "
                    f"Please verify their whereabouts."
                ),
            )


# ── Public API ────────────────────────────────────────────────────────────────

def run_behavior_checks():
    """
    Entry point called by main.py cron every 5 minutes.
    Fetches all users and their enabled devices, runs checks in sequence.
    Port of BehaviorMonitorService.runChecks()

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

            # Each device check is independent — one failure should not
            # stop other devices from being checked.
            try:
                _check_device(
                    uid         = str(uid),
                    device_code = str(device_code),
                    child_name  = child_name,
                    time_in_hm  = time_in_hm,
                    time_out_hm = time_out_hm,
                )
            except Exception as e:
                # Re-raise with device context so main.py can log it
                raise RuntimeError(
                    f"[BehaviorMonitor] Check failed for "
                    f"{device_code} (uid={uid}): {e}"
                ) from e