import 'dart:io';
import 'package:image/image.dart';

void main() {
  final image = Image(width: 1, height: 1, numChannels: 4); // Transparent
  File('assets/images/transparent.png').writeAsBytesSync(encodePng(image));
  print('Transparent PNG created.');
}
