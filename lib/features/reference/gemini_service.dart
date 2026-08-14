import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the Gemini REST API directly (no gRPC — avoids HandshakeException on Android).
class GeminiService {
  final String apiKey;

  GeminiService({required this.apiKey});

  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  /// Sends extracted PDF text + user question to Gemini API and returns the answer.
  Future<String> askQuestion({
    required String pdfText,
    required String question,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    try {
      // Build the contents array with full chat history
      final List<Map<String, dynamic>> contents = [];

      // Add chat history turns (skip the initial welcome message from the model)
      for (final msg in chatHistory) {
        final role = msg['role'] == 'user' ? 'user' : 'model';
        contents.add({
          'role': role,
          'parts': [
            {'text': msg['text'] ?? ''}
          ],
        });
      }

      // Add the system context + new user question
      final systemContext = '''You are an expert legal assistant for Indian Forest Department officers.
You have been given the full text of a legal/official document.
Answer the user's question ONLY based on the document text provided.
If the answer is not found in the document, say "This information is not found in the document."
Always quote the relevant Section/Rule number when applicable.
Answer in the same language the user asks (English, Kannada, or Hindi).

--- DOCUMENT TEXT ---
$pdfText
--- END OF DOCUMENT ---

User Question: $question''';

      contents.add({
        'role': 'user',
        'parts': [
          {'text': systemContext}
        ],
      });

      final body = jsonEncode({
        'contents': contents,
        'generationConfig': {
          'temperature': 0.2,
          'maxOutputTokens': 2048,
        },
      });

      final response = await http
          .post(
            Uri.parse('$_baseUrl?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text'] as String? ?? 'No response from Gemini AI.';
          }
        }
        return 'No response from Gemini AI.';
      } else if (response.statusCode == 400) {
        final data = jsonDecode(response.body);
        final msg = data['error']?['message'] ?? 'Bad request';
        return 'API Error (400): $msg\n\nCheck that your API key is correct and the Gemini API is enabled in your Google Cloud project.';
      } else if (response.statusCode == 403) {
        return 'API Error (403): Access denied.\n\nYour API key may be invalid or the Gemini API is not enabled. Go to: aistudio.google.com to get a valid key.';
      } else if (response.statusCode == 429) {
        return 'API Quota Exceeded (429): Too many requests.\n\nYou have hit the free-tier rate limit. Wait a minute and try again, or enable billing on your Google Cloud project.';
      } else {
        return 'API Error (${response.statusCode}): ${response.body}';
      }
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('HandshakeException') || msg.contains('Connection terminated')) {
        return 'Network Error: SSL/TLS connection failed.\n\n'
            'Please check:\n'
            '• Your internet connection is active\n'
            '• You are not on a restricted WiFi network (try mobile data)\n'
            '• Your device date and time are correct\n\n'
            'Technical detail: $msg';
      }
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        return 'Request timed out. The Gemini server took too long to respond.\n\nPlease try again.';
      }
      return 'Connection Error: $msg\n\nPlease check your internet connection and try again.';
    }
  }
}
