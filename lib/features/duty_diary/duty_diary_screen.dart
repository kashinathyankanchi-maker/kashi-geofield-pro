import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/duty_diary_model.dart';
import 'duty_diary_form_screen.dart';
import 'diary_pdf_generator.dart';
import '../../core/database/db_helper.dart';
import '../../shared/theme.dart';

class DutyDiaryScreen extends StatefulWidget {
  const DutyDiaryScreen({super.key});

  @override
  State<DutyDiaryScreen> createState() => _DutyDiaryScreenState();
}

class _DutyDiaryScreenState extends State<DutyDiaryScreen> {
  List<DutyDiaryModel> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    final raw = await DbHelper().getAllDutyDiaries();
    setState(() {
      _entries = raw.map((m) => DutyDiaryModel.fromMap(m)).toList();
      _isLoading = false;
    });
  }

  void _openForm([DutyDiaryModel? entry]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DutyDiaryFormScreen(entry: entry)),
    );
    if (result == true) {
      _loadEntries();
    }
  }

  Future<void> _deleteEntry(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('ನಮೂದನ್ನು ಅಳಿಸಬೇಕೇ?', style: TextStyle(color: Colors.white)),
        content: const Text('ಈ ಚಟುವಟಿಕೆಯನ್ನು ಮತ್ತೆ ಹಿಂಪಡೆಯಲು ಸಾಧ್ಯವಿಲ್ಲ.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ರದ್ದುಗೊಳಿಸಿ')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ಅಳಿಸಿ (Delete)', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DbHelper().deleteDutyDiary(id);
      _loadEntries();
    }
  }

  Future<void> _exportWeeklyReport() async {
    final initialDate = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'ವರದಿ ರಫ್ತು ಮಾಡಲು ವಾರದ ಯಾವುದಾದರೂ ದಿನಾಂಕ ಆಯ್ಕೆ ಮಾಡಿ',
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.greenPrimary,
              onPrimary: Colors.white,
              surface: AppTheme.bgCard,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    // Find Monday of that week (weekday 1 = Monday)
    final monday = picked.subtract(Duration(days: picked.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    final dateFormat = DateFormat('yyyy-MM-dd');
    final monStr = dateFormat.format(monday);
    final sunStr = dateFormat.format(sunday);

    final weekEntries = _entries.where((e) {
      return e.date.compareTo(monStr) >= 0 && e.date.compareTo(sunStr) <= 0;
    }).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'ವಾರದ ದಿನಚರಿ ಯಾದಿ: ${DateFormat('dd/MM').format(monday)} - ${DateFormat('dd/MM/yyyy').format(sunday)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${weekEntries.length} ದಿನಗಳ ದಾಖಲೆಗಳು ಕಂಡುಬಂದಿವೆ',
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              title: const Text('PDF ರೂಪದಲ್ಲಿ ರಫ್ತು ಮಾಡಿ (ಅಧಿಕೃತ ದಿನಚರಿ ಯಾದಿ)',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showOfficerInfoDialog(monday, weekEntries);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.greenAccent),
              title: const Text('CSV (Excel) ರೂಪದಲ್ಲಿ ರಫ್ತು ಮಾಡಿ',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                DiaryPdfGenerator.generateWeeklyCsv(context, monday, weekEntries);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showOfficerInfoDialog(DateTime monday, List<DutyDiaryModel> weekEntries) {
    showDialog(
      context: context,
      builder: (ctx) => _OfficerInfoDialog(
        monday: monday,
        weekEntries: weekEntries,
      ),
    );
  }
}

class _OfficerInfoDialog extends StatefulWidget {
  final DateTime monday;
  final List<DutyDiaryModel> weekEntries;

  const _OfficerInfoDialog({
    required this.monday,
    required this.weekEntries,
  });

  @override
  State<_OfficerInfoDialog> createState() => _OfficerInfoDialogState();
}

class _OfficerInfoDialogState extends State<_OfficerInfoDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _customDesigCtrl;
  late TextEditingController _rangeCtrl;
  late TextEditingController _divCtrl;

  final List<String> _designationOptions = [
    'ಉಪವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿ',
    'ಗಸ್ತು ವನಪಾಲಕ',
    'ವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿ',
    'ಅರಣ್ಯ ರಕ್ಷಕ',
    'ವನಪಾಲಕ',
    'ವಿಭಾಗಾಧಿಕಾರಿ',
    'ಇತರೆ / Custom',
  ];

  String _selectedDesignation = 'ಉಪವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿ';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _customDesigCtrl = TextEditingController();
    _rangeCtrl = TextEditingController();
    _divCtrl = TextEditingController();
    _loadSavedHeaderData();
  }

  Future<void> _loadSavedHeaderData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('diary_officer_name') ?? '';
    final desig = prefs.getString('diary_designation') ?? 'ಉಪವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿ';
    final range = prefs.getString('diary_range_name') ?? '';
    final div = prefs.getString('diary_division_name') ?? '';

    setState(() {
      _nameCtrl.text = name;
      _rangeCtrl.text = range;
      _divCtrl.text = div;
      if (_designationOptions.contains(desig)) {
        _selectedDesignation = desig;
      } else {
        _selectedDesignation = 'ಇತರೆ / Custom';
        _customDesigCtrl.text = desig;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveAndGeneratePdf() async {
    final name = _nameCtrl.text.trim();
    final desig = _selectedDesignation == 'ಇತರೆ / Custom'
        ? _customDesigCtrl.text.trim()
        : _selectedDesignation;
    final range = _rangeCtrl.text.trim();
    final div = _divCtrl.text.trim();

    // Persist user fed data so they don't need to re-enter every time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('diary_officer_name', name);
    await prefs.setString('diary_designation', desig);
    await prefs.setString('diary_range_name', range);
    await prefs.setString('diary_division_name', div);

    if (!mounted) return;
    Navigator.pop(context);

    DiaryPdfGenerator.generateWeeklyPdf(
      context,
      widget.monday,
      widget.weekEntries,
      officerName: name,
      designation: desig,
      range: range,
      division: div,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customDesigCtrl.dispose();
    _rangeCtrl.dispose();
    _divCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.assignment_ind_outlined, color: AppTheme.greenAccent, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ಅಧಿಕಾರಿಯ ವಿವರಗಳು (PDF Header)',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(color: AppTheme.greenPrimary)),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ದಾಖಲಿಸಿದ ವಿವರಗಳು ಉಳಿಯುತ್ತವೆ (Persistent Data). ಪ್ರತಿ ಬಾರಿಯೂ ಮರು-ನಮೂದಿಸುವ ಅಗತ್ಯವಿಲ್ಲ.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 14),

                  // 1. Officer Name
                  _dialogField(_nameCtrl, 'ಅಧಿಕಾರಿಯ ಹೆಸರು (Officer Name)', Icons.person_outline),
                  const SizedBox(height: 12),

                  // 2. Designation Dropdown
                  const Text(
                    'ಹುದ್ದೆ (Designation)',
                    style: TextStyle(color: AppTheme.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedDesignation,
                        isExpanded: true,
                        dropdownColor: AppTheme.bgCard,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: _designationOptions.map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text(d),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedDesignation = val);
                        },
                      ),
                    ),
                  ),
                  if (_selectedDesignation == 'ಇತರೆ / Custom') ...[
                    const SizedBox(height: 8),
                    _dialogField(_customDesigCtrl, 'ನಿಮ್ಮ ಹುದ್ದೆಯನ್ನು ಟೈಪ್ ಮಾಡಿ', Icons.badge_outlined),
                  ],
                  const SizedBox(height: 12),

                  // 3. Range Name
                  _dialogField(_rangeCtrl, 'ವಲಯ ಹೆಸರು (Range Name)', Icons.landscape_outlined),
                  const SizedBox(height: 12),

                  // 4. Division Name
                  _dialogField(_divCtrl, 'ವಿಭಾಗ ಹೆಸರು (Division Name)', Icons.business_outlined),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ರದ್ದುಗೊಳಿಸಿ', style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.greenPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _saveAndGeneratePdf,
          icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
          label: const Text('PDF ರಚಿಸಿ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _dialogField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 18),
        filled: true,
        fillColor: AppTheme.bgSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.borderColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.greenPrimary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Text('ದಿನಚರಿ ಯಾದಿ (Duty Diary)', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.greenAccent),
            tooltip: 'ವಾರದ ವರದಿ PDF ರಫ್ತು',
            onPressed: _exportWeeklyReport,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.greenPrimary))
          : _entries.isEmpty
              ? _buildEmptyState()
              : _buildList(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.greenPrimary,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('ಹೊಸ ನಮೂದು', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_rounded, size: 64, color: AppTheme.textMuted.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            'ಇನ್ನೂ ಯಾವುದೇ ದಿನಚರಿ ದಾಖಲಾಗಿಲ್ಲ.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'ದೈನಂದಿನ ಗಸ್ತು ವಿವರ ಸೇರಿಸಲು + ಬಟನ್ ಒತ್ತಿ.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final dt = DateTime.tryParse(entry.date);
        
        final dayNames = ['ಸೋಮವಾರ', 'ಮಂಗಳವಾರ', 'ಬುಧವಾರ', 'ಗುರುವಾರ', 'ಶುಕ್ರವಾರ', 'ಶನಿವಾರ', 'ಭಾನುವಾರ'];
        String dateStr = entry.date;
        if (dt != null) {
          final knDay = dayNames[dt.weekday - 1];
          dateStr = '$knDay, ${DateFormat('dd/MM/yyyy').format(dt)}';
        }

        final camp = entry.campStation.isNotEmpty ? entry.campStation : entry.locations;
        final places = entry.placesVisited.isNotEmpty ? entry.placesVisited : entry.locations;
        final work = entry.workDone.isNotEmpty ? entry.workDone : entry.activities;
        final mode = entry.modeAndKm.isNotEmpty ? entry.modeAndKm : (entry.distance > 0 ? '${entry.distance} KM' : '');

        return Card(
          color: AppTheme.bgCard,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: InkWell(
            onTap: () => _openForm(entry),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(
                            color: AppTheme.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      if (entry.departureTime.isNotEmpty || entry.returnTime.isNotEmpty)
                        Text(
                          '${entry.departureTime} ➔ ${entry.returnTime}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        )
                      else if (entry.time.isNotEmpty)
                        Text(
                          entry.time,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  
                  if (camp.isNotEmpty) ...[
                    _buildRow(Icons.home_work_outlined, 'ಮುಕ್ಕಾಂ: $camp'),
                    const SizedBox(height: 4),
                  ],
                  if (places.isNotEmpty) ...[
                    _buildRow(Icons.place_outlined, 'ಸ್ಥಳ: $places'),
                    const SizedBox(height: 4),
                  ],
                  if (mode.isNotEmpty) ...[
                    _buildRow(Icons.directions_bike_outlined, 'ರೀತಿ/ಕಿ.ಮೀ: $mode'),
                    const SizedBox(height: 6),
                  ],
                  if (work.isNotEmpty) ...[
                    Text(
                      work,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    ),
                  ],

                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _deleteEntry(entry.id!),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
