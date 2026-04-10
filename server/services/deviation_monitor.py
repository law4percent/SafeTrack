# SafeTrack/server/services/deviation_monitor.py
#
# Real-time deviation monitor.
# Port of path_monitor_service.dart adapted for always-on Python server.
#
# Responsibilities:
#   - Listens to deviceLogs/{uid}/{code} in real time via RTDB stream
#   - For each new GPS log entry, runs Haversine check against all active routes
#   - If deviation detected: writes to alertLogs + sends FCM push to parent
#
# Guards (ported from path_monitor_service.dart):
#   - deviceEnabled == false    → skip device entirely
#   - locationType != 'gps'     → skip cached logs
#   - sos == true               → skip during emergency
#   - outside school hours      → skip (no point alerting during off-hours)
#   - cooldown not expired      → skip (RTDB-backed, 5 min per device+route)
#   - fewer than 2 waypoints    → skip route (no segment to check)
#   - route isActive == false   → skip route
#
# Rule: This module does NOT import logger directly.
#       Logger is injected by main.py via constructor (Option A).
#
# FIX 1: _on_log_event() and _on_devices_changed() now catch and LOG
#         exceptions instead of re-raising. Re-raising inside a Firebase
#         listener thread causes the SDK to swallow the exception silently —
#         the listener dies with no log entry and no recovery.
#
# FIX 2: _handle_deviation() separates alertLogs write from FCM push.
#         A failed FCM push no longer prevents the alert from being
#         recorded. Each step is logged individually.
#
# RTDB paths read:
#   linkedDevices/{uid}/devices/{code}
#   deviceLogs/{uid}/{code}
#   devicePaths/{uid}/{code}/{routeId}
#   users/{uid}/fcmToken
#   serverCooldowns/{uid}/{code}/{routeId}/lastDeviationAlert
#
# RTDB paths written:
#   alertLogs/{uid}/{code}/{pushId}
#   serverCooldowns/{uid}/{code}/{routeId}/lastDeviationAlert

import time
import threading
from datetime import datetime
from typing import Callable

import firebase_admin.db as rtdb

from config import (
    DEVIATION_COOLDOWN_MINUTES,
    PATH_LINKED_DEVICES,
    PATH_DEVICE_LOGS,
    PATH_DEVICE_PATHS,
    PATH_USERS,
    PATH_ALERT_LOGS,
    PATH_SERVER_COOLDOWNS,
    TIMEZONE,
)
from utils.haversine import distance_to_path, parse_waypoints
from utils.fcm_sender import send_alert


# ── Internal helpers ──────────────────────────────────────────────────────────

def _is_sos(val) -> bool:
    """Handle sos field as bool or string."""
    return val is True or str(val).lower() == 'true'


def _is_enabled(val) -> bool:
    """deviceEnabled is stored as string 'true'/'false' by the app."""
    return str(val).lower() == 'true'


def _now_ms() -> int:
    return int(time.time() * 1000)


def _parse_hhmm(hhmm: str):
    """
    Parse 'HH:MM' string into (hour, minute) tuple.
    Returns None if invalid.
    """
    if not hhmm:
        return None
    parts = hhmm.split(':')
    if len(parts) != 2:
        return None
    try:
        h = int(parts[0])
        m = int(parts[1])
        return (h, m)
    except ValueError:
        return None


def _is_within_school_hours(time_in_hm: tuple, time_out_hm: tuple) -> bool:
    """Return True if current PHT time is within school hours."""
    now    = datetime.now(TIMEZONE)
    h, m   = now.hour, now.minute
    in_h,  in_m  = time_in_hm
    out_h, out_m = time_out_hm

    now_mins = h * 60 + m
    in_mins  = in_h * 60 + in_m
    out_mins = out_h * 60 + out_m

    return in_mins <= now_mins <= out_mins


def _get_fcm_token(uid: str) -> str:
    """
    Fetch FCM token from users/{uid}/fcmToken.
    Returns empty string if missing — caller logs and skips.
    """
    snap = rtdb.reference(f"{PATH_USERS}/{uid}/fcmToken").get()
    if snap and isinstance(snap, str) and snap.strip():
        return snap.strip()
    return ""


def _is_cooldown_active(uid: str, device_code: str, route_id: str) -> bool:
    """
    Check RTDB-backed cooldown for deviation alert.
    Returns True if cooldown is still active (should skip).
    """
    path = (
        f"{PATH_SERVER_COOLDOWNS}/{uid}/{device_code}"
        f"/{route_id}/lastDeviationAlert"
    )
    last_alert_ms = rtdb.reference(path).get()
    if not last_alert_ms:
        return False
    elapsed_ms  = _now_ms() - int(last_alert_ms)
    cooldown_ms = DEVIATION_COOLDOWN_MINUTES * 60 * 1000
    return elapsed_ms < cooldown_ms


