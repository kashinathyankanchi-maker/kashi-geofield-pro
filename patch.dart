import 'dart:io';

void main() {
  final file = File('lib/features/map/map_screen.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains('duty_diary_screen.dart')) {
    content = content.replaceFirst(
      "import '../villages/villages_screen.dart';",
      "import '../villages/villages_screen.dart';\nimport '../duty_diary/duty_diary_screen.dart';"
    );
  }

  final target = '''
                    // Forestry Calculator
                    _MapFab(
                      icon: Icons.calculate_rounded,
                      tooltip: 'Quarter Girth Calc',
                      color: const Color(0xFFAB47BC), // tactical purple
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CbmScreen()),
                        );
                      },
                    ),''';
                    
  final replacement = '''
                    // Duty Diary & Voice Assistant
                    _MapFab(
                      icon: Icons.mic_rounded,
                      tooltip: 'Duty Diary & Voice Assistant',
                      color: Colors.orangeAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DutyDiaryScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    
                    // Forestry Calculator
                    _MapFab(
                      icon: Icons.calculate_rounded,
                      tooltip: 'Quarter Girth Calc',
                      color: const Color(0xFFAB47BC), // tactical purple
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CbmScreen()),
                        );
                      },
                    ),''';

  // Normalize line endings to avoid matching issues
  content = content.replaceAll('\\r\\n', '\\n');
  if (content.contains(target)) {
    content = content.replaceFirst(target, replacement);
    file.writeAsStringSync(content);
    print('Replacement successful');
  } else {
    print('Target not found in Dart script');
  }
}
