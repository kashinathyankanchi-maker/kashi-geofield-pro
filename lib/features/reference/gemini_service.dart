import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  final String apiKey;

  GeminiService({required this.apiKey});

  /// Sends extracted PDF text + user question to Gemini API and returns the answer.
  Future<String> askQuestion({
    required String pdfText,
    required String question,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system('''
You are an expert legal assistant for Indian Forest Department officers. 
You have been given the full text of a legal/official document. 
Answer the user's question ONLY based on the document text provided below. 
If the answer is not found in the document, say "This information is not found in the document."
Always quote the relevant Section/Rule number when applicable.
Answer in the same language the user asks the question in (English, Kannada, or Hindi).

--- DOCUMENT TEXT ---
$pdfText
--- END OF DOCUMENT ---
'''),
      );

      // Build conversation history for the SDK
      final List<Content> history = [];
      for (final msg in chatHistory) {
        if (msg['role'] == 'user') {
          history.add(Content.text(msg['text']!));
        } else {
          history.add(Content.model([TextPart(msg['text']!)]));
        }
      }

      // Initialize the chat session
      final chat = model.startChat(history: history);

      // Send the new message
      final response = await chat.sendMessage(Content.text(question));

      return response.text ?? 'No response from Gemini AI.';
    } catch (e) {
      String availableModels = '';
      try {
        final res = await http.get(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final models = (data['models'] as List).map((m) => m['name'].toString().replaceAll('models/', '')).toList();
          availableModels = '\n\nAvailable models for your key:\n${models.join(', ')}';
        }
      } catch (_) {}

      return 'API Error: $e$availableModels\n\nIf you see a Quota/Limit error, please check if your Google Cloud project requires billing enabled or if the free tier is restricted in your region.';
    }
  }
}
