import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
        title: const Text('Delete Entry?', style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
    // Let user pick a date, we find the Monday of that week
    final initialDate = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select any date in the week to export',
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

    // Filter entries
    final weekEntries = _entries.where((e) {
      return e.date.compareTo(monStr) >= 0 && e.date.compareTo(sunStr) <= 0;
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Export Week: \${DateFormat('MMM d').format(monday)} - \${DateFormat('MMM d').format(sunday)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('\${weekEntries.length} entries found', style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              title: const Text('Export as PDF (A4 Weekly format)', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                DiaryPdfGenerator.generateWeeklyPdf(context, monday, weekEntries);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.greenAccent),
              title: const Text('Export as Soft Copy (CSV)', style: TextStyle(color: Colors.white)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Duty Diary', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.import_export, color: AppTheme.greenAccent),
            tooltip: 'Export Weekly Report',
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
        label: const Text('New Entry', style: TextStyle(color: Colors.white)),
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
            'No diary entries yet.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap + to log your daily patrol activities.',
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
        final dateStr = dt != null ? DateFormat('EEEE, MMM d, yyyy').format(dt) : entry.date;
        
        return Card(
          color: AppTheme.bgCard,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: InkWell(
            onTap: () => _openForm(entry),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
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
                      Text(
                        entry.time,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  _buildRow(Icons.place_outlined, entry.locations),
                  const SizedBox(height: 4),
                  _buildRow(Icons.directions_walk, '\${entry.distance.toStringAsFixed(1)} km'),
                  const SizedBox(height: 8),
                  Text(
                    entry.activities,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  ),
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
