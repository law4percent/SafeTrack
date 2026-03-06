// lib/services/behavior_monitor_service.dart
//
// Feature 2 — Behavior Monitor
// Checks child behavior against school schedule:
//   • Late    — no GPS ping near route after schoolTimeIn + 15 min grace
//   • Absent  — zero GPS pings during school hours
//   • Anomaly — movement detected outside school hours (e.g., 22:00)
//
// Runs once per session when the app starts (called from main.dart or
// background_monitor_service.dart). Checks are cooldown-gated (1 per day
// per type per device) to avoid repeated alerts for the same school day.
//
// RTDB write:
//   alertLogs/{userId}/{deviceCode}/{pushId}
//     type, childName, message, timestamp
//
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';

class BehaviorMonitorService {
  // ── Singleton ─────────────────────────────────────────────────
  static final BehaviorMonitorService _instance =
      BehaviorMonitorService._internal();
  factory BehaviorMonitorService() => _instance;
  BehaviorMonitorService._internal();

  // Tracks last behavior check date per (deviceCode + type) to avoid
  // triggering the same alert multiple times in the same school day.
  final Map<String, DateTime> _lastCheckDate = {};

  // ── Public API ────────────────────────────────────────────────

  /// Call this once after app launch (and from background worker).
  /// Checks all enabled devices that have school schedule set.
  Future<void> runChecks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final devSnap = await FirebaseDatabase.instance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .get();

      if (!devSnap.exists) return;
      final devices = devSnap.value as Map<dynamic, dynamic>;

