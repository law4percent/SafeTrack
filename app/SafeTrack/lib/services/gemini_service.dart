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
class GeminiService {
  static const String _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.5-flash:generateContent';

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

  // ── Safe int cast (handles int, double, String) ────────────
  int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  // ── Fetch Firebase context ────────────────────────────────────
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
            final battery  = s['batteryLevel'] ?? 'N/A';
            final isSOS    = s['sos'] as bool? ?? false;
            final lastTs   = _toInt(s['lastUpdate']);
            final isOnline = lastTs > 0 &&
                DateTime.now()
                    .difference(DateTime.fromMillisecondsSinceEpoch(lastTs))
                    .inMinutes < 5;
            final minsAgo  = lastTs > 0
                ? DateTime.now()
                    .difference(DateTime.fromMillisecondsSinceEpoch(lastTs))
                    .inMinutes
                : -1;
            buf.writeln('- Battery: $battery%');
            buf.writeln('- SOS Active: ${isSOS ? "YES — EMERGENCY" : "No"}');
            buf.writeln('- Online: ${isOnline ? "Online" : minsAgo >= 0 ? "Offline (last seen ${minsAgo}min ago)" : "Unknown"}');
            // Surface lastLocation from deviceStatus
            final ll = s['lastLocation'];
            if (ll is Map) {
              final llLat = (ll['latitude']  as num?)?.toDouble() ?? 0;
              final llLng = (ll['longitude'] as num?)?.toDouble() ?? 0;
              if (llLat != 0 && llLng != 0) {
                buf.writeln('- Last known (status node): Lat $llLat, Lng $llLng');
              }
            }
          } else {
            buf.writeln('- Battery: No status data yet (device not yet synced)');
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

                final startDt =
                    DateTime.fromMillisecondsSinceEpoch(startMs);
                final endDt =
                    DateTime.fromMillisecondsSinceEpoch(endMs);
                buf.writeln(
                    '- Date range filter applied: $startDt → $endDt');
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
                final dt =
                    DateTime.fromMillisecondsSinceEpoch(ts);
                final minsAgo =
                    DateTime.now().difference(dt).inMinutes;

                if (lat == null ||
                    lng == null ||
                    (lat == 0 && lng == 0)) {
                  buf.writeln(
                      '- GPS: Device has not reported a valid location yet');
                } else {
                  buf.writeln(
                      '- Most recent location in range: Lat $lat, Lng $lng');
                  buf.writeln('  • Location type: $type');
                  buf.writeln('  • Accuracy: ${acc}m');
                  buf.writeln(
                      '  • Speed: ${spd.toStringAsFixed(1)} m/s');
                  buf.writeln(
                      '  • Timestamp: $dt ($minsAgo min ago)');
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
                    final rDt =
                        DateTime.fromMillisecondsSinceEpoch(rTs);
                    if (rLat != null &&
                        rLng != null &&
                        !(rLat == 0 && rLng == 0)) {
                      buf.writeln(
                          '  • Lat $rLat, Lng $rLng — $rDt');
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
You are SafeTrack AI — a warm, knowledgeable, and reassuring assistant built into the SafeTrack child safety monitoring app. You help parents of elementary school students understand their child's safety, location, and device status in real time.

## Core Behavior Rules

1. **Use real data.** Always base answers on the Live Device Data section below. Never guess or fabricate values.

2. **Ask for clarification on broad questions.** If a parent asks something vague or time-range-dependent (e.g., "How was my child's behavior?", "Show me movement history"), ask them which time period they mean (today, yesterday, last week, last month) BEFORE answering.

3. **School hours awareness.** You do not know the child's exact school schedule. If a question like "Is my child in school?" or "Has my child arrived?" is time-sensitive, ask the parent to confirm school hours:
   > "Could you let me know your child's school hours so I can give you a more accurate answer?"

4. **Always end with a follow-up question.** Every single response must end with one relevant follow-up question in bold, on its own line. Example:
   > **Would you like me to check the battery status as well?**

5. **Answer technical questions accurately.** Use the SafeTrack Knowledge Base to answer questions about algorithms, hardware, tech stack, and architecture.

6. **Be honest about limitations.** If you cannot determine something from the available data, say so clearly.

7. **Tone:** Warm, clear, and reassuring. These are parents concerned about their children — not developers.

8. **The project Created by:** This app was created by Computer Engineering students: Good Elyza, Samontanez Jemarie Mae B., and Agting Jonnamaye A. from CTU Danao Campus.

---

$_kSafeTrackKnowledgeBase

---

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
        'maxOutputTokens': 1024,
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
      Uri.parse('$_apiUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      debugPrint(
          '[GeminiService] HTTP ${response.statusCode}: ${response.body}');
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