def _set_cooldown(uid: str, device_code: str, route_id: str):
    """Write current timestamp to RTDB cooldown path."""
    path = (
        f"{PATH_SERVER_COOLDOWNS}/{uid}/{device_code}"
        f"/{route_id}/lastDeviationAlert"
    )
    rtdb.reference(path).set(_now_ms())


def _load_active_routes(uid: str, device_code: str) -> list:
    """
    Load active routes from devicePaths/{uid}/{device_code}.
    Returns list of dicts: {route_id, path_name, threshold_meters, waypoints}
    """
    snap = rtdb.reference(f"{PATH_DEVICE_PATHS}/{uid}/{device_code}").get()
    if not snap or not isinstance(snap, dict):
        return []

    routes = []
    for route_id, data in snap.items():
        if not isinstance(data, dict):
            continue

        is_active = data.get('isActive', True)
        if isinstance(is_active, bool) and not is_active:
            continue
        if isinstance(is_active, str) and is_active.lower() == 'false':
            continue

        threshold  = float(data.get('deviationThresholdMeters', 50.0))
        path_name  = str(data.get('pathName', 'Unnamed Route'))
        raw_wps    = data.get('waypoints')

        if not raw_wps:
            continue

        waypoints = parse_waypoints(raw_wps)
        if len(waypoints) < 2:
            continue

        routes.append({
            "route_id"        : route_id,
            "path_name"       : path_name,
            "threshold_meters": threshold,
            "waypoints"       : waypoints,
        })

    return routes


# ── Per-device log listener ───────────────────────────────────────────────────

