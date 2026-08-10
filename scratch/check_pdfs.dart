import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() async {
  final files = ['doc1.pdf', 'doc2.pdf', 'doc3.pdf', 'doc4.pdf'];
  for (var file in files) {
    try {
      final bytes = File('assets/pdfs/$file').readAsBytesSync();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText(startPageIndex: 0, endPageIndex: 0);
      print('=== $file ===');
      print(text.substring(0, text.length > 100 ? 100 : text.length).replaceAll('\n', ' '));
      document.dispose();
    } catch (e) {
      print('Error on $file: $e');
    }
  }
}
