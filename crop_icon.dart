import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File('assets/images/app_icon.jpg');
  final image = decodeImage(file.readAsBytesSync());

  if (image != null) {
    // The AI generated icon has a white border/corners.
    // We can crop the inner 85% of the image to get rid of the borders.
    int cropSize = (image.width * 0.85).toInt();
    int offsetX = (image.width - cropSize) ~/ 2;
    int offsetY = (image.height - cropSize) ~/ 2;

    final cropped = copyCrop(image, x: offsetX, y: offsetY, width: cropSize, height: cropSize);
    
    // Also, we can resize it back to 1024x1024 if needed, but it's fine.
    File('assets/images/app_icon.jpg').writeAsBytesSync(encodeJpg(cropped, quality: 100));
    print('Cropped successfully.');
  }
}
