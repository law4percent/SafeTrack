# SafeTrack/server/services/sos_monitor.py
#
# Real-time SOS monitor.
# Listens to linkedDevices/{uid}/devices/{code}/deviceStatus/sos
# for each enabled device. Fires immediately when sos transitions
# to true.
#
# Responsibilities:
#   - Detects sos: true on deviceStatus for all linked devices
#   - Writes 'sos' alert to alertLogs (so AlertScreen shows history)
#   - Sends FCM push to parent's phone
#   - Resets _wasSOS state when sos returns to false
#
# Guards:
#   - deviceEnabled == false  → skip device entirely
#   - _was_sos == true        → skip (already fired for this SOS event)
#   - No cooldown             → every SOS fires immediately
#   - No school hours guard   → SOS can happen anytime
#
# Rule: This module does NOT import logger directly.
#       Logger is injected by main.py via constructor (Option A).
#
# FIX 1: _on_sos_event() and _on_devices_changed() now catch and LOG
#         exceptions instead of re-raising. Re-raising inside a Firebase
#         listener thread causes the SDK to swallow the exception silently —
#         the listener dies with no log entry and no recovery.
#
# FIX 2: _save_alert() separates alertLogs write from FCM push.
#         A failed FCM push no longer prevents the alert from being
#         recorded. Each step is logged individually.
#
# RTDB paths read:
#   linkedDevices/{uid}/devices/{code}
#   linkedDevices/{uid}/devices/{code}/deviceStatus/sos
#   users/{uid}/fcmToken
#
# RTDB paths written:
#   alertLogs/{uid}/{code}/{pushId}

import threading
from typing import Callable

import firebase_admin.db as rtdb

from config import (
    PATH_LINKED_DEVICES,
    PATH_ALERT_LOGS,
    PATH_USERS,
)
from utils.fcm_sender import send_alert


# ── Internal helpers ──────────────────────────────────────────────────────────

def _is_sos(val) -> bool:
    """Handle sos field as bool or string."""
    return val is True or str(val).lower() == 'true'


def _is_enabled(val) -> bool:
    """deviceEnabled stored as string 'true'/'false'."""
    return str(val).lower() == 'true'


def _get_fcm_token(uid: str) -> str:
    """
    Fetch FCM token from users/{uid}/fcmToken.
    Returns empty string if missing — caller logs and skips.
    """
    snap = rtdb.reference(f"{PATH_USERS}/{uid}/fcmToken").get()
    if snap and isinstance(snap, str) and snap.strip():
        return snap.strip()
    return ""


# ── Per-device SOS listener ───────────────────────────────────────────────────

class _SosDeviceListener:
    """
    Listens to linkedDevices/{uid}/devices/{code}/deviceStatus/sos
    for a single device.

    Detects the false→true transition and fires exactly once per
    SOS event.
    """

    def __init__(self, uid: str, device_code: str, child_name: str,
                 log: Callable):
        self.uid         = uid
        self.device_code = device_code
        self.child_name  = child_name
        self._log        = log
        self._was_sos    = False
        self._listener   = None

    def start(self):
        """Attach RTDB listener to deviceStatus/sos field."""
        path = (
            f"{PATH_LINKED_DEVICES}/{self.uid}/devices/"
            f"{self.device_code}/deviceStatus/sos"
        )
        self._listener = rtdb.reference(path).listen(self._on_sos_event)
        self._log(
            details      = f"SOS listener attached — device={self.device_code} uid={self.uid}",
            log_type     = "info",
            show_console = True,
        )

    def stop(self):
        """Detach RTDB listener."""
        if self._listener:
            self._listener.close()
            self._listener = None
            self._log(
                details      = f"SOS listener stopped — device={self.device_code}",
                log_type     = "info",
                show_console = True,
            )

    def _save_alert(self, message: str):
        """
        Write SOS alert to alertLogs, then send FCM push.

        FIX 2: Two fully separated steps.
          - alertLogs write is always attempted first.
          - FCM failure is caught and logged independently.
          - A failed FCM push does NOT prevent the alertLogs entry
            from being written.
        """
        # ── Step 1: Write to alertLogs (always) ──────────────────
        try:
            rtdb.reference(
                f"{PATH_ALERT_LOGS}/{self.uid}/{self.device_code}"
            ).push({
                "type"     : "sos",
                "childName": self.child_name,
                "message"  : message,
                "timestamp": {".sv": "timestamp"},
            })
            self._log(
                details      = (
                    f"alertLogs written — "
                    f"device={self.device_code} uid={self.uid}"
                ),
                log_type     = "info",
                show_console = True,
            )
        except Exception as e:
            self._log(
                details      = (
                    f"alertLogs write FAILED — "
                    f"device={self.device_code} uid={self.uid}: {e}"
                ),
                log_type     = "error",
                show_console = True,
            )
            # Still attempt FCM so the parent at least gets a push

        # ── Step 2: Send FCM push (best-effort) ──────────────────
        try:
            fcm_token = _get_fcm_token(self.uid)

            if not fcm_token:
                self._log(
                    details      = (
                        f"FCM token missing — push not sent. "
                        f"uid={self.uid} device={self.device_code}. "
                        f"Parent must open app once to register token."
                    ),
                    log_type     = "warning",
                    show_console = True,
                )
                return

            send_alert(
                fcm_token   = fcm_token,
                alert_type  = "sos",
                child_name  = self.child_name,
                device_code = self.device_code,
                message     = message,
            )
            self._log(
                details      = (
                    f"FCM push sent — "
                    f"device={self.device_code} uid={self.uid}"
                ),
                log_type     = "info",
                show_console = True,
            )
        except Exception as e:
            self._log(
                details      = (
                    f"FCM push FAILED — "
                    f"device={self.device_code} uid={self.uid}: {e}. "
                    f"alertLogs entry was still written."
                ),
                log_type     = "error",
                show_console = True,
            )

    def _on_sos_event(self, event):
        """
        Called whenever the sos field changes.

        Transition logic:
          false → true  : SOS activated → fire alert
          true  → false : SOS cleared   → reset _was_sos
          true  → true  : No change     → skip (already fired)

        FIX 1: Exceptions are caught and logged here instead of
        re-raised. Re-raising inside a Firebase listener thread causes
        the SDK to swallow the exception silently — the listener dies
        with no log entry and no recovery.
        """
        try:
            val    = event.data
            is_sos = _is_sos(val) if val is not None else False

            self._log(
                details      = (
                    f"SOS event — device={self.device_code} "
                    f"value={val} is_sos={is_sos} was_sos={self._was_sos}"
                ),
                log_type     = "debug",
                show_console = True,
            )

            if is_sos and not self._was_sos:
                # SOS just activated — fire immediately
                self._was_sos = True
                self._log(
                    details      = (
                        f"SOS ACTIVATED — {self.child_name} "
                        f"device={self.device_code} uid={self.uid}"
                    ),
                    log_type     = "warning",
                    show_console = True,
                )
                message = (
                    f"{self.child_name} has triggered an SOS emergency alert! "
                    f"Please open the app immediately to view their location."
                )
                self._save_alert(message)

            elif not is_sos and self._was_sos:
                # SOS cleared — reset for next event
                self._was_sos = False
                self._log(
                    details      = (
                        f"SOS cleared — "
                        f"device={self.device_code} uid={self.uid}"
                    ),
                    log_type     = "info",
                    show_console = True,
                )

            # else: no state change — skip silently

        except Exception as e:
            # FIX 1: Log instead of re-raise
            self._log(
                details      = (
                    f"SOS event error — "
                    f"device={self.device_code} uid={self.uid}: {e}"
                ),
                log_type     = "error",
                show_console = True,
            )


