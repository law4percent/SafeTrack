import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const String _apiKey = 'AIzaSyAcG7yrUX1YR6b_z9SqYQdKkzuVeMW6iZA';
  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
    );
  }

  Future<String> getResponse(String question) async {
    try {
      // Check for specific questions first
      final lowerQuestion = question.toLowerCase().trim();
      
      // Question about developers/creators
      if (lowerQuestion.contains('who made') || 
          lowerQuestion.contains('who created') ||
          lowerQuestion.contains('who developed') ||
          lowerQuestion.contains('developers') ||
          lowerQuestion.contains('creators') ||
          lowerQuestion.contains('authors')) {
        return '''This app was made by three talented Computer Engineering students from CTU Danao Campus:

1. Good, Elyza
2. Samontanez, Jemarie Mae B.
3. Agting, Jonnamaye A.

They developed SafeTrack as part of their engineering project to help parents keep their children safe.''';
      }

      // Question about child status
      if (lowerQuestion.contains('how is my child') ||
          lowerQuestion.contains('my child status') ||
          lowerQuestion.contains('child doing') ||
          lowerQuestion.contains('child safe')) {
        return '''Based on the current monitoring data:

✅ All your linked children are being monitored
✅ You can check their real-time location in the "Live Location" tab
✅ You'll receive instant alerts if any emergency SOS is triggered
✅ Battery levels and online status are continuously tracked

For detailed information about each child, please check the "Live Location" or "My Children" sections in the app.''';
      }

      // General safety-related questions - use Gemini AI
      final systemPrompt = '''You are SafeTrack AI Assistant, a helpful chatbot for a child safety monitoring app. 
Your role is to help parents with:
- Understanding app features
- Safety tips for children
- How to use the monitoring system
- General child safety advice

Keep responses concise, friendly, and focused on child safety.

This app was created by Computer Engineering students: Good Elyza, Samontanez Jemarie Mae B., and Agting Jonnamaye A. from CTU Danao Campus.''';

      final prompt = '$systemPrompt\n\nUser question: $question';
      
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      return response.text ?? 'I apologize, but I couldn\'t generate a response. Please try again.';
    } catch (e) {
      return 'Sorry, I encountered an error: ${e.toString()}. Please try again.';
    }
  }
}