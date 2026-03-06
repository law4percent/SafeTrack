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
  ///
  /// FIX (critical): removed in-memory _lastCheckDate — replaced with RTDB
  /// existence check in _notYetFiredToday(). In-memory state is always empty
  /// in a workmanager isolate, so the old _shouldCheck() always returned true,
  /// causing alert spam (absent/late/anomaly re-firing every 15 min all day).
  ///
  /// FIX (minor): parallel device checks via Future.wait — was sequential.
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

      // FIX (minor): parallel — was `for (entry) { await _checkDevice(...) }`
      await Future.wait(
        devices.entries.map((entry) async {
          final deviceCode = entry.key.toString();
          final data = entry.value as Map<dynamic, dynamic>;

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

    // FIX (minor): limitToLast(200) — covers a full school day at 30s
    // intervals (~96 entries) with headroom. Was unbounded .get() which
    // downloaded the entire log history (thousands of entries after weeks).
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

        // Only today's calendar-day logs
        if (logDt.year  != now.year  ||
            logDt.month != now.month ||
            logDt.day   != now.day)  continue;

        // FIX B (part 1): Only live GPS fixes — firmware writes
        // locationType: "gps" | "cached". Cached entries reuse stale
        // coordinates/timestamps, causing false absent/late/anomaly results.
        final locationType = log['locationType']?.toString() ?? 'cached';
        final isGps = locationType == 'gps';

        // FIX B (part 2): Exclude SOS logs — device is in emergency mode;
        // its timing should not feed late/absent/anomaly logic.
        final sosVal = log['sos'];
        final isSos  = sosVal == true || sosVal == 'true';

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
      // FIX B (part 3): schoolHourGpsLogs guaranteed GPS-only — safe to sort.
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
    // FIX B (part 4): todayLogs is GPS+non-SOS only — cached logs replayed
    // at 22:00 can no longer trigger false anomaly alerts.
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

      // FIX A: deviceCode passed — notification_service.showBehaviorAlert
      // requires it (FIX 8) so payload is deviceCode, consistent with
      // deviation and SOS notifications.
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

  /// FIX (critical): RTDB-backed cooldown — replaces in-memory _lastCheckDate.
  ///
  /// Queries alertLogs/{userId}/{deviceCode} for any entry where type matches
  /// AND timestamp falls within today's calendar day. Returns true (proceed)
  /// only when no such entry exists.
  ///
  /// Isolate-safe: reads from RTDB which persists across workmanager task
  /// restarts. The old in-memory map was always empty in background isolates,
  /// making every 15-min task fire every alert type again.
  Future<bool> _notYetFiredToday(
      String userId, String deviceCode, String type) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('alertLogs')
          .child(userId)
          .child(deviceCode)
          .get();

      if (!snap.exists || snap.value == null) return true;

      final entries    = snap.value as Map<dynamic, dynamic>;
      final now        = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day)
          .millisecondsSinceEpoch;
      final todayEnd   = todayStart + const Duration(days: 1).inMilliseconds;

      for (final entry in entries.values) {
        if (entry is! Map) continue;
        if (entry['type']?.toString() != type) continue;
        final ts = (entry['timestamp'] as num?)?.toInt() ?? 0;
        if (ts >= todayStart && ts < todayEnd) return false; // already fired
      }
      return true;
    } catch (e) {
      debugPrint('[BehaviorMonitor] _notYetFiredToday error: $e');
      return true; // fail-open: allow check on error
    }
  }

  /// Parse "HH:MM" into a DateTime (date part is today).
  /// Same format written by my_children_screen.dart formatTimeOfDay()
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