class _DeviceListener:
    """
    Listens to deviceLogs/{uid}/{device_code} for new entries.
    Runs Haversine check on each new GPS log.
    """

    def __init__(self, uid: str, device_code: str, child_name: str,
                 time_in_hm: tuple, time_out_hm: tuple, log: Callable):
        self.uid           = uid
        self.device_code   = device_code
        self.child_name    = child_name
        self.time_in_hm    = time_in_hm
        self.time_out_hm   = time_out_hm
        self._log          = log
        self._last_log_key = None
        self._listener     = None

    def start(self):
        """Attach RTDB listener to deviceLogs."""
        path = f"{PATH_DEVICE_LOGS}/{self.uid}/{self.device_code}"
        self._listener = rtdb.reference(path).listen(self._on_log_event)
        self._log(
            details      = (
                f"Deviation listener attached — "
                f"device={self.device_code} uid={self.uid}"
            ),
            log_type     = "info",
            show_console = True,
        )

    def stop(self):
        """Detach RTDB listener."""
        if self._listener:
            self._listener.close()
            self._listener = None
            self._log(
                details      = (
                    f"Deviation listener stopped — "
                    f"device={self.device_code}"
                ),
                log_type     = "info",
                show_console = True,
            )

    def _on_log_event(self, event):
        """
        Called by Firebase Admin SDK on any change to the log node.
        Filters to only process new child additions.

        FIX 1: Exceptions are caught and logged here instead of
        re-raised. Re-raising inside a Firebase listener thread causes
        the SDK to swallow the exception silently — the listener dies
        with no log entry and no recovery.
        """
        try:
            data = event.data
            if not isinstance(data, dict):
                return

            # Find the newest entry by timestamp
            latest_key = None
            latest_ts  = 0
            latest_log = None

            for key, log in data.items():
                if not isinstance(log, dict):
                    continue
                ts = int(log.get('lastUpdate') or log.get('timestamp') or 0)
                if ts > latest_ts:
                    latest_ts  = ts
                    latest_key = key
                    latest_log = log

            if not latest_key or latest_key == self._last_log_key:
                return

            self._last_log_key = latest_key
            self._process_log(latest_log)

        except Exception as e:
            # FIX 1: Log instead of re-raise
            self._log(
                details      = (
                    f"Log event error — "
                    f"device={self.device_code}: {e}"
                ),
                log_type     = "error",
                show_console = True,
            )

    def _process_log(self, log: dict):
        """Apply all guards then run Haversine check."""
        # Guard 1: GPS only
        if str(log.get('locationType', 'cached')) != 'gps':
            return

        # Guard 2: Skip during SOS
        if _is_sos(log.get('sos', False)):
            return

        # Guard 3: Skip outside school hours
        if not _is_within_school_hours(self.time_in_hm, self.time_out_hm):
            return

        # Guard 4: Valid coordinates
        lat = log.get('latitude')
        lng = log.get('longitude')
        if lat is None or lng is None:
            return
        try:
            lat = float(lat)
            lng = float(lng)
        except (TypeError, ValueError):
            return
        if lat == 0.0 and lng == 0.0:
            return

        routes = _load_active_routes(self.uid, self.device_code)
        if not routes:
            return

        self._check_deviation((lat, lng), routes)

    def _check_deviation(self, position: tuple, routes: list):
        """Run Haversine check against all active routes."""
        for route in routes:
            distance = distance_to_path(position, route["waypoints"])
            if distance > route["threshold_meters"]:
                self._handle_deviation(distance, route)

    def _handle_deviation(self, distance_m: float, route: dict):
        """
        Fire deviation alert if cooldown allows.

        FIX 2: alertLogs write and FCM push are fully separated.
          - alertLogs is always written first.
          - FCM failure is caught and logged independently.
          - A failed FCM push does NOT prevent the alertLogs entry
            from being written.
        """
        route_id   = route["route_id"]
        route_name = route["path_name"]

        # Guard 5: RTDB-backed cooldown
        if _is_cooldown_active(self.uid, self.device_code, route_id):
            return

        # Set cooldown immediately to prevent race conditions
        _set_cooldown(self.uid, self.device_code, route_id)

        dist_str = f"{distance_m:.0f}"
        message  = (
            f"{self.child_name} is {dist_str}m away from the registered "
            f"route \"{route_name}\". Please check their location immediately."
        )

        self._log(
            details      = (
                f"Deviation: {self.child_name} {dist_str}m "
                f"from \"{route_name}\" — device={self.device_code}"
            ),
            log_type     = "info",
            show_console = True,
        )

        # ── Step 1: Write to alertLogs (always) ──────────────────
        try:
            rtdb.reference(
                f"{PATH_ALERT_LOGS}/{self.uid}/{self.device_code}"
            ).push({
                "type"          : "deviation",
                "childName"     : self.child_name,
                "message"       : message,
                "timestamp"     : {".sv": "timestamp"},
                "distanceMeters": round(distance_m, 1),
                "routeName"     : route_name,
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
                alert_type  = "deviation",
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


# ── Public API ────────────────────────────────────────────────────────────────

class DeviationMonitor:
    """
    Manages per-device RTDB listeners for all linked devices.
    Called once from main.py on server start.

    Usage:
        monitor = DeviationMonitor(logger=log)
        monitor.start()
    """

    def __init__(self, logger: Callable):
        self._listeners: dict[str, _DeviceListener] = {}
        self._lock = threading.Lock()
        self._log  = logger

    def start(self):
        """
        Fetch all linked devices and start per-device listeners.
        Then watch for device list changes to add/remove listeners dynamically.
        """
        self._load_all_devices()
        rtdb.reference(PATH_LINKED_DEVICES).listen(self._on_devices_changed)

    def _load_all_devices(self):
        """Fetch all users and start listeners for their enabled devices."""
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
        """Start a listener for a device if it's enabled and has a schedule."""
        if not _is_enabled(device_data.get('deviceEnabled', 'false')):
            return

        child_name   = str(device_data.get('childName', 'Unknown'))
        time_in_str  = str(device_data.get('schoolTimeIn', ''))
        time_out_str = str(device_data.get('schoolTimeOut', ''))

        time_in_hm  = _parse_hhmm(time_in_str)
        time_out_hm = _parse_hhmm(time_out_str)

        if not time_in_hm or not time_out_hm:
            return

        key = f"{uid}:{device_code}"
        with self._lock:
            if key in self._listeners:
                return

            listener = _DeviceListener(
                uid         = uid,
                device_code = device_code,
                child_name  = child_name,
                time_in_hm  = time_in_hm,
                time_out_hm = time_out_hm,
                log         = self._log,
            )
            listener.start()
            self._listeners[key] = listener

    def _stop_listener(self, uid: str, device_code: str):
        """Stop and remove listener for a device."""
        key = f"{uid}:{device_code}"
        with self._lock:
            listener = self._listeners.pop(key, None)
            if listener:
                listener.stop()

    def _on_devices_changed(self, event):
        """
        Handle changes to linkedDevices tree.
        Starts listeners for new enabled devices,
        stops listeners for disabled or removed devices.

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