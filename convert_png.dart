import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File('assets/images/app_icon.jpg');
  final image = decodeImage(file.readAsBytesSync());

  if (image != null) {
    File('assets/images/app_icon_bg.png').writeAsBytesSync(encodePng(image));
    print('PNG created.');
  }
}
