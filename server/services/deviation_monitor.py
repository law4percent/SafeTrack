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
# Rule: This module raises exceptions to caller (main.py).
#       It does NOT import logger directly.
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
    """Handle sos field as bool or string (firmware writes bool, app init writes string)."""
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
    Port of BehaviorMonitorService._parseHHMM()
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


def _get_fcm_token(uid: str) -> str | None:
    """Fetch FCM token from users/{uid}/fcmToken."""
    snap = rtdb.reference(f"{PATH_USERS}/{uid}/fcmToken").get()
    if snap and isinstance(snap, str) and snap.strip():
        return snap.strip()
    return None


def _is_cooldown_active(uid: str, device_code: str, route_id: str) -> bool:
    """
    Check RTDB-backed cooldown for deviation alert.
    Path: serverCooldowns/{uid}/{device_code}/{route_id}/lastDeviationAlert
    Returns True if cooldown is still active (should skip).
    """
    path = f"{PATH_SERVER_COOLDOWNS}/{uid}/{device_code}/{route_id}/lastDeviationAlert"
    last_alert_ms = rtdb.reference(path).get()

    if not last_alert_ms:
        return False

    elapsed_ms = _now_ms() - int(last_alert_ms)
    cooldown_ms = DEVIATION_COOLDOWN_MINUTES * 60 * 1000
    return elapsed_ms < cooldown_ms


def _set_cooldown(uid: str, device_code: str, route_id: str):
    """Write current timestamp to RTDB cooldown path."""
    path = f"{PATH_SERVER_COOLDOWNS}/{uid}/{device_code}/{route_id}/lastDeviationAlert"
    rtdb.reference(path).set(_now_ms())


def _save_alert_to_rtdb(
    uid        : str,
    device_code: str,
    child_name : str,
    message    : str,
    distance_m : float,
    route_name : str,
):
    """
    Write deviation alert to alertLogs/{uid}/{device_code}/{pushId}.
    Port of PathMonitorService._saveAlertToRTDB()
    """
    ref = rtdb.reference(f"{PATH_ALERT_LOGS}/{uid}/{device_code}")
    ref.push({
        "type"          : "deviation",
        "childName"     : child_name,
        "message"       : message,
        "timestamp"     : {".sv": "timestamp"},
        "distanceMeters": round(distance_m, 1),
        "routeName"     : route_name,
    })


def _load_active_routes(uid: str, device_code: str) -> list:
    """
    Load active routes from devicePaths/{uid}/{device_code}.
    Returns list of dicts: {route_id, path_name, threshold_meters, waypoints}
    Port of PathMonitorService._parseRoutesSnapshot()
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
                 time_in_hm: tuple, time_out_hm: tuple):
        self.uid          = uid
        self.device_code  = device_code
        self.child_name   = child_name
        self.time_in_hm   = time_in_hm
        self.time_out_hm  = time_out_hm
        self._last_log_key = None
        self._listener     = None

    def start(self):
        """Attach RTDB listener to deviceLogs."""
        path = f"{PATH_DEVICE_LOGS}/{self.uid}/{self.device_code}"
        self._listener = rtdb.reference(path).listen(self._on_log_event)

    def stop(self):
        """Detach RTDB listener."""
        if self._listener:
            self._listener.close()
            self._listener = None

    def _on_log_event(self, event):
        """
        Called by Firebase Admin SDK on any change to the log node.
        Filters to only process new child additions.
        Port of PathMonitorService._subscribeToLogs()
        """
        try:
            # event.data is the full node snapshot on first load,
            # then individual child updates. We handle both.
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
            # Raise so main.py can log it
            raise RuntimeError(
                f"[DeviationMonitor] Log event error "
                f"{self.device_code}: {e}"
            ) from e

    def _process_log(self, log: dict):
        """
        Apply all guards then run Haversine check.
        Port of PathMonitorService._subscribeToLogs() guard chain.
        """
        # Guard 1: GPS only — skip cached logs
        location_type = str(log.get('locationType', 'cached'))
        if location_type != 'gps':
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

        # Load active routes (fresh fetch on each log event)
        routes = _load_active_routes(self.uid, self.device_code)
        if not routes:
            return

        position = (lat, lng)
        self._check_deviation(position, routes)

    def _check_deviation(self, position: tuple, routes: list):
        """
        Run Haversine check against all active routes.
        Port of PathMonitorService._checkDeviation()
        """
        for route in routes:
            distance = distance_to_path(position, route["waypoints"])

            if distance > route["threshold_meters"]:
                self._handle_deviation(distance, route)

    def _handle_deviation(self, distance_m: float, route: dict):
        """
        Fire deviation alert if cooldown allows.
        Port of PathMonitorService._handleDeviation()
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

        # Write to alertLogs
        _save_alert_to_rtdb(
            uid         = self.uid,
            device_code = self.device_code,
            child_name  = self.child_name,
            message     = message,
            distance_m  = distance_m,
            route_name  = route_name,
        )

        # Send FCM push
        fcm_token = _get_fcm_token(self.uid)
        if fcm_token:
            send_alert(
                fcm_token   = fcm_token,
                alert_type  = "deviation",
                child_name  = self.child_name,
                device_code = self.device_code,
                message     = message,
            )


# ── Public API ────────────────────────────────────────────────────────────────

class DeviationMonitor:
    """
    Manages per-device RTDB listeners for all linked devices.
    Called once from main.py on server start.

    Usage:
        monitor = DeviationMonitor()
        monitor.start()   # blocking — runs until KeyboardInterrupt
    """

    def __init__(self):
        self._listeners: dict[str, _DeviceListener] = {}
        self._lock = threading.Lock()

    def start(self):
        """
        Fetch all linked devices and start per-device listeners.
        Then watch for device list changes to add/remove listeners dynamically.
        """
        # Initial load of all users and their devices
        self._load_all_devices()

        # Watch linkedDevices for changes (new devices linked, devices removed)
        rtdb.reference(PATH_LINKED_DEVICES).listen(self._on_devices_changed)

    def _load_all_devices(self):
        """Fetch all users and start listeners for their enabled devices."""
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
                self._maybe_start_listener(str(uid), str(device_code), device_data)

    def _maybe_start_listener(self, uid: str, device_code: str, device_data: dict):
        """Start a listener for a device if it's enabled and has a schedule."""
        # Guard: deviceEnabled
        if not _is_enabled(device_data.get('deviceEnabled', 'false')):
            return

        child_name   = str(device_data.get('childName', 'Unknown'))
        time_in_str  = str(device_data.get('schoolTimeIn', ''))
        time_out_str = str(device_data.get('schoolTimeOut', ''))

        time_in_hm  = _parse_hhmm(time_in_str)
        time_out_hm = _parse_hhmm(time_out_str)

        # Skip if no schedule set
        if not time_in_hm or not time_out_hm:
            return

        key = f"{uid}:{device_code}"
        with self._lock:
            if key in self._listeners:
                return  # already listening

            listener = _DeviceListener(
                uid          = uid,
                device_code  = device_code,
                child_name   = child_name,
                time_in_hm   = time_in_hm,
                time_out_hm  = time_out_hm,
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
                        # Device disabled — stop listener
                        if key in self._listeners:
                            self._stop_listener(str(uid), str(device_code))

        except Exception as e:
            raise RuntimeError(
                f"[DeviationMonitor] Devices change event error: {e}"
            ) from e