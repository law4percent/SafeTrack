// app/SafeTrack/lib/services/gemini_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// =============================================================
// HARDCODED RAG KNOWLEDGE BASE
// All project knowledge injected as a system prompt variable.
// Covers tech stack, architecture, algorithms, and components
// so the AI can answer thesis-level technical questions.
// =============================================================
const String _kSafeTrackKnowledgeBase = r"""
# SafeTrack System Knowledge Base

## Project Overview
SafeTrack is an IoT-based child safety monitoring system developed as a Bachelor of Science in Computer Engineering thesis project at Cebu Technological University – Danao Campus. It helps parents of elementary school students monitor their child's real-time GPS location, register safe travel routes, receive deviation alerts, and query an AI assistant for safety insights.

## IoT Tracker Device (Hardware)
The child carries a custom-built portable tracker device:
- **ESP32-C3 Super Mini**: RISC-V 160MHz microcontroller running C/C++ Arduino firmware. Handles GPS parsing, battery reading, SOS detection, and Firebase HTTPS POST transmission.
- **SIM7600E-H1C**: 4G LTE module with built-in GPS. Transmits data to Firebase via HTTPS POST over cellular. GPS sentences are read via UART.
- **MAX17043**: LiPo battery fuel gauge IC (I2C). Provides accurate battery percentage to firmware and app.
- **TP4056**: LiPo battery charging module with overcharge protection.
- **MT3608**: DC-DC boost converter stepping 3.7V up to 5V for the SIM module.
- **LiFePO4 3.7V 2000mAh**: Primary power source. Approximately 8-12 hours continuous operation.
- **Push Button (SOS)**: GPIO interrupt on ESP32-C3. Pressing it sets an SOS flag in the Firebase payload, triggering an emergency alert in the parent app.

## Firmware
Language: C/C++ (Arduino framework for ESP32).
Operations: GPS NMEA parsing from SIM7600E-H1C via UART, battery % from MAX17043 via I2C, SOS button via GPIO interrupt, HTTPS POST to Firebase every ~30-60 seconds.

Sample JSON payload sent to Firebase:
{ "latitude": 10.3167, "longitude": 123.8907, "accuracy": 4.8, "speed": 0.0, "altitude": 11.2, "locationType": "gps", "battery": 84, "isSOS": false, "timestamp": 1709123456000 }

## Parent Mobile Application
Framework: Flutter (Dart), cross-platform, primary target Android API 21+.
State management: Provider pattern (ChangeNotifier).
Mapping: flutter_map + OpenStreetMap tiles (free, no API key).

### Screens
- dashboard_screen.dart: Overview of all children, battery, SOS, online status.
- live_location_screen.dart: Real-time map with route polylines, child marker, start/end markers.
- my_children_screen.dart: Device management and linking.
- route_registration_screen.dart: Tap-to-drop waypoint map editor with threshold slider.
- ask_ai_screen.dart: Gemini-powered AI chat interface.

### Services
- auth_service.dart: Firebase Authentication wrapper.
- gemini_service.dart: Gemini API integration with Firebase context and RAG knowledge base.
- haversine_service.dart: Pure Dart Haversine formula + perpendicular segment projection.
- path_monitor_service.dart: Singleton listening to deviceLogs, checks deviation against active routes.
- notification_service.dart: flutter_local_notifications for deviation and SOS alerts.
- background_monitor_service.dart: Workmanager periodic background deviation checks.

## Firebase Realtime Database Structure
- linkedDevices/{userId}/devices/{deviceCode}: childName, deviceEnabled.
- deviceLogs/{userId}/{deviceCode}/{pushId}: latitude, longitude, accuracy, speed, altitude, locationType, timestamp.
- linkedDevices/{userId}/devices/{deviceCode}/deviceStatus: batteryLevel, sos, lastUpdate, lastLocation (latitude/longitude/altitude).
- devicePaths/{userId}/{deviceCode}/{routeId}: pathName, deviationThresholdMeters, isActive, waypoints (wp_0, wp_1, ... as Map keys to prevent Firebase List conversion).

Offline persistence: 10MB cache enabled for resilience during brief connectivity loss.

## Geofencing Algorithm: Haversine + Perpendicular Segment Distance

### Why Haversine over Euclidean?
Euclidean distance treats GPS coordinates as flat Cartesian coordinates, introducing errors over distances greater than a few hundred meters. Haversine correctly computes the great-circle distance accounting for Earth's spherical surface, providing meter-level accuracy suitable for school route monitoring.

### Haversine Formula
a = sin^2(delta_lat/2) + cos(lat1) * cos(lat2) * sin^2(delta_lon/2)
c = 2 * asin(sqrt(a))
distance = Earth_radius_meters * c   (Earth radius = 6,371,000 m)

### Path Distance (Perpendicular Segment Projection)
Rather than measuring distance to waypoints only, SafeTrack measures perpendicular distance from the child's position to each route segment. For segment A to B and child position P:
1. Project P onto segment A-B: t = dot(P-A, B-A) / |B-A|^2
2. Clamp t to [0, 1] to stay within the segment.
3. Nearest point = A + t*(B-A).
4. Distance = Haversine(P, nearest_point).
The minimum across all segments is the child's deviation from the route. If it exceeds the threshold, an alert fires.

## Notification System
- flutter_local_notifications: deviation alerts (high priority) and SOS alerts (max priority, full-screen intent on Android).
- Two Android channels: safetrack_deviation and safetrack_sos.
- Workmanager: periodic background task every 15 minutes (Android minimum). Re-initializes Firebase, runs PathMonitorService for 10 seconds, fires notification if deviation detected.
- Deviation alert cooldown: 5 minutes per device to prevent spam.
- Tapping a notification navigates directly to the child's Live Location screen.

## AI Assistant
- Model: Google Gemini API
- Context: Real-time Firebase data (battery, location, SOS, last 10 log entries) fetched before each query.
- RAG: This knowledge base is injected as a hardcoded string variable in gemini_service.dart.
- Question categories: location/whereabouts, safety/emergency, battery/device, reassurance, child status, technical.
- Broad temporal questions: AI asks for time range clarification before answering.
- School hours awareness: AI asks parent to confirm school hours when answering time-sensitive questions.
- Every response ends with a relevant follow-up question.
- Conversation history maintained for multi-turn context (last 20 turns).

## Academic Context
- Degree: Bachelor of Science in Computer Engineering
- Institution: Cebu Technological University – Danao Campus
- Purpose: Thesis demonstrating integration of embedded systems, mobile development, cloud infrastructure, and AI.
- Target users: Parents of elementary school students in the Philippines.
""";

