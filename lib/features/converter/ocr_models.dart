import 'dart:ui';

class OcrLine {
  final String text;
  final Rect boundingBox;

  OcrLine({required this.text, required this.boundingBox});
}

class OcrBlock {
  final Rect boundingBox;
  final List<OcrLine> lines;

  OcrBlock({required this.boundingBox, required this.lines});
}
