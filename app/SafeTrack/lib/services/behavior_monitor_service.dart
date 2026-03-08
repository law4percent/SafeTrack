// lib/services/behavior_monitor_service.dart
//
// Feature 2 — Behavior Monitor
// Checks child behavior against school schedule:
//   • Late    — no GPS ping near route after schoolTimeIn + 15 min grace
//   • Absent  — zero GPS pings during school hours
//   • Anomaly — movement detected outside school hours (e.g., 22:00)
//
// Safe to call from workmanager isolates — cooldown is persisted in RTDB
// (not in-memory) so it survives isolate restarts.
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

  // ── Public API ────────────────────────────────────────────────

  /// Call this once after app launch AND from the background workmanager task.
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

      await Future.wait(
        devices.entries.map((entry) async {
          final deviceCode = entry.key.toString();
          final data       = entry.value as Map<dynamic, dynamic>;

          final isEnabled = data['deviceEnabled']?.toString() == 'true';
          if (!isEnabled) return;

          final childName  = data['childName']?.toString()    ?? 'Unknown';
          final timeInStr  = data['schoolTimeIn']?.toString()  ?? '';
          final timeOutStr = data['schoolTimeOut']?.toString() ?? '';

          if (timeInStr.isEmpty || timeOutStr.isEmpty) return;

          final timeIn  = _parseHHMM(timeInStr);
          final timeOut = _parseHHMM(timeOutStr);
          if (timeIn == null || timeOut == null) return;

          await _checkDevice(
            userId: user.uid,
            deviceCode: deviceCode,
            childName: childName,
            schoolTimeIn: timeIn,
            schoolTimeOut: timeOut,
          );
        }),
      );
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
    final now      = DateTime.now();
    final todayIn  = DateTime(now.year, now.month, now.day,
        schoolTimeIn.hour, schoolTimeIn.minute);
    final todayOut = DateTime(now.year, now.month, now.day,
        schoolTimeOut.hour, schoolTimeOut.minute);
    final graceEnd = todayIn.add(const Duration(minutes: 15));

    final logsSnap = await FirebaseDatabase.instance
        .ref('deviceLogs')
        .child(userId)
        .child(deviceCode)
        .limitToLast(200)
        .get();

    final todayLogs         = <Map<dynamic, dynamic>>[];
    final schoolHourGpsLogs = <Map<dynamic, dynamic>>[];

    if (logsSnap.exists && logsSnap.value is Map) {
      final raw = logsSnap.value as Map<dynamic, dynamic>;
      for (final e in raw.entries) {
        if (e.value is! Map) continue;
        final log = e.value as Map<dynamic, dynamic>;
        final ts  = (log['timestamp'] as num?)?.toInt() ?? 0;
        if (ts == 0) continue;
        final logDt = DateTime.fromMillisecondsSinceEpoch(ts);

        if (logDt.year  != now.year  ||
            logDt.month != now.month ||
            logDt.day   != now.day)  continue;

        final locationType = log['locationType']?.toString() ?? 'cached';
        final isGps        = locationType == 'gps';
        final sosVal       = log['sos'];
        final isSos        = sosVal == true || sosVal == 'true';

        if (!isGps || isSos) continue;

        todayLogs.add(log);

        if (logDt.isAfter(todayIn) && logDt.isBefore(todayOut)) {
          schoolHourGpsLogs.add(log);
        }
      }
    }

    // ── CHECK 1: Absent ──────────────────────────────────────────
    if (now.isAfter(graceEnd) &&
        now.isBefore(todayOut) &&
        schoolHourGpsLogs.isEmpty &&
        await _notYetFiredToday(userId, deviceCode, 'absent')) {
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
    if (schoolHourGpsLogs.isNotEmpty &&
        await _notYetFiredToday(userId, deviceCode, 'late')) {
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
    if (await _notYetFiredToday(userId, deviceCode, 'anomaly')) {
      final suspiciousStart =
          DateTime(now.year, now.month, now.day, 22, 0);

      final anomalyLogs = todayLogs.where((log) {
        final ts = (log['timestamp'] as num?)?.toInt() ?? 0;
        if (ts == 0) return false;
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        return dt.isAfter(suspiciousStart) ||
            dt.isBefore(DateTime(now.year, now.month, now.day, 5, 0));
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

  Future<void> _fireAlert({
    required String userId,
    required String deviceCode,
    required String childName,
    required String type,
    required String message,
  }) async {
    try {
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

      await NotificationService().showBehaviorAlert(
        childName: childName,
        deviceCode: deviceCode,
        type: type,
        message: message,
      );

      debugPrint('[BehaviorMonitor] $type alert fired for $childName');
    } catch (e) {
      debugPrint('[BehaviorMonitor] Failed to fire alert: $e');
    }
  }

  /// FIX: Scoped alertLogs query — only downloads today's entries.
  ///
  /// Previous implementation fetched the ENTIRE alertLogs node for a device
  /// (unbounded .get()), which grew by ~3 entries per school day indefinitely.
  /// After 30 school days that was 90+ entries downloaded on every background
  /// task invocation just to check a boolean.
  ///
  /// Fix: orderByChild('timestamp').startAt(todayStart) limits the Firebase
  /// read to entries written today. The result is O(alerts today) instead of
  /// O(alerts all time).
  ///
  /// Isolate-safe: reads from RTDB which persists across workmanager restarts.
  Future<bool> _notYetFiredToday(
      String userId, String deviceCode, String type) async {
    try {
      final now        = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day)
          .millisecondsSinceEpoch
          .toDouble(); // startAt requires double

      // FIX: scope the query to today only — was an unbounded .get() that
      // downloaded the full alertLogs history for the device.
      final snap = await FirebaseDatabase.instance
          .ref('alertLogs')
          .child(userId)
          .child(deviceCode)
          .orderByChild('timestamp')
          .startAt(todayStart)
          .get();

      if (!snap.exists || snap.value == null) return true;

      final entries  = snap.value as Map<dynamic, dynamic>;
      final todayEnd = todayStart + const Duration(days: 1).inMilliseconds;

      for (final entry in entries.values) {
        if (entry is! Map) continue;
        if (entry['type']?.toString() != type) continue;
        final ts = (entry['timestamp'] as num?)?.toInt() ?? 0;
        if (ts >= todayStart && ts < todayEnd) return false;
      }
      return true;
    } catch (e) {
      debugPrint('[BehaviorMonitor] _notYetFiredToday error: $e');
      return true; // fail-open: allow check on error
    }
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
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}