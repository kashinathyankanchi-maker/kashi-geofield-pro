import 'dart:io';
import 'package:archive/archive.dart';

void main() {
  final bytes = File('test.kmz').readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive.files) {
    print(file.name + ' isFile: ' + file.isFile.toString() + ' content type: ' + file.content.runtimeType.toString());
  }
}
