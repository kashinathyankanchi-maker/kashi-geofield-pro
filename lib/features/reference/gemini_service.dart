import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the Gemini REST API directly (no gRPC — avoids HandshakeException on Android).
/// Uses the proper systemInstruction field so PDF text is sent once, not repeated every turn.
/// Automatically falls back across model aliases (gemini-1.5-flash, gemini-2.0-flash, etc.)
/// if Google deprecates or changes endpoint availability.
class GeminiService {
  final String apiKey;

  GeminiService({required this.apiKey});

  // Candidate models to try in order (handles Google API deprecations / model alias updates)
  static const List<String> _candidateModels = [
    'gemini-1.5-flash',
    'gemini-2.0-flash',
    'gemini-2.5-flash',
    'gemini-1.5-flash-latest',
    'gemini-1.5-pro',
    'gemini-pro',
  ];

  // Store working model name to avoid retrying on every question once found
  static String? _workingModel;

  /// Sends extracted PDF text + user question to Gemini API and returns the answer.
  Future<String> askQuestion({
    required String pdfText,
    required String question,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    // If we already know a working model, try that first
    final modelsToTry = <String>[];
    if (_workingModel != null) {
      modelsToTry.add(_workingModel!);
    }
    for (final m in _candidateModels) {
      if (!modelsToTry.contains(m)) modelsToTry.add(m);
    }

    String lastError = 'No response from Gemini API.';

    for (final model in modelsToTry) {
      try {
        final result = await _sendRequest(
          model: model,
          pdfText: pdfText,
          question: question,
          chatHistory: chatHistory,
        );

        if (result.isSuccess) {
          _workingModel = model; // Cache the working model!
          return result.text;
        }

        if (result.isNotFound) {
          // Model 404 (deprecated / not available on this key), try next candidate
          lastError = result.text;
          continue;
        }

        // For other errors (quota, invalid key, blocked), return immediately
        return result.text;
      } catch (e) {
        lastError = _formatException(e);
      }
    }

    return lastError;
  }

  Future<_ApiResult> _sendRequest({
    required String model,
    required String pdfText,
    required String question,
    required List<Map<String, String>> chatHistory,
  }) async {
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

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

    contents.add({
      'role': 'user',
      'parts': [
        {'text': question}
      ],
    });

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
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final promptFeedback = data['promptFeedback'] as Map<String, dynamic>?;
      if (promptFeedback != null) {
        final blockReason = promptFeedback['blockReason'];
        if (blockReason != null) {
          return _ApiResult.success(
              'Response blocked by safety filter: $blockReason\n\nTry rephrasing your question.');
        }
      }

      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final finishReason = candidates[0]['finishReason'] as String?;
        if (finishReason == 'SAFETY') {
          return _ApiResult.success(
              'Response was blocked by safety filters. Try rephrasing your question.');
        }
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return _ApiResult.success(
              parts[0]['text'] as String? ?? 'No response from Gemini AI.');
        }
      }
      return _ApiResult.success('No response from Gemini AI. Please try again.');
    } else if (response.statusCode == 404) {
      return _ApiResult.notFound('Model $model not found (404).');
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      final msg = data['error']?['message'] ?? 'Bad request';
      if (msg.toString().contains('too large') || msg.toString().contains('token')) {
        return _ApiResult.error(
            'Error: The PDF document is too large for the AI to process.\n\nTry asking about a specific section or page.');
      }
      return _ApiResult.error(
          'API Error (400): $msg\n\nMake sure your Gemini API key is correct. Get a free key at: aistudio.google.com');
    } else if (response.statusCode == 403) {
      return _ApiResult.error(
          'API Error (403): Access denied.\n\nYour API key is invalid or the Gemini API is not enabled.\nGet a free key at: aistudio.google.com');
    } else if (response.statusCode == 429) {
      return _ApiResult.error(
          'API Quota Exceeded: Too many requests.\n\nYou have hit the free-tier rate limit. Please wait 1 minute and try again.');
    } else {
      String errBody = response.body;
      if (errBody.length > 300) errBody = '${errBody.substring(0, 300)}...';
      return _ApiResult.error('API Error (${response.statusCode}): $errBody');
    }
  }

  String _formatException(dynamic e) {
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

class _ApiResult {
  final bool isSuccess;
  final bool isNotFound;
  final String text;

  _ApiResult.success(this.text)
      : isSuccess = true,
        isNotFound = false;

  _ApiResult.notFound(this.text)
      : isSuccess = false,
        isNotFound = true;

  _ApiResult.error(this.text)
      : isSuccess = false,
        isNotFound = false;
}
