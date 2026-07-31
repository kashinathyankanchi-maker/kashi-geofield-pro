import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'ocr_models.dart';

class CloudVisionService {
  static Future<List<OcrBlock>> recognizeText(File imageFile, String apiKey) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final url = Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$apiKey');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requests': [
          {
            'image': {'content': base64Image},
            'features': [{'type': 'DOCUMENT_TEXT_DETECTION'}]
          }
        ]
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Cloud Vision API error: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    final responses = data['responses'] as List;
    if (responses.isEmpty) return [];

    final firstResponse = responses.first;
    if (firstResponse['error'] != null) {
       throw Exception('Cloud Vision API error: ${firstResponse['error']['message']}');
    }

    final fullTextAnnotation = firstResponse['fullTextAnnotation'];
    if (fullTextAnnotation == null) return [];

    final pages = fullTextAnnotation['pages'] as List?;
    if (pages == null || pages.isEmpty) return [];

    final blocks = <OcrBlock>[];

    for (var page in pages) {
      for (var blockData in page['blocks'] ?? []) {
        final lines = <OcrLine>[];
        for (var paragraph in blockData['paragraphs'] ?? []) {
          final words = paragraph['words'] as List? ?? [];
          final text = words.map((w) {
            final symbols = w['symbols'] as List? ?? [];
            return symbols.map((s) => s['text']).join('');
          }).join(' ');

          if (text.trim().isNotEmpty) {
            final bbox = _getRect(paragraph['boundingBox']);
            lines.add(OcrLine(text: text.trim(), boundingBox: bbox));
          }
        }

        if (lines.isNotEmpty) {
          final blockBbox = _getRect(blockData['boundingBox']);
          blocks.add(OcrBlock(boundingBox: blockBbox, lines: lines));
        }
      }
    }

    return blocks;
  }

  static Rect _getRect(Map<String, dynamic>? boundingBox) {
    if (boundingBox == null) return Rect.zero;
    final vertices = boundingBox['vertices'] as List?;
    if (vertices == null || vertices.isEmpty) return Rect.zero;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (var v in vertices) {
      final x = (v['x'] ?? 0).toDouble();
      final y = (v['y'] ?? 0).toDouble();
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}