// =============================================================
// QUESTION CATEGORY
// =============================================================
enum _QuestionCategory {
  locationWhereabouts,
  safetyEmergency,
  batteryDevice,
  reassurance,
  childStatus,
  broadTemporal,
  technical,
  other,
}

// =============================================================
// GEMINI SERVICE
// =============================================================
// =============================================================
// AVAILABLE AI MODELS
// Shown to the user as friendly options in the model picker.
// Free-tier limits: RPM = requests per minute, RPD = per day.
// =============================================================
class GeminiModel {
  final String id;          // API model ID
  final String displayName; // Friendly name shown in UI
  final String description; // One-line plain-language description
  final String quota;       // e.g. "10 RPM · higher daily limit"
  final String badge;       // Short badge label e.g. "Fastest"

  const GeminiModel({
    required this.id,
    required this.displayName,
    required this.description,
    required this.quota,
    required this.badge,
  });

  String get endpointUrl =>
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$id:generateContent';
}

const List<GeminiModel> kGeminiModels = [
  GeminiModel(
    id: 'gemini-2.5-flash-lite',
    displayName: 'Quick & Efficient',
    description: 'Fastest responses, highest daily limit. '
        'Best when you need quick answers.',
    quota: '10 requests/min · most daily requests',
    badge: 'Fastest',
  ),
  GeminiModel(
    id: 'gemini-2.5-flash',
    displayName: 'Balanced',
    description: 'Great balance of speed and detail. '
        'Recommended for most questions.',
    quota: '5 requests/min · high daily limit',
    badge: 'Recommended',
  ),
  GeminiModel(
    id: 'gemini-3-flash-preview',
    displayName: 'Most Detailed',
    description: 'Deepest reasoning and most thorough answers. '
        'Use when you need the most accurate response.',
    quota: '5 requests/min · lower daily limit',
    badge: 'Most Accurate',
  ),
];

// Returned by sendMessage() when the API responds with HTTP 429
// (rate limit / quota exhausted). The UI detects this exact string
// to show the model-switcher prompt instead of a generic error.
const String kGeminiRateLimitError = '__RATE_LIMIT__';

// =============================================================
// GEMINI SERVICE
// =============================================================
class GeminiService {
  // Default model — Balanced is the best starting point
  GeminiModel _selectedModel = kGeminiModels[1];

  GeminiModel get selectedModel => _selectedModel;

  /// Called by the UI when the parent picks a different model.
  void setModel(GeminiModel model) {
    _selectedModel = model;
  }

