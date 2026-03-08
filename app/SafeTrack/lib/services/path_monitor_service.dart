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

  // FIX #9: Store the top-level devices subscription so stop() can cancel it.
  // Previously this subscription was discarded, meaning calling start() a
  // second time (e.g. after sign-out/sign-in) created a second listener
  // alongside the first, causing duplicate deviation alerts and SOS saves.
  StreamSubscription<DatabaseEvent>? _devicesSubscription;

  /// All active log listeners keyed by deviceCode.
  final Map<String, StreamSubscription<DatabaseEvent>> _logListeners = {};

  /// Cached routes per device: deviceCode → list of _RouteData
  final Map<String, List<_RouteData>> _routeCache = {};

  /// Route listeners keyed by deviceCode (refresh cache on change).
  final Map<String, StreamSubscription<DatabaseEvent>> _routeListeners = {};

  /// Tracks the last processed log key per device to avoid re-processing.
  final Map<String, String> _lastLogKey = {};

  /// Cooldown tracker: deviceCode:routeId → last deviation notification time.
  final Map<String, DateTime> _lastAlertTime = {};

  /// Minimum time between alerts for the same device+route (5 minutes).
  static const Duration _alertCooldown = Duration(minutes: 5);

  OnDeviationDetected? _onDeviationDetected;
  bool _isRunning = false;

  /// Whether the monitor is currently active.
  bool get isRunning => _isRunning;

  // ── Public API ────────────────────────────────────────────────

  /// Start monitoring all linked devices for the current user.
  Future<void> start({required OnDeviationDetected onDeviationDetected}) async {
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
    // FIX #9: Cancel the devices listener that was previously leaked.
    _devicesSubscription?.cancel();
    _devicesSubscription = null;

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
    _lastAlertTime.clear();
    _isRunning = false;
    _onDeviationDetected = null;
    debugPrint('[PathMonitor] Stopped');
  }

  // FIX #10: saveSosAlert was called from ChildCard._listenToSOS() but was
  // missing from this service, meaning SOS events were never persisted to
  // alertLogs. Implemented here using the same _saveAlertToRTDB path used
  // by deviation alerts so all alert types share one write path.
  Future<void> saveSosAlert({
    required String deviceCode,
    required String childName,
    double? latitude,
    double? longitude,
  }) async {
    final locationNote = (latitude != null && longitude != null)
        ? ' Last known position: ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}.'
        : '';

    await _saveAlertToRTDB(
      deviceCode: deviceCode,
      childName: childName,
      type: 'sos',
      message: '$childName has triggered an SOS alert.$locationNote '
          'Please check their location immediately.',
      latitude: latitude,
      longitude: longitude,
    );
  }

  // ── Internal ──────────────────────────────────────────────────

  /// Listen to linkedDevices and set up per-device monitors.
  Future<void> _subscribeToDevices(String userId) async {
    final devicesRef = FirebaseDatabase.instance
        .ref('linkedDevices')
        .child(userId)
        .child('devices');

    // FIX #9: Assign to _devicesSubscription so stop() can cancel it.
    // Previously the return value was discarded, making the listener
    // impossible to cancel and allowing it to outlive the service's
    // logical lifetime.
    _devicesSubscription = devicesRef.onValue.listen(
      (event) async {
        // FIX #9 (cont): Wrap in try/catch because async listener exceptions
        // are silently swallowed by StreamSubscription. Without this, any
        // error inside the callback (e.g. bad cast) would stop the listener
        // without any visible indication in logs.
        try {
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

            if (!isEnabled) {
              if (_logListeners.containsKey(deviceCode)) {
                _logListeners[deviceCode]?.cancel();
                _logListeners.remove(deviceCode);
                _routeListeners[deviceCode]?.cancel();
                _routeListeners.remove(deviceCode);
                _routeCache.remove(deviceCode);
                _lastLogKey.remove(deviceCode);
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

          // Cancel listeners for removed devices.
          final removedCodes =
              _logListeners.keys.toSet().difference(currentCodes);
          for (final code in removedCodes) {
            _logListeners[code]?.cancel();
            _logListeners.remove(code);
            _routeListeners[code]?.cancel();
            _routeListeners.remove(code);
            _routeCache.remove(code);
            _lastLogKey.remove(code);
            debugPrint('[PathMonitor] Removed listener for $code');
          }
        } catch (e, stack) {
          debugPrint('[PathMonitor] Error in devices listener: $e\n$stack');
        }
      },
      onError: (Object error) {
        debugPrint('[PathMonitor] Devices stream error: $error');
      },
    );
  }

  /// Cache routes for [deviceCode] and refresh when they change.
  Future<void> _subscribeToRoutes(
      String userId, String deviceCode) async {
    final routesRef = FirebaseDatabase.instance
        .ref('devicePaths')
        .child(userId)
        .child(deviceCode);

    final initialSnap = await routesRef.get();
    _routeCache[deviceCode] = _parseRoutesSnapshot(deviceCode, initialSnap);

    final sub = routesRef.onValue.listen((event) {
      _routeCache[deviceCode] =
          _parseRoutesSnapshot(deviceCode, event.snapshot);
    });

    _routeListeners[deviceCode] = sub;
  }

  /// Parse a devicePaths snapshot into a list of active _RouteData.
  List<_RouteData> _parseRoutesSnapshot(
      String deviceCode, DataSnapshot snapshot) {
    if (!snapshot.exists || snapshot.value == null) return [];

    final routesData = snapshot.value as Map<dynamic, dynamic>;
    final routes = <_RouteData>[];

    for (final entry in routesData.entries) {
      final data = entry.value as Map<dynamic, dynamic>;
      final isActive = data['isActive'] as bool? ?? true;
      if (!isActive) continue;

      final threshold =
          (data['deviationThresholdMeters'] as num?)?.toDouble() ?? 50.0;
      final pathName = data['pathName']?.toString() ?? 'Unnamed Route';
      final waypoints = _parseWaypoints(data['waypoints']);
      if (waypoints.length < 2) continue;

      routes.add(_RouteData(
        routeId: entry.key.toString(),
        pathName: pathName,
        thresholdMeters: threshold,
        waypoints: waypoints,
      ));
    }

    debugPrint(
        '[PathMonitor] Cached ${routes.length} active route(s) for $deviceCode');
    return routes;
  }

  /// Listen to the latest log entry for [deviceCode].
  void _subscribeToLogs(
      String userId, String deviceCode, String childName) {
    final logsRef = FirebaseDatabase.instance
        .ref('deviceLogs')
        .child(userId)
        .child(deviceCode);

    final sub = logsRef.limitToLast(1).onChildAdded.listen((event) {
      final logKey = event.snapshot.key ?? '';
      if (_lastLogKey[deviceCode] == logKey) return;
      _lastLogKey[deviceCode] = logKey;

      final logData = event.snapshot.value as Map<dynamic, dynamic>?;
      if (logData == null) return;

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
      // HaversineService.distanceToPath returns distance in meters.
      final distance =
          HaversineService.distanceToPath(position, route.waypoints);

      debugPrint('[PathMonitor] $childName ($deviceCode) → '
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
    final cooldownKey = '$deviceCode:${route.routeId}';
    final lastAlert = _lastAlertTime[cooldownKey];

    if (lastAlert != null &&
        now.difference(lastAlert) < _alertCooldown) {
      debugPrint(
          '[PathMonitor] Deviation for $deviceCode suppressed (cooldown)');
      return;
    }

    _lastAlertTime[cooldownKey] = now;

    final event = DeviationEvent(
      deviceCode: deviceCode,
      childName: childName,
      position: position,
      distanceMeters: distanceMeters,
      thresholdMeters: route.thresholdMeters,
      routeName: route.pathName,
      detectedAt: now,
    );

    debugPrint('[PathMonitor] ⚠️ DEVIATION: $childName is '
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

  /// Write alert entry to RTDB.
  /// Path: alertLogs/{userId}/{deviceCode}/{pushId}
  Future<void> _saveAlertToRTDB({
    required String deviceCode,
    required String childName,
    required String type,
    required String message,
    double? distanceMeters,
    String? routeName,
    double? latitude,
    double? longitude,
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
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      });
      debugPrint('[PathMonitor] Alert saved to RTDB: $type for $childName');
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
      wpMaps.addAll(sorted.map((e) => e.value as Map<dynamic, dynamic>));
    } else if (raw is List) {
      wpMaps.addAll(raw.whereType<Map<dynamic, dynamic>>());
    }

    return wpMaps
        .map((wp) {
          final lat = (wp['latitude'] as num?)?.toDouble();
          final lng = (wp['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) {
            debugPrint(
                '[PathMonitor] _parseWaypoints: skipping malformed waypoint $wp');
            return null;
          }
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }
}

// ── Internal model ────────────────────────────────────────────
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