import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String apiKey;

  GeminiService({required this.apiKey});

  /// Sends extracted PDF text + user question to Gemini API and returns the answer.
  Future<String> askQuestion({
    required String pdfText,
    required String question,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
    );

    // Build conversation history
    final List<Map<String, dynamic>> contents = [];

    // System-like first user message with PDF context
    final systemPrompt = '''You are an expert legal assistant for Indian Forest Department officers. 
You have been given the full text of a legal/official document. 
Answer the user's question ONLY based on the document text provided below. 
If the answer is not found in the document, say "This information is not found in the document."
Always quote the relevant Section/Rule number when applicable.
Answer in the same language the user asks the question in (English, Kannada, or Hindi).

--- DOCUMENT TEXT ---
$pdfText
--- END OF DOCUMENT ---''';

    contents.add({
      'role': 'user',
      'parts': [{'text': systemPrompt}],
    });
    contents.add({
      'role': 'model',
      'parts': [{'text': 'I have read the document. I will answer your questions based on its contents. Please ask your question.'}],
    });

    // Add chat history
    for (final msg in chatHistory) {
      contents.add({
        'role': msg['role'] == 'user' ? 'user' : 'model',
        'parts': [{'text': msg['text']!}],
      });
    }

    // Add current question
    contents.add({
      'role': 'user',
      'parts': [{'text': question}],
    });

    final body = jsonEncode({
      'contents': contents,
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 2048,
      },
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']['parts'] as List;
          return parts.map((p) => p['text']).join('');
        }
        return 'No response from Gemini AI.';
      } else {
        final errorData = jsonDecode(response.body);
        final errorMsg = errorData['error']?['message'] ?? 'Unknown error';
        return 'API Error (${response.statusCode}): $errorMsg';
      }
    } catch (e) {
      return 'Connection error: $e\n\nMake sure you have internet access.';
    }
  }
}
