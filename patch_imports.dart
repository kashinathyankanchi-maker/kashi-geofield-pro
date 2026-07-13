import 'dart:io';

void main() {
  final file = File('lib/features/duty_diary/diary_pdf_generator.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains('package:flutter/material.dart')) {
    content = "import 'package:flutter/material.dart';\n" + content;
  }
  
  // Fix unnecessary non-null assertion
  content = content.replaceAll('XFile(file!.path)', 'XFile(file?.path ?? "")');
  
  file.writeAsStringSync(content);
  print('Added material import and fixed file!.path');
}
