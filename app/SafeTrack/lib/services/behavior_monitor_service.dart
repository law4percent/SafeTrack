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
// import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Used
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
        final timeInStr = data['schoolTimeIn']?.toString() ?? '';
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

    final todayLogs = <Map<dynamic, dynamic>>[];
    final schoolHourLogs = <Map<dynamic, dynamic>>[];

    if (logsSnap.exists && logsSnap.value is Map) {
      final raw = logsSnap.value as Map<dynamic, dynamic>;
      for (final e in raw.entries) {
        if (e.value is! Map) continue;
        final log = e.value as Map<dynamic, dynamic>;
        final ts = (log['timestamp'] as num?)?.toInt() ?? 0;
        if (ts == 0) continue;
        final logDt = DateTime.fromMillisecondsSinceEpoch(ts);
        // Only today's logs
        if (logDt.year == now.year &&
            logDt.month == now.month &&
            logDt.day == now.day) {
          todayLogs.add(log);
          if (logDt.isAfter(todayIn) && logDt.isBefore(todayOut)) {
            schoolHourLogs.add(log);
          }
        }
      }
    }

    // ── CHECK 1: Absent ──────────────────────────────────────
    // Zero pings during school hours and it's already past grace period
    if (now.isAfter(graceEnd) && now.isBefore(todayOut)) {
      if (schoolHourLogs.isEmpty && _shouldCheck(deviceCode, 'absent')) {
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
    }

    // ── CHECK 2: Late ────────────────────────────────────────
    // First ping today is after graceEnd (schoolTimeIn + 15 min)
    if (schoolHourLogs.isNotEmpty && _shouldCheck(deviceCode, 'late')) {
      final sortedLogs = List<Map<dynamic, dynamic>>.from(schoolHourLogs)
        ..sort((a, b) {
          final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
          final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
          return ta.compareTo(tb);
        });
      final firstTs =
          (sortedLogs.first['timestamp'] as num?)?.toInt() ?? 0;
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

    // ── CHECK 3: Anomaly ─────────────────────────────────────
    // Movement detected outside school hours (before 06:00 or after 20:00)
    // Using a "suspicious hours" window — adjustable
    final suspiciousStart = DateTime(now.year, now.month, now.day, 22, 0);
    // final suspiciousEnd   = DateTime(now.year, now.month, now.day, 5, 0) // Unused
        // .add(const Duration(days: 1)); // 05:00 next day

    if (_shouldCheck(deviceCode, 'anomaly')) {
      final anomalyLogs = todayLogs.where((log) {
        final ts = (log['timestamp'] as num?)?.toInt() ?? 0;
        if (ts == 0) return false;
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        return dt.isAfter(suspiciousStart) || dt.isBefore(
            DateTime(now.year, now.month, now.day, 5, 0));
      }).toList();

      if (anomalyLogs.isNotEmpty) {
        final ts = (anomalyLogs.first['timestamp'] as num?)?.toInt() ?? 0;
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
      // Save to RTDB
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

      // Push local notification
      await NotificationService().showBehaviorAlert(
        childName: childName,
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
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}