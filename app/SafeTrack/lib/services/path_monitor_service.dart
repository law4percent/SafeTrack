// app/SafeTrack/lib/services/path_monitor_service.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'haversine_service.dart';

/// Represents one active deviation event for a device.
class DeviationEvent {
  final String deviceCode;
  final String childName;
  final LatLng position;
  final double distanceMeters;
  final double thresholdMeters;
  final String routeName;
  final DateTime detectedAt;

  const DeviationEvent({
    required this.deviceCode,
    required this.childName,
    required this.position,
    required this.distanceMeters,
    required this.thresholdMeters,
    required this.routeName,
    required this.detectedAt,
  });
}

/// Callback fired whenever a deviation is detected.
typedef OnDeviationDetected = void Function(DeviationEvent event);

/// Monitors all linked devices in real time.
/// For each new GPS log entry it checks every active route
/// and fires [onDeviationDetected] if the child is off-path.
class PathMonitorService {
  // ── Singleton ─────────────────────────────────────────────────
  static final PathMonitorService _instance =
      PathMonitorService._internal();
  factory PathMonitorService() => _instance;
  PathMonitorService._internal();

  // ── State ─────────────────────────────────────────────────────

  /// All active log listeners keyed by deviceCode.
  final Map<String, StreamSubscription<DatabaseEvent>> _logListeners = {};

  /// Cached routes per device: deviceCode → list of _RouteData
  final Map<String, List<_RouteData>> _routeCache = {};

  /// Route listeners keyed by deviceCode (refresh cache on change).
  final Map<String, StreamSubscription<DatabaseEvent>> _routeListeners = {};

  /// Tracks the last processed log key per device to avoid re-processing.
  final Map<String, String> _lastLogKey = {};

  // FIX 3: secondary timestamp guard so a service restart doesn't
  // re-process the last known log entry.
  // Uses firmware's 'lastUpdate' server timestamp (Unix ms int).
  final Map<String, int> _lastLogTimestamp = {};

  /// Cooldown tracker: deviceCode → last deviation notification time.
  /// Prevents spamming the parent with repeated alerts.
  final Map<String, DateTime> _lastAlertTime = {};

  /// Minimum time between alerts for the same device (5 minutes).
  static const Duration _alertCooldown = Duration(minutes: 5);

  // FIX 5: school hours cache per device.
  // Populated when _subscribeToDevices processes linkedDevices snapshot.
  // Stored as "HH:MM" strings matching firmware/my_children_screen format.
  final Map<String, _SchoolSchedule> _schoolSchedules = {};

  OnDeviationDetected? _onDeviationDetected;
  bool _isRunning = false;

  /// Whether the monitor is currently active.
  bool get isRunning => _isRunning;

  // ── Public API ────────────────────────────────────────────────

  /// Start monitoring all linked devices for the current user.
  Future<void> start(
      {required OnDeviationDetected onDeviationDetected}) async {
    if (_isRunning) return;
    _isRunning = true;
    _onDeviationDetected = onDeviationDetected;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[PathMonitor] No user logged in — aborting start');
      _isRunning = false;
      return;
    }