  final List<Map<String, dynamic>> _conversationHistory = [];
  bool _awaitingTimeRangeClarification = false;
  String? _pendingBroadQuestion;

  // ── Public: send message ─────────────────────────────────────
  Future<String> sendMessage(String userMessage) async {
    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        return 'AI service is not configured. Please check your setup.';
      }

      // If we asked for time-range clarification, process the answer
      if (_awaitingTimeRangeClarification &&
          _pendingBroadQuestion != null) {
        final enrichedQuestion =
            '$_pendingBroadQuestion (Time range specified by parent: $userMessage)';
        _awaitingTimeRangeClarification = false;
        _pendingBroadQuestion = null;
        return await _sendToGemini(enrichedQuestion, apiKey);
      }

      // Check if this is a broad temporal question needing clarification
      final category = _categorizeQuestion(userMessage);
      if (category == _QuestionCategory.broadTemporal) {
        _awaitingTimeRangeClarification = true;
        _pendingBroadQuestion = userMessage;
        return _buildClarificationPrompt();
      }

      return await _sendToGemini(userMessage, apiKey);
    } catch (e) {
      debugPrint('[GeminiService] sendMessage error: $e');
      return 'Something went wrong. Please try again.';
    }
  }

  // ── Categorize question ──────────────────────────────────────
  _QuestionCategory _categorizeQuestion(String message) {
    final q = message.toLowerCase();

    // Broad temporal — needs clarification unless time range given
    final broadPatterns = [
      'behavior', 'how was', 'what did my child do',
      'movement history', 'tell me about', 'show me the history',
      'what happened', 'activity', 'how has my child been',
      'logs for', 'report on',
    ];
    if (_matchesAny(q, broadPatterns) && !_containsTimeRange(q)) {
      return _QuestionCategory.broadTemporal;
    }

    if (_matchesAny(q, [
      'where is', 'location', 'whereabouts', 'inside the school',
      'school premises', 'left the school', 'geofence',
      'movement history', 'after recess', 'boundary',
      'showing a different', 'how accurate', 'how often',
      'delay', 'went after', 'tracking',
    ])) return _QuestionCategory.locationWhereabouts;

    if (_matchesAny(q, [
      'emergency', 'sos', 'press', 'emergency button',
      'unusual movement', 'loses signal', 'contact my child',
      'should i do if', 'confirm.*safe', 'notif',
    ])) return _QuestionCategory.safetyEmergency;

    if (_matchesAny(q, [
      'battery', 'running low', 'how long does', 'turned off',
      'not showing', 'device status', 'tracker not', 'powered',
    ])) return _QuestionCategory.batteryDevice;

    if (_matchesAny(q, [
      'is my child safe', 'any problem', 'in the classroom',
      'unusual activity', 'confirm that', 'is there any',
    ])) return _QuestionCategory.reassurance;

    if (_matchesAny(q, [
      'arrived at school', 'inside the school', 'left the school',
      'left the campus', 'what time did', 'already inside',
      'has my child arrived', 'has my child left',
    ])) return _QuestionCategory.childStatus;

    if (_matchesAny(q, [
      'algorithm', 'haversine', 'tech stack', 'framework',
      'how does', 'how is this built', 'firebase', 'flutter',
      'esp32', 'iot', 'architecture', 'system work',
      'how does the app', 'programming', 'thesis', 'distance',
    ])) return _QuestionCategory.technical;

    return _QuestionCategory.other;
  }

  bool _containsTimeRange(String q) => _matchesAny(q, [
        'yesterday', 'today', 'last week', 'last month',
        'this morning', 'this afternoon', 'past hour',
        'past day', 'this week', 'recent',
      ]);

  bool _matchesAny(String text, List<String> patterns) =>
      patterns.any((p) => text.contains(p));

  String _buildClarificationPrompt() =>
      'To give you accurate information, could you tell me which '
      'time period you\'d like me to check?\n\n'
      '• **Today**\n'
      '• **Yesterday**\n'
      '• **Last week**\n'
      '• **Last month**\n\n'
      'Just reply with your preferred time range and I\'ll look '
      'into it right away.';

  // ── Parse natural language date range to timestamps ─────────
  /// Returns [startMs, endMs] in milliseconds, or null if no
  /// recognizable time reference found in the message.
  List<int>? _parseDateRange(String message) {
    final q = message.toLowerCase();
    final now = DateTime.now();

    // "first week of april 2025" / "second week of march 2024"
    final weekOfMonthRx = RegExp(
        r'(first|second|third|fourth|last)\s+week\s+of\s+'
        r'(january|february|march|april|may|june|july|august|'
        r'september|october|november|december)\s+(\d{4})');
    final wom = weekOfMonthRx.firstMatch(q);
    if (wom != null) {
      final weekWord = wom.group(1)!;
      final monthWord = wom.group(2)!;
      final year = int.parse(wom.group(3)!);
      final month = _monthIndex(monthWord);
      final weekNum = {'first': 1, 'second': 2, 'third': 3,
          'fourth': 4, 'last': 4}[weekWord]!;
      final startDay = (weekNum - 1) * 7 + 1;
      final endDay = startDay + 6;
      final start = DateTime(year, month, startDay);
      final end = DateTime(year, month,
          endDay.clamp(1, _daysInMonth(year, month)), 23, 59, 59);
      return [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }

    // "april 2025" / "march 2024" — full month
    final monthYearRx = RegExp(
        r'(january|february|march|april|may|june|july|august|'
        r'september|october|november|december)\s+(\d{4})');
    final my = monthYearRx.firstMatch(q);
    if (my != null) {
      final month = _monthIndex(my.group(1)!);
      final year = int.parse(my.group(2)!);
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month,
          _daysInMonth(year, month), 23, 59, 59);
      return [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }

    // "last week"
    if (q.contains('last week')) {
      final start = now.subtract(const Duration(days: 7));
      return [_startOfDay(start), _endOfDay(now)];
    }

    // "last month"
    if (q.contains('last month')) {
      final start = DateTime(now.year, now.month - 1, 1);
      final end = DateTime(now.year, now.month, 1)
          .subtract(const Duration(seconds: 1));
      return [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }

    // "yesterday"
    if (q.contains('yesterday')) {
      final yesterday = now.subtract(const Duration(days: 1));
      return [_startOfDay(yesterday), _endOfDay(yesterday)];
    }

    // "today" / "right now" / no date = last 24 hours
    if (q.contains('today') || q.contains('right now') ||
        q.contains('current') || q.contains('now')) {
      return [_startOfDay(now), _endOfDay(now)];
    }

    // "past N days/hours"
    final pastRx = RegExp(r'past\s+(\d+)\s+(day|hour|week)s?');
    final past = pastRx.firstMatch(q);
    if (past != null) {
      final n = int.parse(past.group(1)!);
      final unit = past.group(2)!;
      Duration dur;
      if (unit == 'hour') dur = Duration(hours: n);
      else if (unit == 'week') dur = Duration(days: n * 7);
      else dur = Duration(days: n);
      return [now.subtract(dur).millisecondsSinceEpoch,
              now.millisecondsSinceEpoch];
    }

    return null; // no recognizable time reference
  }

  int _startOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
  int _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59)
          .millisecondsSinceEpoch;

  int _monthIndex(String name) {
    const months = ['january','february','march','april','may',
        'june','july','august','september','october',
        'november','december'];
    return months.indexOf(name) + 1;
  }

  int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  // ── Safe int cast ────────────────────────────────────────────
  int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  // ── Feature 3: Human-readable timestamp ──────────────────────
  // Converts raw millisecond timestamps to natural language.
  // Examples: "today at 07:30", "yesterday at 15:45", "03 Jan 2025, 08:00"
  String _formatTimestamp(int ms) {
    if (ms <= 0) return 'unknown time';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24 && dt.day == now.day) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'today at $h:$m';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.day == yesterday.day &&
        dt.month == yesterday.month &&
        dt.year == yesterday.year) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'yesterday at $h:$m';
    }
    final day  = dt.day.toString().padLeft(2, '0');
    final mon  = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$day $mon ${dt.year}, $h:$m';
  }

  // ── Feature 3: Friendly battery description ───────────────────
  String _batteryLabel(dynamic raw) {
    final pct = (raw is num) ? raw.toInt() : int.tryParse(raw.toString()) ?? -1;
    if (pct < 0)  return 'unknown';
    if (pct <= 10) return '$pct% — critically low, charge immediately';
    if (pct <= 25) return '$pct% — low, please charge soon';
    if (pct <= 50) return '$pct% — moderate';
    return '$pct% — good';
  }

  Future<String> _buildFirebaseContext({
    String originalQuestion = '',
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'No authenticated user found.';

      // ✅ FIX 1: Inject parent identity so AI knows who it's talking to
      final parentName = user.displayName?.isNotEmpty == true
          ? user.displayName!
          : user.email ?? 'the parent';

      final devicesSnap = await FirebaseDatabase.instance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .get();

      if (!devicesSnap.exists) return 'No linked devices found for this account.';

      final devicesData =
          devicesSnap.value as Map<dynamic, dynamic>;
      final buf = StringBuffer();

      buf.writeln('## Parent Account');
      buf.writeln('- Name / Email: $parentName');
      buf.writeln('- UID: ${user.uid}');
      buf.writeln('- Linked children: ${devicesData.length}');
      buf.writeln('');
      buf.writeln('## Live Device Data (from Firebase)\n');

      for (final entry in devicesData.entries) {
        final deviceCode = entry.key.toString();
        final meta = entry.value as Map<dynamic, dynamic>;
        final childName = meta['childName']?.toString() ?? 'Unknown';
        final isEnabled =
            meta['deviceEnabled']?.toString() == 'true';

        buf.writeln('### Child: $childName (Device Code: $deviceCode)');
        buf.writeln('- Tracking: ${isEnabled ? "Enabled" : "Disabled"}');

        // Feature 1 — School schedule (parent-configured)
        // AI reads this directly — no need to ask parent for school hours.
        final timeIn  = meta['schoolTimeIn']?.toString()  ?? '';
        final timeOut = meta['schoolTimeOut']?.toString() ?? '';
        if (timeIn.isNotEmpty && timeOut.isNotEmpty) {
          buf.writeln('- School Time In:  $timeIn (24hr)');
          buf.writeln('- School Time Out: $timeOut (24hr)');
          // Compute whether device is currently in school hours
          try {
            final now = DateTime.now();
            List<int> splitHHMM(String hhmm) {
              final p = hhmm.split(':');
              return [int.parse(p[0]), int.parse(p[1])];
            }
            final inP  = splitHHMM(timeIn);
            final outP = splitHHMM(timeOut);
            final schoolStart = DateTime(now.year, now.month, now.day, inP[0], inP[1]);
            final schoolEnd   = DateTime(now.year, now.month, now.day, outP[0], outP[1]);
            final inSchool    = now.isAfter(schoolStart) && now.isBefore(schoolEnd);
            buf.writeln('- Currently within school hours: ${inSchool ? "Yes" : "No"}');
            buf.writeln('- School day ended today: ${now.isAfter(schoolEnd) ? "Yes" : "No"}');
          } catch (_) {}
        } else {
          buf.writeln('- School schedule: Not configured by parent');
        }

        // ── Device status (battery, SOS) ─────────────────────
        // ✅ Reads from correct RTDB path:
        //    linkedDevices/{uid}/devices/{deviceCode}/deviceStatus
        // ✅ Correct field names: batteryLevel, sos
        try {
          final statusSnap = await FirebaseDatabase.instance
              .ref('linkedDevices')
              .child(user.uid)
              .child('devices')
              .child(deviceCode)
              .child('deviceStatus')
              .get();
          if (statusSnap.exists) {
            final s = statusSnap.value as Map<dynamic, dynamic>;
            final isSOS   = s['sos'] as bool? ?? false;
            final lastTs  = _toInt(s['lastUpdate']);
            final isOnline = lastTs > 0 &&
                DateTime.now()
                    .difference(DateTime.fromMillisecondsSinceEpoch(lastTs))
                    .inMinutes < 5;
            // Feature 3 — human-readable battery + timestamp
            final batteryDesc = _batteryLabel(s['batteryLevel']);
            final lastSeenDesc = lastTs > 0
                ? _formatTimestamp(lastTs)
                : 'never';
            // Feature 5 — explicit flags so AI can trigger actionable steps
            final batteryPct = (s['batteryLevel'] is num)
                ? (s['batteryLevel'] as num).toInt() : -1;
            buf.writeln('- Battery: $batteryDesc');
            buf.writeln('- Battery level (numeric): $batteryPct');
            buf.writeln('- Battery is low: ${batteryPct >= 0 && batteryPct <= 10 ? "YES — action needed" : "No"}');
            buf.writeln('- SOS Active: ${isSOS ? "YES — EMERGENCY" : "No"}');
            buf.writeln('- Device online: ${isOnline ? "Yes" : "No"}');
            buf.writeln('- Last update received: $lastSeenDesc');
            buf.writeln('- Needs attention: ${!isOnline ? "YES — device offline" : "No"}');
            // Surface lastLocation from deviceStatus
            final ll = s['lastLocation'];
            if (ll is Map) {
              final llLat = (ll['latitude']  as num?)?.toDouble() ?? 0;
              final llLng = (ll['longitude'] as num?)?.toDouble() ?? 0;
              if (llLat != 0 && llLng != 0) {
                buf.writeln('- Last known position: Lat $llLat, Lng $llLng');
              }
            }
          } else {
            buf.writeln('- Battery: Device has not synced yet');
            buf.writeln('- Device online: No');
            buf.writeln('- Needs attention: YES — no sync data');
          }
        } catch (e) {
          buf.writeln('- Battery: Error reading status');
          debugPrint('[GeminiService] Status read error: $e');
        }

        // ── GPS logs (date-range aware) ────────────────────────
        // Uses _parseDateRange to extract a timestamp window from
        // the original user message, then filters client-side.
        // No server-side orderByChild needed — avoids index errors.
        try {
          final logsSnap = await FirebaseDatabase.instance
              .ref('deviceLogs')
              .child(user.uid)
              .child(deviceCode)
              .get();

          if (logsSnap.exists && logsSnap.value != null) {
            final raw = logsSnap.value;

            List<Map<dynamic, dynamic>> allLogs = [];
            if (raw is Map) {
              for (final e in (raw as Map<dynamic, dynamic>).entries) {
                if (e.value is Map) {
                  allLogs.add(e.value as Map<dynamic, dynamic>);
                }
              }
            } else if (raw is List) {
              for (final item in raw) {
                if (item is Map) {
                  allLogs.add(item as Map<dynamic, dynamic>);
                }
              }
            }

            if (allLogs.isEmpty) {
              buf.writeln('- GPS logs: No valid entries found');
            } else {
              // Sort all logs descending by timestamp
              allLogs.sort((a, b) {
                final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
                final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
                return tb.compareTo(ta);
              });

              // Apply date-range filter if the user question
              // contains a recognizable time reference
              final dateRange = _parseDateRange(originalQuestion);
              List<Map<dynamic, dynamic>> filtered;

              if (dateRange != null) {
                final startMs = dateRange[0];
                final endMs = dateRange[1];
                filtered = allLogs.where((log) {
                  final ts = (log['timestamp'] as num?)?.toInt() ?? 0;
                  return ts >= startMs && ts <= endMs;
                }).toList();

                // Feature 3 — format date range nicely
                final startFmt = _formatTimestamp(startMs);
                final endFmt   = _formatTimestamp(endMs);
                buf.writeln(
                    '- Date range filter applied: $startFmt → $endFmt');
                buf.writeln(
                    '- Matching log entries: ${filtered.length}');
              } else {
                // No date filter — use latest 10 entries
                filtered = allLogs.take(10).toList();
                buf.writeln(
                    '- Showing latest ${filtered.length} log entries');
              }

              if (filtered.isEmpty) {
                buf.writeln(
                    '- GPS logs: No entries found for the requested time period');
              } else {
                final latest = filtered.first;
                final lat =
                    (latest['latitude'] as num?)?.toDouble();
                final lng =
                    (latest['longitude'] as num?)?.toDouble();
                final acc = latest['accuracy'];
                final type =
                    latest['locationType'] ?? 'unknown';
                final spd =
                    (latest['speed'] as num?)?.toDouble() ?? 0;
                final ts =
                    (latest['timestamp'] as num?)?.toInt() ?? 0;
                // Feature 3 — formatted timestamp instead of raw DateTime
                final tsFormatted = _formatTimestamp(ts);
                final locationTypeDesc = type == 'gps'
                    ? 'live GPS fix'
                    : type == 'cached'
                        ? 'last known position (GPS unavailable)'
                        : type;

                if (lat == null ||
                    lng == null ||
                    (lat == 0 && lng == 0)) {
                  buf.writeln(
                      '- GPS: Device has not reported a valid location yet');
                } else {
                  buf.writeln(
                      '- Most recent location: Lat $lat, Lng $lng');
                  buf.writeln('  • Recorded: $tsFormatted');
                  buf.writeln('  • Fix type: $locationTypeDesc');
                  buf.writeln('  • Accuracy: approx. ${acc}m');
                  buf.writeln(
                      '  • Speed: ${spd.toStringAsFixed(1)} km/h');
                }

                // Show up to 5 historical entries for context
                if (filtered.length > 1) {
                  final showCount =
                      filtered.length > 5 ? 5 : filtered.length;
                  buf.writeln(
                      '- Location history (up to $showCount entries):');
                  for (int i = 1; i < showCount; i++) {
                    final r = filtered[i];
                    final rLat =
                        (r['latitude'] as num?)?.toDouble();
                    final rLng =
                        (r['longitude'] as num?)?.toDouble();
                    final rTs =
                        (r['timestamp'] as num?)?.toInt() ?? 0;
                    // Feature 3 — formatted history timestamps
                    final rFmt = _formatTimestamp(rTs);
                    if (rLat != null &&
                        rLng != null &&
                        !(rLat == 0 && rLng == 0)) {
                      buf.writeln(
                          '  • Lat $rLat, Lng $rLng — $rFmt');
                    }
                  }
                }
              }

              buf.writeln(
                  '- Total logs on device: ${allLogs.length}');
            }
          } else {
            buf.writeln(
                '- GPS logs: No log data found for this device');
          }
        } catch (e) {
          buf.writeln('- GPS logs: Error reading logs');
          debugPrint('[GeminiService] Logs read error: $e');
        }

        // ── Active routes ─────────────────────────────────────
        try {
          final routesSnap = await FirebaseDatabase.instance
              .ref('devicePaths')
              .child(user.uid)
              .child(deviceCode)
              .get();
          if (routesSnap.exists) {
            final rd = routesSnap.value as Map<dynamic, dynamic>;
            final active = rd.entries
                .where((e) =>
                    e.value is Map &&
                    ((e.value as Map)['isActive'] as bool? ?? true))
                .toList();
            buf.writeln('- Active routes: ${active.length}');
            for (final r in active) {
              final d = r.value as Map<dynamic, dynamic>;
              buf.writeln(
                  '  • "${d['pathName']}" '
                  '(deviation threshold: ${d['deviationThresholdMeters']}m)');
            }
          } else {
            buf.writeln('- Active routes: None registered');
          }
        } catch (_) {}

        // Feature 2 — Recent alerts from alertLogs (last 5, for AI context)
        try {
          final alertsSnap = await FirebaseDatabase.instance
              .ref('alertLogs')
              .child(user.uid)
              .child(deviceCode)
              .get();
          if (alertsSnap.exists && alertsSnap.value is Map) {
            final raw = alertsSnap.value as Map<dynamic, dynamic>;
            final alerts = raw.entries
                .where((e) => e.value is Map)
                .map((e) => e.value as Map<dynamic, dynamic>)
                .toList();
            alerts.sort((a, b) {
              final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
              final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
              return tb.compareTo(ta);
            });
            final recent = alerts.take(5).toList();
            if (recent.isNotEmpty) {
              buf.writeln('- Recent alerts (${recent.length} shown):');
              for (final a in recent) {
                final aType = a['type']?.toString() ?? 'alert';
                final aTs   = _toInt(a['timestamp'] as dynamic);
                final aTsFmt = _formatTimestamp(aTs);
                final aMsg  = a['message']?.toString() ?? '';
                buf.writeln('  • [$aType] $aTsFmt — $aMsg');
              }
            } else {
              buf.writeln('- Recent alerts: None');
            }
          } else {
            buf.writeln('- Recent alerts: None on record');
          }
        } catch (_) {}

        buf.writeln();
      }
      return buf.toString();
    } catch (e) {
      debugPrint('[GeminiService] Firebase context error: $e');
      return 'Device data temporarily unavailable.';
    }
  }

  // ── Call Gemini API ──────────────────────────────────────────
  Future<String> _sendToGemini(
      String userMessage, String apiKey) async {
    final firebaseContext = await _buildFirebaseContext(
      originalQuestion: userMessage,
    );

    final systemPrompt = '''
You are SafeTrack AI — a caring, warm assistant inside the SafeTrack child safety app. You speak directly with parents of elementary school students. Your job is to help them understand their child's location, safety, and device status clearly and calmly.

---

## Core Rules

1. **Always use real data from the Live Device Data section below.** Never guess, estimate, or fabricate values. If a value is missing, say so honestly and kindly.

2. **School schedule is already known — never ask the parent for school hours.** The parent has configured school Time In and Time Out in the app. Use those values directly when answering questions like "Is my child in school?" or "Has my child arrived?".

3. **Ask for clarification on broad time questions.** If a parent asks something vague like "How was my child's behavior?" or "Show me the history" without specifying when, ask which period they mean (today, yesterday, last week, last month) BEFORE answering.

4. **Every response must end with one follow-up question in bold.** This helps the parent know what to check next. Example:
   > **Would you like me to check the device's battery status?**

5. **Answer technical questions using the SafeTrack Knowledge Base.** Translate technical details into plain language when speaking to parents.

6. **Be honest about limitations.** If data is unavailable, say so warmly and suggest what the parent can do.

7. **The project Created by:** This app was created by Computer Engineering students: (a) Elyza Camille Good, (b) Jemarie Mae B. Samontanez, and (c) Jonnamaye A. Agting from CTU Danao Campus.

8. **"Behavior" in SafeTrack means movement patterns only.** 
   When a parent asks about their child's behavior, explain that SafeTrack 
   tracks location and movement data. Summarize the GPS log entries for 
   the requested time period: how many location updates were recorded, 
   any deviation alerts triggered, and whether the child stayed on their 
   registered route. Do not say SafeTrack "cannot" answer — always 
   summarize what the data shows.

---

## Tone Rules (Feature 4 — Reassuring, Parent-Friendly)

You are speaking to a parent who may be anxious. Always:

- **Use warm, everyday language.** Never use technical jargon like "null", "N/A", "epoch", "timestamp", "ms", "API", "JSON", or "RTDB" in responses.
- **Translate device values into plain English:**
  - Battery 85% → "The device is well charged at 85%."
  - Battery 12% → "The battery is getting low at 12%. Please charge it tonight."
  - Battery 5% → "The battery is critically low at 5% — please charge the device immediately."
  - locationType "gps" → "This is a live GPS reading."
  - locationType "cached" → "This is the last known location — the GPS was temporarily unavailable."
  - Online: No → "The device hasn't sent an update recently."
- **Never say the child is missing or in danger** unless SOS is active. Use cautious, reassuring language instead.
- **When SOS is active**, respond with calm urgency: acknowledge the alert, give location, and suggest calling the child or going to the location immediately.
- **Always reassure the parent when things are normal.** Example: "Everything looks good — [Name] is on her registered route and the device is working well."

---

## Actionable Steps (Feature 5)

When the device is offline, battery is low, or data is stale, always provide clear numbered steps the parent can take. Do not just report the problem — guide them.

**Template for offline device:**
> I don't have a recent location update from [Name]'s device. The last update I received was [formatted time]. Since no deviation alerts were triggered at that time, [Name] was within the registered route.
>
> To restore real-time tracking, please:
> 1. Make sure the device is powered on (look for the green LED blinking every 30 seconds).
> 2. Check that the SIM card has an active Globe data balance.
> 3. Move to an area with better cellular signal if indoors.

**Template for low battery:**
> [Name]'s device battery is at [X]%. To avoid losing tracking:
> 1. Collect the device as soon as your child arrives home.
> 2. Connect it to a USB charger tonight.
> 3. A full charge takes about 2–3 hours.

**Template for SOS:**
> 🚨 [Name] has triggered an SOS alert. Her last recorded location was [location] at [time].
> 1. Try calling your child directly.
> 2. Contact the school to verify their whereabouts.
> 3. If you cannot reach them, contact local authorities.

---

$_kSafeTrackKnowledgeBase

---

## Live Device Data (from Firebase — updated each query)

$firebaseContext
''';

    _conversationHistory.add({
      'role': 'user',
      'parts': [
        {'text': userMessage}
      ],
    });

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ],
      },
      'contents': _conversationHistory,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 2048,
        'topP': 0.9,
      },
      'safetySettings': [
        {
          'category': 'HARM_CATEGORY_HARASSMENT',
          'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
        },
        {
          'category': 'HARM_CATEGORY_HATE_SPEECH',
          'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
        },
      ],
    });

    final response = await http.post(
      Uri.parse('${_selectedModel.endpointUrl}?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      debugPrint(
          '[GeminiService] HTTP ${response.statusCode}: ${response.body}');
      // 429 = rate limit / quota exhausted — UI will prompt model switch
      if (response.statusCode == 429) {
        return kGeminiRateLimitError;
      }
      return 'I\'m having trouble connecting right now. '
          'Please try again in a moment.';
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;
    final candidates =
        (data['candidates'] as List<dynamic>?) ?? [];
    if (candidates.isEmpty) {
      return 'I couldn\'t generate a response. '
          'Please try rephrasing your question.';
    }

    final content = candidates[0]['content'] as Map<String, dynamic>? ?? {};
    final parts = (content['parts'] as List<dynamic>?) ?? [];
    final text = parts
        .map((p) =>
            (p as Map<String, dynamic>)['text'] as String? ?? '')
        .join('');

    if (text.isEmpty) {
      return 'I received an empty response. Please try again.';
    }

    _conversationHistory.add({
      'role': 'model',
      'parts': [
        {'text': text}
      ],
    });

    // Keep history to last 20 messages to avoid token overflow
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, 2);
    }

    return text;
  }

  /// Call when starting a new chat session.
  void resetConversation() {
    _conversationHistory.clear();
    _awaitingTimeRangeClarification = false;
    _pendingBroadQuestion = null;
  }
}