# ── Public API ────────────────────────────────────────────────────────────────

class SosMonitor:
    """
    Manages per-device SOS listeners for all linked devices.
    Called once from main.py on server start.

    Usage:
        monitor = SosMonitor(logger=log)
        monitor.start()
    """

    def __init__(self, logger: Callable):
        self._listeners: dict[str, _SosDeviceListener] = {}
        self._lock = threading.Lock()
        self._log  = logger

    def start(self):
        """
        Fetch all linked devices and start per-device SOS listeners.
        Then watch for device list changes at runtime.
        """
        self._load_all_devices()
        rtdb.reference(PATH_LINKED_DEVICES).listen(self._on_devices_changed)

    def _load_all_devices(self):
        """Fetch all users and start SOS listeners for enabled devices."""
        snap = rtdb.reference(PATH_LINKED_DEVICES).get()
        if not snap or not isinstance(snap, dict):
            self._log(
                details      = "No linked devices found on startup",
                log_type     = "warning",
                show_console = True,
            )
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
                self._maybe_start_listener(
                    str(uid), str(device_code), device_data
                )

    def _maybe_start_listener(
        self, uid: str, device_code: str, device_data: dict
    ):
        """Start a SOS listener for a device if it is enabled."""
        if not _is_enabled(device_data.get('deviceEnabled', 'false')):
            return

        child_name = str(device_data.get('childName', 'Unknown'))
        key        = f"{uid}:{device_code}"

        with self._lock:
            if key in self._listeners:
                return

            listener = _SosDeviceListener(
                uid         = uid,
                device_code = device_code,
                child_name  = child_name,
                log         = self._log,
            )
            listener.start()
            self._listeners[key] = listener

    def _stop_listener(self, uid: str, device_code: str):
        """Stop and remove SOS listener for a device."""
        key = f"{uid}:{device_code}"
        with self._lock:
            listener = self._listeners.pop(key, None)
            if listener:
                listener.stop()

    def _on_devices_changed(self, event):
        """
        Handle changes to linkedDevices tree at runtime.
        Starts listeners for newly enabled devices.
        Stops listeners for disabled or removed devices.

        FIX 1: Exceptions are caught and logged instead of re-raised.
        """
        try:
            data = event.data
            if not isinstance(data, dict):
                return

            for uid, user_data in data.items():
                if not isinstance(user_data, dict):
                    continue
                devices = user_data.get('devices', {})
                if not isinstance(devices, dict):
                    continue

                for device_code, device_data in devices.items():
                    if not isinstance(device_data, dict):
                        continue

                    key        = f"{uid}:{device_code}"
                    is_enabled = _is_enabled(
                        device_data.get('deviceEnabled', 'false')
                    )

                    if is_enabled:
                        if key not in self._listeners:
                            self._maybe_start_listener(
                                str(uid), str(device_code), device_data
                            )
                    else:
                        if key in self._listeners:
                            self._stop_listener(str(uid), str(device_code))

        except Exception as e:
            # FIX 1: Log instead of re-raise
            self._log(
                details      = f"Devices change event error: {e}",
                log_type     = "error",
                show_console = True,
            )