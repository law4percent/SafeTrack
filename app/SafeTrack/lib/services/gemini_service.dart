// lib/services/gemini_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static String get _apiKey {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception("GEMINI_API_KEY is missing in .env file");
    }
    return key;
  }
  static String get _geminiModelName => dotenv.env['GEMINI_MODEL_NAME'] ?? 'gemini-2.5-flash';

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: _geminiModelName,
      apiKey: _apiKey,
    );
  }

  // ── Fetch all device data from Firebase for the current user ──
  Future<String> _buildFirebaseContext() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'No user is currently logged in.';

      final devicesSnapshot = await FirebaseDatabase.instance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .get();

      if (!devicesSnapshot.exists) {
        return 'The parent has no linked devices yet.';
      }

      final devicesData = devicesSnapshot.value as Map<dynamic, dynamic>;
      final StringBuffer context = StringBuffer();
      context.writeln('=== CURRENT DEVICE DATA FROM FIREBASE ===');

      for (final entry in devicesData.entries) {
        final deviceCode = entry.key.toString();
        final deviceData = entry.value as Map<dynamic, dynamic>;
        final childName = deviceData['childName'] ?? 'Unknown';
        final isEnabled = deviceData['deviceEnabled']?.toString() == 'true';
        final yearLevel = deviceData['yearLevel'] ?? '';
        final section = deviceData['section'] ?? '';

        context.writeln('\n--- Child: $childName ---');
        context.writeln('Device Code: $deviceCode');
        context.writeln('Grade: $yearLevel  Section: $section');
        context.writeln('Device Enabled: $isEnabled');

        // Read deviceStatus (SOS, battery, last location from linkedDevices)
        final deviceStatus =
            deviceData['deviceStatus'] as Map<dynamic, dynamic>?;
        if (deviceStatus != null) {
          final sos = deviceStatus['sos'];
          final battery = deviceStatus['batteryLevel'];
          final lastUpdate = deviceStatus['lastUpdate'] as int? ?? 0;

          context.writeln(
              'SOS Active: ${sos == true || sos == "true" ? "YES ⚠️" : "No"}');
          context.writeln('Battery Level: $battery%');

          if (lastUpdate > 0) {
            final lastUpdateDt =
                DateTime.fromMillisecondsSinceEpoch(lastUpdate);
            final diff = DateTime.now().difference(lastUpdateDt);
            final isOnline = diff.inMinutes < 5;
            context.writeln(
                'Last Update: ${diff.inMinutes}m ago (${isOnline ? "ONLINE" : "OFFLINE"})');
          } else {
            context.writeln('Last Update: No data yet');
          }

          final lastLocation =
              deviceStatus['lastLocation'] as Map<dynamic, dynamic>?;
          if (lastLocation != null) {
            final lat = lastLocation['latitude'];
            final lng = lastLocation['longitude'];
            context.writeln('Last Known Location: Lat $lat, Lng $lng');
          }
        }

        // Read recent logs from deviceLogs for richer history
        try {
          final logsSnapshot = await FirebaseDatabase.instance
              .ref('deviceLogs')
              .child(user.uid)
              .child(deviceCode)
              .limitToLast(10) // last 10 log entries only
              .get();

          if (logsSnapshot.exists) {
            final logsData = logsSnapshot.value as Map<dynamic, dynamic>;
            int sosCount = 0;
            double avgBattery = 0;
            int batteryReadings = 0;

            logsData.forEach((key, value) {
              if (value is Map) {
                final sos = value['sos'];
                if (sos == true || sos == 'true') sosCount++;

                final battery = (value['batteryLevel'] as num?)?.toDouble();
                if (battery != null && battery > 0) {
                  avgBattery += battery;
                  batteryReadings++;
                }
              }
            });

            if (batteryReadings > 0) avgBattery /= batteryReadings;

            context.writeln(
                'Recent Log Summary (last 10 entries):');
            context.writeln('  - SOS triggers: $sosCount');
            context
                .writeln('  - Average battery: ${avgBattery.toStringAsFixed(1)}%');
            context.writeln('  - Total log entries checked: ${logsData.length}');
          } else {
            context.writeln('Recent Logs: No log entries yet');
          }
        } catch (e) {
          context.writeln('Recent Logs: Could not fetch ($e)');
        }
      }

      context.writeln('\n=== END OF DEVICE DATA ===');
      return context.toString();
    } catch (e) {
      debugPrint('Error building Firebase context: $e');
      return 'Could not fetch device data at this time.';
    }
  }

  Future<String> getResponse(String question) async {
    try {
      if (_apiKey.isEmpty) {
        return 'Gemini API key is not configured. Please check your .env file.';
      }

      // ── Hardcoded override: who made this app ──────────────────
      final lowerQuestion = question.toLowerCase().trim();
      if (lowerQuestion.contains('who made') ||
          lowerQuestion.contains('who created') ||
          lowerQuestion.contains('who developed') ||
          lowerQuestion.contains('developers') ||
          lowerQuestion.contains('creators') ||
          lowerQuestion.contains('authors')) {
        return '''SafeTrack was developed by three Computer Engineering students from CTU Danao Campus:

1. Good, Elyza
2. Samontanez, Jemarie Mae B.
3. Agting, Jonnamaye A.

They built SafeTrack as their engineering project to help parents monitor their children's safety.''';
      }

      // ── Fetch real Firebase data for all other questions ───────
      final firebaseContext = await _buildFirebaseContext();

      final systemPrompt = '''
You are SafeTrack AI Assistant — a smart, friendly safety monitoring assistant built into the SafeTrack child safety app.

Your job is to help parents understand their children's safety status based on REAL data from their devices.

Here is the current real-time data from Firebase for this parent's linked devices:

$firebaseContext

INSTRUCTIONS:
- Use the Firebase data above to answer questions about specific children, their status, battery, SOS history, and location.
- If the parent asks "How is my child?" or similar, summarize the relevant device data clearly.
- If SOS is active for any child, treat this as urgent and highlight it prominently.
- If a child is offline for more than 5 minutes, mention it.
- If battery is below 20%, flag it as low.
- Be concise, warm, and parent-friendly.
- Do NOT make up data. If something is unknown, say so.
- You can also answer general child safety questions, app usage tips, and parenting advice.
- This app was created by: Good Elyza, Samontanez Jemarie Mae B., and Agting Jonnamaye A. from CTU Danao Campus.

Parent's question: $question
''';

      final content = [Content.text(systemPrompt)];
      final response = await _model.generateContent(content);

      return response.text ??
          'I could not generate a response. Please try again.';
    } catch (e) {
      debugPrint('Gemini error: $e');
      return 'Sorry, I encountered an error: ${e.toString()}. Please try again.';
    }
  }
}