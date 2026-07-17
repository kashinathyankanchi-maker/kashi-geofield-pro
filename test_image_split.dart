import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final image = img.Image(width: 100, height: 100, numChannels: 4);
  // Fill with white
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
  
  // Draw black line
  img.drawLine(image, x1: 10, y1: 10, x2: 90, y2: 90, color: img.ColorRgba8(0, 0, 0, 255), thickness: 2);
  
  // Draw red line
  img.drawLine(image, x1: 90, y1: 10, x2: 10, y2: 90, color: img.ColorRgba8(255, 0, 0, 255), thickness: 2);
  
  // Fill top left with light cyan
  img.fillRect(image, x1: 0, y1: 0, x2: 20, y2: 20, color: img.ColorRgba8(200, 255, 255, 255));

  // Save original
  File('test_original.png').writeAsBytesSync(img.encodePng(image));

  // Split image
  final fgImage = img.Image.from(image);
  final bgImage = img.Image.from(image);

  for (final p in fgImage) {
    if (p.r > 220 && p.g > 220 && p.b > 220) {
      // White
      p.a = 0;
    } else if (p.g > 200 && p.b > 200 && p.r > 150) {
      // Light cyan
      p.a = 0;
    }
  }

  for (final p in bgImage) {
    if (p.r > 220 && p.g > 220 && p.b > 220) {
      // White -> keep
    } else if (p.g > 200 && p.b > 200 && p.r > 150) {
      // Light cyan -> keep
    } else {
      p.a = 0;
    }
  }

  File('test_fg.png').writeAsBytesSync(img.encodePng(fgImage));
  File('test_bg.png').writeAsBytesSync(img.encodePng(bgImage));
  print('Done splitting image.');
}
