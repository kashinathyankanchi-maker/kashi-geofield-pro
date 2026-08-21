import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the Gemini REST API directly (no gRPC — avoids HandshakeException on Android).
/// Uses the proper systemInstruction field so PDF text is sent once, not repeated every turn.
class GeminiService {
  final String apiKey;

  GeminiService({required this.apiKey});

  // gemini-2.0-flash is the latest free fast model (replaces deprecated gemini-flash-latest)
  static const _model = 'gemini-2.0-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  /// Sends extracted PDF text + user question to Gemini API and returns the answer.
  Future<String> askQuestion({
    required String pdfText,
    required String question,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    try {
      // Build the chat history turns (user/model alternating)
      // Skip the first welcome message (role: model, index 0)
      final List<Map<String, dynamic>> contents = [];

      for (final msg in chatHistory) {
        final role = msg['role'] == 'user' ? 'user' : 'model';
        contents.add({
          'role': role,
          'parts': [
            {'text': msg['text'] ?? ''}
          ],
        });
      }

      // Add the current user question
      contents.add({
        'role': 'user',
        'parts': [
          {'text': question}
        ],
      });

      // The PDF text goes in systemInstruction — sent ONCE, not repeated every turn.
      // This is the correct Gemini REST API approach.
      final systemInstruction = {
        'role': 'user',
        'parts': [
          {
            'text': '''You are an expert legal assistant for Indian Forest Department officers.
You have been given the full text of a legal/official document.
Answer the user\'s question ONLY based on the document text provided below.
If the answer is not found in the document, say "This information is not found in the document."
Always quote the relevant Section/Rule number when applicable.
Answer in the same language the user asks the question in (English, Kannada, or Hindi).

--- DOCUMENT TEXT ---
$pdfText
--- END OF DOCUMENT ---'''
          }
        ],
      };

      final body = jsonEncode({
        'systemInstruction': systemInstruction,
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
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Check for prompt blocked by safety filters
        final promptFeedback = data['promptFeedback'] as Map<String, dynamic>?;
        if (promptFeedback != null) {
          final blockReason = promptFeedback['blockReason'];
          if (blockReason != null) {
            return 'Response blocked by safety filter: $blockReason\n\nTry rephrasing your question.';
          }
        }

        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          // Check finish reason
          final finishReason = candidates[0]['finishReason'] as String?;
          if (finishReason == 'SAFETY') {
            return 'Response was blocked by safety filters. Try rephrasing your question.';
          }
          final content = candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text'] as String? ?? 'No response from Gemini AI.';
          }
        }
        return 'No response from Gemini AI. Please try again.';
      } else if (response.statusCode == 400) {
        final data = jsonDecode(response.body);
        final msg = data['error']?['message'] ?? 'Bad request';
        // Common cause: PDF text too long — truncate hint
        if (msg.toString().contains('too large') || msg.toString().contains('token')) {
          return 'Error: The PDF document is too large for the AI to process.\n\nTry asking about a specific section or page.';
        }
        return 'API Error (400): $msg\n\nMake sure your Gemini API key is correct. Get a free key at: aistudio.google.com';
      } else if (response.statusCode == 403) {
        return 'API Error (403): Access denied.\n\nYour API key is invalid or the Gemini API is not enabled.\nGet a free key at: aistudio.google.com';
      } else if (response.statusCode == 429) {
        return 'API Quota Exceeded: Too many requests.\n\nYou have hit the free-tier rate limit. Please wait 1 minute and try again.';
      } else if (response.statusCode == 404) {
        return 'API Error (404): Model not found.\n\nPlease check your internet connection and try again.';
      } else {
        // Show raw body to help debug unknown errors
        String errBody = response.body;
        if (errBody.length > 300) errBody = '${errBody.substring(0, 300)}...';
        return 'API Error (${response.statusCode}): $errBody';
      }
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('HandshakeException') || msg.contains('Connection terminated')) {
        return 'Network Error: SSL/TLS connection failed.\n\n'
            'Please check:\n'
            '• Your internet connection is active\n'
            '• Try switching from WiFi to mobile data\n'
            '• Make sure your device date and time are correct';
      }
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        return 'Request timed out. The server took too long.\n\nPlease try again with a shorter question.';
      }
      if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
        return 'No internet connection.\n\nPlease check your connection and try again.';
      }
      return 'Connection Error: $msg\n\nPlease check your internet connection and try again.';
    }
  }
}
