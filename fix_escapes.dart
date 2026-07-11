import 'dart:io';

void main() {
  final dir = Directory('lib/features/duty_diary');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  for (final file in files) {
    var content = file.readAsStringSync();
    if (content.contains('\\\$')) {
      content = content.replaceAll('\\\$', '\$');
      file.writeAsStringSync(content);
      print('Fixed \');
    }
  }
}