      for (final entry in devices.entries) {
        final deviceCode = entry.key.toString();
        final data = entry.value as Map<dynamic, dynamic>;

        final isEnabled = data['deviceEnabled']?.toString() == 'true';
        if (!isEnabled) continue;

        final childName = data['childName']?.toString() ?? 'Unknown';
        final timeInStr  = data['schoolTimeIn']?.toString()  ?? '';
        final timeOutStr = data['schoolTimeOut']?.toString() ?? '';

        // Skip if schedule not configured
        if (timeInStr.isEmpty || timeOutStr.isEmpty) continue;

        final timeIn  = _parseHHMM(timeInStr);
        final timeOut = _parseHHMM(timeOutStr);
        if (timeIn == null || timeOut == null) continue;

        await _checkDevice(
          userId: user.uid,
          deviceCode: deviceCode,
          childName: childName,
          schoolTimeIn: timeIn,
          schoolTimeOut: timeOut,
        );
      }
    } catch (e) {
      debugPrint('[BehaviorMonitor] runChecks error: $e');
    }
  }

  // ── Per-device checks ─────────────────────────────────────────

  Future<void> _checkDevice({
    required String userId,
    required String deviceCode,
    required String childName,
    required DateTime schoolTimeIn,
    required DateTime schoolTimeOut,
  }) async {
    final now = DateTime.now();
    final todayIn  = DateTime(now.year, now.month, now.day,
        schoolTimeIn.hour, schoolTimeIn.minute);
    final todayOut = DateTime(now.year, now.month, now.day,
        schoolTimeOut.hour, schoolTimeOut.minute);
    final graceEnd = todayIn.add(const Duration(minutes: 15));

    // Fetch today's logs for this device
    final logsSnap = await FirebaseDatabase.instance
        .ref('deviceLogs')
        .child(userId)
        .child(deviceCode)
        .get();

    final todayLogs        = <Map<dynamic, dynamic>>[];
    final schoolHourGpsLogs = <Map<dynamic, dynamic>>[];

    if (logsSnap.exists && logsSnap.value is Map) {
      final raw = logsSnap.value as Map<dynamic, dynamic>;
      for (final e in raw.entries) {
        if (e.value is! Map) continue;
        final log = e.value as Map<dynamic, dynamic>;
        final ts = (log['timestamp'] as num?)?.toInt() ?? 0;
        if (ts == 0) continue;
        final logDt = DateTime.fromMillisecondsSinceEpoch(ts);

        // Only today's logs
        if (logDt.year != now.year ||
            logDt.month != now.month ||
            logDt.day != now.day) continue;

        // FIX B (part 1): Only count live GPS fixes for behavior analysis.
        // Firmware writes locationType: "gps" | "cached".
        // Cached entries reuse stale coordinates and timestamps — including
        // them in absent/late/anomaly checks produces false results:
        //   • Absent: a cached log makes the child appear present when they're not.
        //   • Late:   a cached log with an early timestamp makes a late child appear on time.
        //   • Anomaly: a cached log replayed at 22:00 fires a false outside-hours alert.
        // Same guard applied in path_monitor_service for deviation checks.
        final locationType = log['locationType']?.toString() ?? 'cached';
        final isGps = locationType == 'gps';

        // FIX B (part 2): Also exclude SOS logs from behavior analysis.
        // When SOS is active the device is in emergency mode — its position
        // and timing should not feed into late/absent/anomaly logic.
        // Same guard applied in path_monitor_service.
        final sosVal = log['sos'];
        final isSos = sosVal == true || sosVal == 'true';

        if (!isGps || isSos) continue;

        todayLogs.add(log);

        if (logDt.isAfter(todayIn) && logDt.isBefore(todayOut)) {
          schoolHourGpsLogs.add(log);
        }
      }
    }

    // ── CHECK 1: Absent ──────────────────────────────────────────
    // Zero live GPS pings during school hours after grace period ends.
    if (now.isAfter(graceEnd) &&
        now.isBefore(todayOut) &&
        schoolHourGpsLogs.isEmpty &&
        _shouldCheck(deviceCode, 'absent')) {
      await _fireAlert(
        userId: userId,
        deviceCode: deviceCode,
        childName: childName,
        type: 'absent',
        message: '$childName has not been detected during school hours today '
            '(${_fmt(todayIn)} – ${_fmt(todayOut)}). '
            'They may be absent. Please verify.',
      );
    }

    // ── CHECK 2: Late ────────────────────────────────────────────
    // First live GPS ping during school hours is after graceEnd.
    if (schoolHourGpsLogs.isNotEmpty && _shouldCheck(deviceCode, 'late')) {
      // FIX B (part 3): Sort only GPS-verified logs — already guaranteed
      // by schoolHourGpsLogs containing only isGps == true entries.
      final sorted = List<Map<dynamic, dynamic>>.from(schoolHourGpsLogs)
        ..sort((a, b) {
          final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
          final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
          return ta.compareTo(tb);
        });
      final firstTs = (sorted.first['timestamp'] as num?)?.toInt() ?? 0;
      final firstDt = DateTime.fromMillisecondsSinceEpoch(firstTs);
      if (firstDt.isAfter(graceEnd)) {
        final lateBy = firstDt.difference(todayIn).inMinutes;
        await _fireAlert(
          userId: userId,
          deviceCode: deviceCode,
          childName: childName,
          type: 'late',
          message: '$childName\'s device was first detected at ${_fmt(firstDt)}, '
              'which is $lateBy minutes after school start time (${_fmt(todayIn)}). '
              'They may have arrived late.',
        );
      }
    }

    // ── CHECK 3: Anomaly ─────────────────────────────────────────
    // Live GPS movement detected at suspicious hours (after 22:00 or before 05:00).
    // FIX B (part 4): todayLogs now contains only GPS+non-SOS entries so
    // a cached log replayed at 22:00 can no longer trigger a false anomaly.
    if (_shouldCheck(deviceCode, 'anomaly')) {
      final suspiciousStart =
          DateTime(now.year, now.month, now.day, 22, 0);
      final suspiciousEnd =
          DateTime(now.year, now.month, now.day, 5, 0);

      final anomalyLogs = todayLogs.where((log) {
        final ts = (log['timestamp'] as num?)?.toInt() ?? 0;
        if (ts == 0) return false;
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        return dt.isAfter(suspiciousStart) ||
            dt.isBefore(suspiciousEnd);
      }).toList();

      if (anomalyLogs.isNotEmpty) {
        final ts =
            (anomalyLogs.first['timestamp'] as num?)?.toInt() ?? 0;
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        await _fireAlert(
          userId: userId,
          deviceCode: deviceCode,
          childName: childName,
          type: 'anomaly',
          message: '$childName\'s device detected movement at ${_fmt(dt)}, '
              'which is outside normal school hours. '
              'Please verify their whereabouts.',
        );
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  /// Write alert to RTDB and push local notification.
  Future<void> _fireAlert({
    required String userId,
    required String deviceCode,
    required String childName,
    required String type,
    required String message,
  }) async {
    try {
      // Save to RTDB — same schema as path_monitor_service._saveAlertToRTDB
      // and alert_screen._AlertEntry expects.
      final ref = FirebaseDatabase.instance
          .ref('alertLogs')
          .child(userId)
          .child(deviceCode)
          .push();
      await ref.set({
        'type': type,
        'childName': childName,
        'message': message,
        'timestamp': ServerValue.timestamp,
      });

      // FIX A: Pass deviceCode to showBehaviorAlert.
      // notification_service.showBehaviorAlert now requires deviceCode
      // (added in FIX 8) so the notification payload is deviceCode,
      // consistent with deviation and SOS alerts. Without this the
      // call would not compile after the notification_service fix.
      await NotificationService().showBehaviorAlert(
        childName: childName,
        deviceCode: deviceCode, // FIX A: was missing — causes compile error
        type: type,
        message: message,
      );

      // Mark as checked for today
      _lastCheckDate['${deviceCode}_$type'] = DateTime.now();
      debugPrint('[BehaviorMonitor] $type alert fired for $childName');
    } catch (e) {
      debugPrint('[BehaviorMonitor] Failed to fire alert: $e');
    }
  }

  /// Returns true if this check hasn't run today for this device+type.
  /// NOTE: _lastCheckDate is in-memory. If the app is killed and relaunched
  /// on the same school day, checks will re-run. For a production app,
  /// persist this to RTDB or SharedPreferences keyed by date string.
  bool _shouldCheck(String deviceCode, String type) {
    final key = '${deviceCode}_$type';
    final last = _lastCheckDate[key];
    if (last == null) return true;
    final now = DateTime.now();
    return last.day != now.day ||
        last.month != now.month ||
        last.year != now.year;
  }

  /// Parse "HH:MM" into a DateTime (date part is today).
  /// Same format written by my_children_screen.dart LinkedDevice.formatTimeOfDay()
  /// and read by gemini_service._buildFirebaseContext().
  DateTime? _parseHHMM(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, h, m);
  }

  /// Format DateTime as "HH:MM".
  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}