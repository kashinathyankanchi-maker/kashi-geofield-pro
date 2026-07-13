import 'dart:io';

void main() {
  final file = File('lib/features/map/map_screen.dart');
  var lines = file.readAsLinesSync();
  
  int cbmIndex = lines.indexWhere((l) => l.contains('const CbmScreen()'));
  if (cbmIndex == -1) {
    print('CbmScreen not found');
    return;
  }
  
  // Find the start of the _MapFab block above it
  int fabStartIndex = -1;
  for (int i = cbmIndex; i >= 0; i--) {
    if (lines[i].contains('// Forestry Calculator')) {
      fabStartIndex = i;
      break;
    }
  }
  
  if (fabStartIndex == -1) {
    print('Forestry Calculator comment not found');
    return;
  }
  
  // Create the new block to insert
  final newBlock = [
    '                    // Duty Diary & Voice Assistant',
    '                    _MapFab(',
    '                      icon: Icons.mic_rounded,',
    '                      tooltip: \\'Duty Diary & Voice Assistant\\',',
    '                      color: Colors.orangeAccent,',
    '                      onTap: () {',
    '                        Navigator.push(',
    '                          context,',
    '                          MaterialPageRoute(builder: (context) => const DutyDiaryScreen()),',
    '                        );',
    '                      },',
    '                    ),',
    '                    const SizedBox(height: 6),',
    '                    '
  ];
  
  lines.insertAll(fabStartIndex, newBlock);
  
  // Add import if not present
  if (!lines.any((l) => l.contains('duty_diary_screen.dart'))) {
    int villageImportIndex = lines.indexWhere((l) => l.contains('villages_screen.dart'));
    if (villageImportIndex != -1) {
      lines.insert(villageImportIndex + 1, "import '../duty_diary/duty_diary_screen.dart';");
    } else {
      lines.insert(0, "import '../duty_diary/duty_diary_screen.dart';");
    }
  }

  file.writeAsStringSync(lines.join('\\n'));
  print('Successfully inserted DutyDiary FAB!');
}