    debugPrint('[PathMonitor] Starting for user ${user.uid}');
    await _subscribeToDevices(user.uid);
  }

  /// Stop all listeners and clear state.
  void stop() {
    for (final sub in _logListeners.values) {
      sub.cancel();
    }
    for (final sub in _routeListeners.values) {
      sub.cancel();
    }
    _logListeners.clear();
    _routeListeners.clear();
    _routeCache.clear();
    _lastLogKey.clear();
    _lastLogTimestamp.clear(); // FIX 3
    _lastAlertTime.clear();
    _schoolSchedules.clear();  // FIX 5
    _isRunning = false;
    _onDeviationDetected = null;
    debugPrint('[PathMonitor] Stopped');
  }

  // ── Internal ──────────────────────────────────────────────────

  /// Listen to linkedDevices and set up per-device monitors.
  Future<void> _subscribeToDevices(String userId) async {
    final devicesRef = FirebaseDatabase.instance
        .ref('linkedDevices')
        .child(userId)
        .child('devices');

    devicesRef.onValue.listen((event) async {
      if (!event.snapshot.exists) return;

      final devicesData =
          event.snapshot.value as Map<dynamic, dynamic>;

      final currentCodes =
          devicesData.keys.map((k) => k.toString()).toSet();

      for (final entry in devicesData.entries) {
        final deviceCode = entry.key.toString();
        final deviceData = entry.value as Map<dynamic, dynamic>;
        final isEnabled =
            deviceData['deviceEnabled']?.toString() == 'true';
        final childName =
            deviceData['childName']?.toString() ?? 'Unknown';

        // FIX 5: Cache school schedule whenever linkedDevices fires.
        // schoolTimeIn / schoolTimeOut are written as "HH:MM" strings
        // by my_children_screen.dart's LinkedDevice.formatTimeOfDay().
        // gemini_service also reads these same fields with the same format.
        final timeIn  = deviceData['schoolTimeIn']?.toString() ?? '';
        final timeOut = deviceData['schoolTimeOut']?.toString() ?? '';
        _schoolSchedules[deviceCode] =
            _SchoolSchedule(timeIn: timeIn, timeOut: timeOut);

        if (!isEnabled) {
          // Device disabled — cancel any active listener
          if (_logListeners.containsKey(deviceCode)) {
            _logListeners[deviceCode]?.cancel();
            _logListeners.remove(deviceCode);
            _routeListeners[deviceCode]?.cancel();
            _routeListeners.remove(deviceCode);
            _routeCache.remove(deviceCode);
            _lastLogKey.remove(deviceCode);
            _lastLogTimestamp.remove(deviceCode); // FIX 3
            debugPrint(
                '[PathMonitor] Listener stopped — device disabled: $deviceCode');
          }
          continue;
        }

        if (!_logListeners.containsKey(deviceCode)) {
          await _subscribeToRoutes(userId, deviceCode);
          _subscribeToLogs(userId, deviceCode, childName);
        }
      }

      // Cancel listeners for removed devices
      final removedCodes =
          _logListeners.keys.toSet().difference(currentCodes);
      for (final code in removedCodes) {
        _logListeners[code]?.cancel();
        _logListeners.remove(code);
        _routeListeners[code]?.cancel();
        _routeListeners.remove(code);
        _routeCache.remove(code);
        _lastLogKey.remove(code);
        _lastLogTimestamp.remove(code); // FIX 3
        _schoolSchedules.remove(code);  // FIX 5
        debugPrint('[PathMonitor] Removed listener for $code');
      }
    });
  }

  /// Cache routes for [deviceCode] and refresh when they change.
  Future<void> _subscribeToRoutes(
      String userId, String deviceCode) async {
    final routesRef = FirebaseDatabase.instance
        .ref('devicePaths')
        .child(userId)
        .child(deviceCode);

    final sub = routesRef.onValue.listen((event) {
      if (!event.snapshot.exists) {
        _routeCache[deviceCode] = [];
        return;
      }

      final routesData =
          event.snapshot.value as Map<dynamic, dynamic>;
      final routes = <_RouteData>[];

      for (final entry in routesData.entries) {
        final data = entry.value as Map<dynamic, dynamic>;
        final isActive = data['isActive'] as bool? ?? true;
        if (!isActive) continue;

        final threshold =
            (data['deviationThresholdMeters'] as num?)?.toDouble() ??
                50.0;
        final pathName =
            data['pathName']?.toString() ?? 'Unnamed Route';

        final waypoints = _parseWaypoints(data['waypoints']);
        if (waypoints.length < 2) continue;

        routes.add(_RouteData(
          routeId: entry.key.toString(),
          pathName: pathName,
          thresholdMeters: threshold,
          waypoints: waypoints,
        ));
      }

      _routeCache[deviceCode] = routes;
      debugPrint(
          '[PathMonitor] Cached ${routes.length} active route(s) for $deviceCode');
    });

    _routeListeners[deviceCode] = sub;

    // Wait briefly for initial cache load before log listener starts
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Listen to the latest log entry for [deviceCode].
  void _subscribeToLogs(
      String userId, String deviceCode, String childName) {
    final logsRef = FirebaseDatabase.instance
        .ref('deviceLogs')
        .child(userId)
        .child(deviceCode);

    // limitToLast(1) — only care about the newest entry
    final sub = logsRef.limitToLast(1).onChildAdded.listen((event) {
      final logKey = event.snapshot.key ?? '';

      // FIX 3 (part A): key-based dedup — same as before
      if (_lastLogKey[deviceCode] == logKey) return;

      final logData =
          event.snapshot.value as Map<dynamic, dynamic>?;
      if (logData == null) return;

      // FIX 3 (part B): timestamp-based secondary guard.
      // Prevents re-processing the most recent log when the service
      // restarts and onChildAdded replays the last stored entry.
      // firmware writes 'lastUpdate' as a Firebase server timestamp (int ms).
      final logTimestamp = _toInt(logData['lastUpdate']);
      final lastKnownTs = _lastLogTimestamp[deviceCode] ?? 0;
      if (logTimestamp > 0 && logTimestamp <= lastKnownTs) {
        debugPrint(
            '[PathMonitor] Skipping already-processed log for $deviceCode '
            '(ts: $logTimestamp ≤ last: $lastKnownTs)');
        return;
      }

      // FIX 1: Only process live GPS fixes.
      // Firmware writes locationType: "gps" | "cached".
      // Cached entries reuse stale coordinates — running deviation
      // checks against them produces false positives because the child
      // may be on route now but the cached position was recorded earlier.
      final locationType =
          logData['locationType']?.toString() ?? 'cached';
      if (locationType != 'gps') {
        debugPrint(
            '[PathMonitor] Skipping $locationType log for $deviceCode '
            '— only live GPS fixes are checked for deviation');
        _lastLogKey[deviceCode] = logKey; // still advance the key
        if (logTimestamp > lastKnownTs) {
          _lastLogTimestamp[deviceCode] = logTimestamp;
        }
        return;
      }

      // FIX 2: Skip deviation check when SOS is already active.
      // The firmware writes sos as a bool. dashboard_screen._listenToSOS()
      // also guards on sosVal == true || sosVal == 'true' for consistency.
      // No need to stack a deviation alert on top of an SOS alert.
      final sosVal = logData['sos'];
      final isSos = sosVal == true || sosVal == 'true';
      if (isSos) {
        debugPrint(
            '[PathMonitor] Skipping deviation check for $deviceCode '
            '— SOS is active, emergency already signalled');
        _lastLogKey[deviceCode] = logKey;
        if (logTimestamp > lastKnownTs) {
          _lastLogTimestamp[deviceCode] = logTimestamp;
        }
        return;
      }

      // FIX 5: Skip deviation check outside school hours.
      // schoolTimeIn / schoolTimeOut come from linkedDevices, written
      // by my_children_screen.dart as "HH:MM" 24hr strings.
      // gemini_service uses the same field names and parsing logic.
      // Monitoring outside school hours generates noise (e.g. the child
      // is at home and home coords are off the school route polyline).
      final schedule = _schoolSchedules[deviceCode];
      if (schedule != null && schedule.isConfigured) {
        if (!schedule.isWithinSchoolHours()) {
          debugPrint(
              '[PathMonitor] Skipping deviation check for $deviceCode '
              '— outside school hours '
              '(${schedule.timeIn} – ${schedule.timeOut})');
          _lastLogKey[deviceCode] = logKey;
          if (logTimestamp > lastKnownTs) {
            _lastLogTimestamp[deviceCode] = logTimestamp;
          }
          return;
        }
      }

      // All guards passed — advance state and check deviation
      _lastLogKey[deviceCode] = logKey;
      if (logTimestamp > lastKnownTs) {
        _lastLogTimestamp[deviceCode] = logTimestamp;
      }

      final lat = (logData['latitude'] as num?)?.toDouble();
      final lng = (logData['longitude'] as num?)?.toDouble();

      if (lat == null || lng == null || (lat == 0 && lng == 0)) return;

      final position = LatLng(lat, lng);
      _checkDeviation(deviceCode, childName, position);
    });

    _logListeners[deviceCode] = sub;
    debugPrint('[PathMonitor] Listening to logs for $deviceCode');
  }

  /// Run Haversine check against all cached routes for this device.
  void _checkDeviation(
      String deviceCode, String childName, LatLng position) {
    final routes = _routeCache[deviceCode];
    if (routes == null || routes.isEmpty) return;

    for (final route in routes) {
      final distance =
          HaversineService.distanceToPath(position, route.waypoints);

      debugPrint(
          '[PathMonitor] $childName ($deviceCode) → '
          '${route.pathName}: ${distance.toStringAsFixed(1)}m '
          '(threshold: ${route.thresholdMeters}m)');

      if (distance > route.thresholdMeters) {
        _handleDeviation(
          deviceCode: deviceCode,
          childName: childName,
          position: position,
          distanceMeters: distance,
          route: route,
        );
      }
    }
  }

  /// Fire the deviation callback respecting cooldown.
  void _handleDeviation({
    required String deviceCode,
    required String childName,
    required LatLng position,
    required double distanceMeters,
    required _RouteData route,
  }) {
    final now = DateTime.now();
    final lastAlert = _lastAlertTime[deviceCode];

    if (lastAlert != null &&
        now.difference(lastAlert) < _alertCooldown) {
      debugPrint(
          '[PathMonitor] Deviation for $deviceCode suppressed (cooldown)');
      return;
    }

    _lastAlertTime[deviceCode] = now;

    final event = DeviationEvent(
      deviceCode: deviceCode,
      childName: childName,
      position: position,
      distanceMeters: distanceMeters,
      thresholdMeters: route.thresholdMeters,
      routeName: route.pathName,
      detectedAt: now,
    );

    debugPrint(
        '[PathMonitor] ⚠️ DEVIATION: $childName is '
        '${distanceMeters.toStringAsFixed(1)}m from "${route.pathName}"');

    _saveAlertToRTDB(
      deviceCode: deviceCode,
      childName: childName,
      type: 'deviation',
      message: '$childName is ${distanceMeters.toStringAsFixed(0)}m away '
          'from the registered route "${route.pathName}". '
          'Please check their location immediately.',
      distanceMeters: distanceMeters,
      routeName: route.pathName,
    );

    _onDeviationDetected?.call(event);
  }

  // ── Public alert writers ──────────────────────────────────────
  // These expose _saveAlertToRTDB for callers outside this service
  // (dashboard_screen for SOS, background_monitor_service for behavior).
  // All write to alertLogs/{uid}/{deviceCode}/{pushId} — the same path
  // alert_screen.dart reads and gemini_service reads for AI context.

  /// Save an SOS alert to alertLogs.
  /// Call from dashboard_screen._listenToSOS() when sos becomes true,
  /// alongside NotificationService().showSosAlert().
  /// This ensures the SOS filter in alert_screen is never empty and
  /// gemini_service sees SOS history in its Firebase context.
  Future<void> saveSosAlert({
    required String deviceCode,
    required String childName,
    double? latitude,
    double? longitude,
  }) async {
    final loc = (latitude != null && longitude != null &&
            !(latitude == 0 && longitude == 0))
        ? 'Last location: Lat ${latitude.toStringAsFixed(5)}, '
          'Lng ${longitude.toStringAsFixed(5)}.'
        : 'Location unavailable at time of alert.';
    await _saveAlertToRTDB(
      deviceCode: deviceCode,
      childName: childName,
      type: 'sos',
      message: '$childName triggered an SOS emergency alert. $loc',
    );
  }

  /// Save any alert type to alertLogs.
  /// Use for 'late', 'absent', 'anomaly' from behavior_monitor_service
  /// or any future alert type. behavior_monitor_service._fireAlert already
  /// writes directly to RTDB — this method exists as a convenience for
  /// callers that don't have direct Firebase access (e.g. background tasks).
  Future<void> saveAlert({
    required String deviceCode,
    required String childName,
    required String type,
    required String message,
  }) async {
    await _saveAlertToRTDB(
      deviceCode: deviceCode,
      childName: childName,
      type: type,
      message: message,
    );
  }

  /// Write alert entry to RTDB.
  /// Path: alertLogs/{userId}/{deviceCode}/{pushId}
  Future<void> _saveAlertToRTDB({
    required String deviceCode,
    required String childName,
    required String type,
    required String message,
    double? distanceMeters,
    String? routeName,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final ref = FirebaseDatabase.instance
          .ref('alertLogs')
          .child(user.uid)
          .child(deviceCode)
          .push();
      await ref.set({
        'type': type,
        'childName': childName,
        'message': message,
        'timestamp': ServerValue.timestamp,
        if (distanceMeters != null) 'distanceMeters': distanceMeters,
        if (routeName != null) 'routeName': routeName,
      });
      debugPrint(
          '[PathMonitor] Alert saved to RTDB: $type for $childName');
    } catch (e) {
      debugPrint('[PathMonitor] Failed to save alert: $e');
    }
  }

  // ── Waypoint parser (handles Map and legacy List) ─────────────
  static List<LatLng> _parseWaypoints(dynamic raw) {
    final List<Map<dynamic, dynamic>> wpMaps = [];

    if (raw is Map) {
      final sorted = (raw as Map<dynamic, dynamic>).entries.toList()
        ..sort((a, b) {
          final aIdx =
              int.tryParse(a.key.toString().replaceAll('wp_', '')) ?? 0;
          final bIdx =
              int.tryParse(b.key.toString().replaceAll('wp_', '')) ?? 0;
          return aIdx.compareTo(bIdx);
        });
      wpMaps.addAll(
          sorted.map((e) => e.value as Map<dynamic, dynamic>));
    } else if (raw is List) {
      wpMaps.addAll(raw.whereType<Map<dynamic, dynamic>>());
    }

    return wpMaps
        .map((wp) {
          final lat = (wp['latitude'] as num?)?.toDouble();
          final lng = (wp['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }

  // ── Safe int cast (same pattern as gemini_service._toInt) ─────
  static int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }
}

// ── Internal models ───────────────────────────────────────────
class _RouteData {
  final String routeId;
  final String pathName;
  final double thresholdMeters;
  final List<LatLng> waypoints;

  const _RouteData({
    required this.routeId,
    required this.pathName,
    required this.thresholdMeters,
    required this.waypoints,
  });
}

// FIX 5: School schedule model.
// Parses "HH:MM" strings written by my_children_screen.dart
// (LinkedDevice.formatTimeOfDay) and read by gemini_service.dart.
// Inlined here to avoid importing my_children_screen.
class _SchoolSchedule {
  final String timeIn;   // "HH:MM" 24hr, empty if not set
  final String timeOut;  // "HH:MM" 24hr, empty if not set

  const _SchoolSchedule({required this.timeIn, required this.timeOut});

  /// True only when both timeIn and timeOut are non-empty valid strings.
  bool get isConfigured => timeIn.isNotEmpty && timeOut.isNotEmpty;

  /// Returns true if current device time is within school hours.
  /// Returns true (always monitor) when schedule is not configured,
  /// so devices without a schedule set are never silenced.
  bool isWithinSchoolHours() {
    if (!isConfigured) return true;
    try {
      final now = DateTime.now();
      final inParts  = timeIn.split(':');
      final outParts = timeOut.split(':');
      final schoolStart = DateTime(
        now.year, now.month, now.day,
        int.parse(inParts[0]), int.parse(inParts[1]),
      );
      final schoolEnd = DateTime(
        now.year, now.month, now.day,
        int.parse(outParts[0]), int.parse(outParts[1]),
      );
      return now.isAfter(schoolStart) && now.isBefore(schoolEnd);
    } catch (_) {
      return true; // parse error → don't suppress monitoring
    }
  }
}