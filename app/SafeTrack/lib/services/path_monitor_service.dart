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

  /// Cooldown tracker: deviceCode → last deviation notification time.
  /// Prevents spamming the parent with repeated alerts.
  final Map<String, DateTime> _lastAlertTime = {};

  /// Minimum time between alerts for the same device (5 minutes).
  static const Duration _alertCooldown = Duration(minutes: 5);

  OnDeviationDetected? _onDeviationDetected;
  bool _isRunning = false;

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

      // Start new listeners for newly added devices
      for (final entry in devicesData.entries) {
        final deviceCode = entry.key.toString();
        final deviceData = entry.value as Map<dynamic, dynamic>;
        final isEnabled =
            deviceData['deviceEnabled']?.toString() == 'true';
        final childName =
            deviceData['childName']?.toString() ?? 'Unknown';

        if (!isEnabled) continue;

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

        final waypoints =
            _parseWaypoints(data['waypoints']);
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

      // Skip if we already processed this key
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

    _onDeviationDetected?.call(event);
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