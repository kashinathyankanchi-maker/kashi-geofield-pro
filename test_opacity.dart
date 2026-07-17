import 'dart:io';
import 'package:image/image.dart' as img;

Future<void> main() async {
  print('Creating test image...');
  final testImg = img.Image(width: 4, height: 1, numChannels: 3);
  // Red
  testImg.setPixelRgb(0, 0, 255, 0, 0);
  // Black
  testImg.setPixelRgb(1, 0, 0, 0, 0);
  // White
  testImg.setPixelRgb(2, 0, 255, 255, 255);
  // Light cyan
  testImg.setPixelRgb(3, 0, 200, 255, 255);
  
  final testPath = 'test_opacity.png';
  File(testPath).writeAsBytesSync(img.encodePng(testImg));
  
  print('Running split function (simulated)...');
  final originalPath = testPath;
  final ext = originalPath.contains('.') ? originalPath.split('.').last : 'png';
  final pathWithoutExt = originalPath.substring(0, originalPath.length - ext.length - 1);
  final fgPath = '${pathWithoutExt}_fg.png';
  final bgPath = '${pathWithoutExt}_bg.png';

  final bytes = File(originalPath).readAsBytesSync();
  final srcImage = img.decodeImage(bytes)!;

  final w = srcImage.width;
  final h = srcImage.height;

  final fgImage = img.Image(width: w, height: h, numChannels: 4);
  final bgImage = img.Image(width: w, height: h, numChannels: 4);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final sp = srcImage.getPixel(x, y);
      final r = sp.r.toInt();
      final g = sp.g.toInt();
      final b = sp.b.toInt();

      final isWhite = r > 220 && g > 220 && b > 220;
      final isLightCyan = !isWhite && g > 200 && b > 200 && r > 150;
      final isBackground = isWhite || isLightCyan;

      if (isBackground) {
        bgImage.setPixelRgba(x, y, r, g, b, 255);
        fgImage.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        fgImage.setPixelRgba(x, y, r, g, b, 255);
        bgImage.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  File(fgPath).writeAsBytesSync(img.encodePng(fgImage));
  File(bgPath).writeAsBytesSync(img.encodePng(bgImage));

  print('Checking foreground image...');
  final resFg = img.decodeImage(File(fgPath).readAsBytesSync())!;
  print('FG Red (0,0): a=${resFg.getPixel(0,0).a}');
  print('FG Black (1,0): a=${resFg.getPixel(1,0).a}');
  print('FG White (2,0): a=${resFg.getPixel(2,0).a}');
  print('FG Cyan (3,0): a=${resFg.getPixel(3,0).a}');

  print('Checking background image...');
  final resBg = img.decodeImage(File(bgPath).readAsBytesSync())!;
  print('BG Red (0,0): a=${resBg.getPixel(0,0).a}');
  print('BG Black (1,0): a=${resBg.getPixel(1,0).a}');
  print('BG White (2,0): a=${resBg.getPixel(2,0).a}');
  print('BG Cyan (3,0): a=${resBg.getPixel(3,0).a}');
}
