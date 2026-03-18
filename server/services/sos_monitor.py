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
# Rule: This module raises exceptions to caller (main.py).
#       It does NOT import logger directly.
#
# RTDB paths read:
#   linkedDevices/{uid}/devices/{code}
#   linkedDevices/{uid}/devices/{code}/deviceStatus/sos
#   users/{uid}/fcmToken
#
# RTDB paths written:
#   alertLogs/{uid}/{code}/{pushId}

import threading

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
    Raises RuntimeError if missing so main.py can log it visibly.
    Token is saved by the app on login via authStateChanges() listener.
    """
    snap = rtdb.reference(f"{PATH_USERS}/{uid}/fcmToken").get()
    if snap and isinstance(snap, str) and snap.strip():
        return snap.strip()
    raise RuntimeError(
        f"[SosMonitor] FCM token missing for uid={uid} — "
        f"push not sent. Parent must open app once to register token."
    )


def _save_alert(
    uid        : str,
    device_code: str,
    child_name : str,
    message    : str,
):
    """
    Write SOS alert to alertLogs and send FCM push.
    No cooldown — every SOS transition fires.
    """
    # Write to RTDB alertLogs
    rtdb.reference(f"{PATH_ALERT_LOGS}/{uid}/{device_code}").push({
        "type"     : "sos",
        "childName": child_name,
        "message"  : message,
        "timestamp": {".sv": "timestamp"},
    })

    # Send FCM push to parent
    try:
        fcm_token = _get_fcm_token(uid)
        send_alert(
            fcm_token   = fcm_token,
            alert_type  = "sos",
            child_name  = child_name,
            device_code = device_code,
            message     = message,
        )
    except RuntimeError:
        raise


# ── Per-device SOS listener ───────────────────────────────────────────────────

class _SosDeviceListener:
    """
    Listens to linkedDevices/{uid}/devices/{code}/deviceStatus/sos
    for a single device.

    Mirrors the logic of _ChildCardState._listenToSOS() in
    dashboard_screen.dart — detects the false→true transition
    and fires exactly once per SOS event.
    """

    def __init__(self, uid: str, device_code: str, child_name: str):
        self.uid         = uid
        self.device_code = device_code
        self.child_name  = child_name
        self._was_sos    = False
        self._listener   = None

    def start(self):
        """Attach RTDB listener to deviceStatus/sos field."""
        path = (
            f"{PATH_LINKED_DEVICES}/{self.uid}/devices/"
            f"{self.device_code}/deviceStatus/sos"
        )
        self._listener = rtdb.reference(path).listen(self._on_sos_event)

    def stop(self):
        """Detach RTDB listener."""
        if self._listener:
            self._listener.close()
            self._listener = None

    def _on_sos_event(self, event):
        """
        Called whenever the sos field changes.

        Transition logic:
          false → true  : SOS activated → fire alert
          true  → false : SOS cleared   → reset _was_sos
          true  → true  : No change     → skip (already fired)
        """
        try:
            val    = event.data
            is_sos = _is_sos(val) if val is not None else False

            if is_sos and not self._was_sos:
                # SOS just activated — fire immediately
                self._was_sos = True

                message = (
                    f"{self.child_name} has triggered an SOS emergency alert! "
                    f"Please open the app immediately to view their location."
                )

                _save_alert(
                    uid         = self.uid,
                    device_code = self.device_code,
                    child_name  = self.child_name,
                    message     = message,
                )

            elif not is_sos and self._was_sos:
                # SOS cleared — reset for next event
                self._was_sos = False

        except Exception as e:
            raise RuntimeError(
                f"[SosMonitor] SOS event error "
                f"{self.device_code} (uid={self.uid}): {e}"
            ) from e


# ── Public API ────────────────────────────────────────────────────────────────

class SosMonitor:
    """
    Manages per-device SOS listeners for all linked devices.
    Called once from main.py on server start.

    Mirrors the structure of DeviationMonitor — starts listeners
    for all enabled devices and watches for runtime changes.

    Usage:
        monitor = SosMonitor()
        monitor.start()
    """

    def __init__(self):
        self._listeners: dict[str, _SosDeviceListener] = {}
        self._lock = threading.Lock()

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
            raise RuntimeError(
                f"[SosMonitor] Devices change event error: {e}"
            ) from e