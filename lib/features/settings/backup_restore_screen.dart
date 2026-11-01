import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/db_helper.dart';
import '../../core/models/polygon_model.dart';
import '../../core/utils/backup_helper.dart';
import '../../shared/theme.dart';

/// ── Backup & Restore Screen ──────────────────────────────────────────────────
/// Shows all backed-up data (polygons, markers, villages, KML, duty diary) and
/// lets the user Export, Import/Restore, and Edit each record directly.
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  bool _busy = false;

  List<PolygonModel> _shapes = [];
  List<Map<String, dynamic>> _diary = [];
  List<Map<String, dynamic>> _villages = [];

  // Counts for summary cards
  int get _polygons => _shapes.where((s) => _isPolygon(s)).length;
  int get _markers  => _shapes.where((s) => !_isPolygon(s)).length;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isPolygon(PolygonModel p) {
    try {
      final list = jsonDecode(p.coordinates) as List;
      return list.length > 1;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final db = DbHelper();
      final shapes  = await db.getAllPolygons();
      final diary   = await db.getAllDutyDiaries();
      final dbObj   = await db.database;
      final villages = await dbObj.query('village_maps', orderBy: 'village_name ASC');

      setState(() {
        _shapes   = shapes;
        _diary    = diary;
        _villages = villages;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── EXPORT ───────────────────────────────────────────────────────────────────
  Future<void> _doExport() async {
    setState(() => _busy = true);
    try {
      final result = await BackupHelper.exportAllData(context);
      if (!mounted) return;
      _showToast(result.success ? '✅ ${result.message}' : '❌ ${result.message}',
          success: result.success);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── IMPORT ───────────────────────────────────────────────────────────────────
  Future<void> _doImport() async {
    setState(() => _busy = true);
    try {
      final result = await BackupHelper.importData(context);
      if (!mounted) return;
      if (!result.cancelled) {
        _showResultSheet(
          icon: result.success ? Icons.check_circle_rounded : Icons.error_rounded,
          iconColor: result.success ? AppTheme.greenAccent : AppTheme.errorColor,
          title: result.success ? 'Restore Complete' : 'Restore Failed',
          body: result.message,
        );
        if (result.success) await _loadData();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── AUTO-SCAN ────────────────────────────────────────────────────────────────
  Future<void> _doAutoScan() async {
    setState(() => _busy = true);
    try {
      final db = DbHelper();
      final dbObj = await db.database;
      await db.checkAndRestoreBackup(dbObj);
      if (!mounted) return;
      await _loadData();
      _showToast('✅ Device scan complete — data updated', success: true);
    } catch (e) {
      if (!mounted) return;
      _showToast('❌ Scan failed: $e', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showToast(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: success ? AppTheme.greenPrimary : AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showResultSheet({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: iconColor, size: 56),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(
            color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.greenPrimary,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(fontSize: 15)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        title: const Text('Backup & Restore',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.greenAccent,
          labelColor: AppTheme.greenAccent,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.shield_rounded, size: 18), text: 'Backup'),
            Tab(icon: Icon(Icons.pentagon_rounded, size: 18), text: 'Shapes'),
            Tab(icon: Icon(Icons.book_rounded, size: 18), text: 'Diary'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.greenAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBackupTab(),
                _buildShapesTab(),
                _buildDiaryTab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1 — BACKUP
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildBackupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Summary cards
        Row(children: [
          _SummaryCard(label: 'Polygons',  value: '$_polygons',         icon: Icons.pentagon,          color: AppTheme.greenAccent),
          const SizedBox(width: 8),
          _SummaryCard(label: 'Markers',   value: '$_markers',          icon: Icons.place_rounded,     color: AppTheme.warningColor),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _SummaryCard(label: 'Villages',  value: '${_villages.length}',icon: Icons.location_city,     color: AppTheme.infoColor),
          const SizedBox(width: 8),
          _SummaryCard(label: 'Diary',     value: '${_diary.length}',   icon: Icons.book_rounded,      color: const Color(0xFFBA68C8)),
        ]),

        const SizedBox(height: 24),

        // Export card
        _ActionCard(
          icon: Icons.upload_rounded,
          iconColor: AppTheme.greenAccent,
          title: 'Export / Backup',
          subtitle: 'Save all data (polygons, markers, KML files, diary, settings) to a .kgfp backup file and share/save it to your device or cloud.',
          badge: '${_shapes.length + _diary.length + _villages.length} records',
          badgeColor: AppTheme.greenPrimary,
          buttonLabel: _busy ? 'Exporting…' : 'Export Backup',
          buttonIcon: Icons.upload_rounded,
          onTap: _busy ? null : _doExport,
        ),

        const SizedBox(height: 16),

        // Import card
        _ActionCard(
          icon: Icons.download_rounded,
          iconColor: AppTheme.infoColor,
          title: 'Import / Restore',
          subtitle: 'Pick a .kgfp or .db backup file from your device. All shapes, markers, KML files, and diary entries will be restored and become fully editable.',
          badge: 'Supports .kgfp & .db',
          badgeColor: AppTheme.infoColor,
          buttonLabel: _busy ? 'Restoring…' : 'Import Backup',
          buttonIcon: Icons.download_rounded,
          onTap: _busy ? null : _doImport,
        ),

        const SizedBox(height: 16),

        // Auto-scan card
        _ActionCard(
          icon: Icons.manage_search_rounded,
          iconColor: AppTheme.warningColor,
          title: 'Auto-Scan Device',
          subtitle: 'Scan device storage for auto-saved backup files and restore any missing data. Useful after reinstalling the app.',
          badge: 'Searches storage',
          badgeColor: AppTheme.warningColor,
          buttonLabel: _busy ? 'Scanning…' : 'Scan & Restore',
          buttonIcon: Icons.manage_search_rounded,
          onTap: _busy ? null : _doAutoScan,
        ),

        const SizedBox(height: 24),

        // How it works info box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.greenPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.greenPrimary.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppTheme.greenAccent, size: 16),
              SizedBox(width: 6),
              Text('How Backup Works', style: TextStyle(
                color: AppTheme.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
            const SizedBox(height: 8),
            _InfoStep(n: '1', text: 'Tap Export Backup → share or save the .kgfp file to Google Drive, WhatsApp, or local folder.'),
            _InfoStep(n: '2', text: 'Uninstall & reinstall the app on the same or new device.'),
            _InfoStep(n: '3', text: 'Open Settings → Backup & Restore → Import Backup → select the .kgfp file.'),
            _InfoStep(n: '4', text: 'All shapes, markers, photos, voice notes and diary entries are fully restored and editable immediately.'),
          ]),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2 — SHAPES (editable list)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildShapesTab() {
    if (_shapes.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.pentagon_outlined, color: AppTheme.textMuted, size: 64),
          SizedBox(height: 12),
          Text('No shapes saved yet', style: TextStyle(color: AppTheme.textSecondary)),
        ]),
      );
    }

    return Column(children: [
      // Filter bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Text('${_shapes.length} records',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 20),
            onPressed: _loadData,
          ),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: _shapes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _ShapeListTile(
            model: _shapes[i],
            onEdit: () => _openShapeEditor(_shapes[i]),
            onDelete: () => _deleteShape(_shapes[i]),
            onShare: () => _shareShape(_shapes[i]),
          ),
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3 — DIARY
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDiaryTab() {
    if (_diary.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.book_outlined, color: AppTheme.textMuted, size: 64),
          SizedBox(height: 12),
          Text('No diary entries', style: TextStyle(color: AppTheme.textSecondary)),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _diary.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = _diary[i];
        final dateStr = d['date'] as String? ?? '';
        final camp    = d['camp_station'] as String? ?? '';
        final work    = d['work_done'] as String? ?? '';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFBA68C8).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.book_rounded, color: Color(0xFFBA68C8), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dateStr, style: const TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                if (camp.isNotEmpty)
                  Text('Camp: $camp',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                if (work.isNotEmpty)
                  Text(work, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ]),
            ),
          ]),
        );
      },
    );
  }

  // ── Edit shape dialog ────────────────────────────────────────────────────────
  void _openShapeEditor(PolygonModel model) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ShapeEditorSheet(
        model: model,
        onSaved: (updated) async {
          final db = DbHelper();
          await db.updatePolygon(updated);
          await _loadData();
          if (mounted) _showToast('✅ "${updated.name}" saved', success: true);
        },
      ),
    );
  }

  Future<void> _deleteShape(PolygonModel model) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete Shape?',
          style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Delete "${model.name}"? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && model.id != null) {
      await DbHelper().deletePolygon(model.id!);
      await _loadData();
      if (mounted) _showToast('Deleted "${model.name}"', success: true);
    }
  }

  void _shareShape(PolygonModel model) {
    try {
      final coords = (jsonDecode(model.coordinates) as List)
          .map((c) => c is Map ? '${c['lat']},${c['lng']}' : c.toString())
          .join(' → ');
      final text = '''Shape: ${model.name}
Type: ${_isPolygon(model) ? 'Polygon' : 'Marker/Path'}
Area: ${model.areaHectares.toStringAsFixed(4)} ha
Perimeter: ${model.perimeterMeters.toStringAsFixed(1)} m
Created: ${model.createdAt.substring(0, 10)}
${model.description != null ? 'Description: ${model.description}' : ''}
Coordinates: $coords
      ''';
      Share.share(text, subject: 'Shape: ${model.name}');
    } catch (_) {
      Share.share('Shape: ${model.name}\nArea: ${model.areaHectares} ha');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHAPE EDITOR BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════
class _ShapeEditorSheet extends StatefulWidget {
  final PolygonModel model;
  final void Function(PolygonModel) onSaved;

  const _ShapeEditorSheet({required this.model, required this.onSaved});

  @override
  State<_ShapeEditorSheet> createState() => _ShapeEditorSheetState();
}

class _ShapeEditorSheetState extends State<_ShapeEditorSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _officerCtrl;
  late Color _color;
  bool _saving = false;

  static const _colorPalette = [
    Color(0xFF2EA043), Color(0xFF39D353), Color(0xFF1E88E5),
    Color(0xFFE53935), Color(0xFFFFB300), Color(0xFF8E24AA),
    Color(0xFF00ACC1), Color(0xFFFF7043), Color(0xFF6D4C41),
    Color(0xFF757575), Color(0xFF43A047), Color(0xFFC0CA33),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl   = TextEditingController(text: widget.model.name);
    _descCtrl   = TextEditingController(text: widget.model.description ?? '');
    _officerCtrl = TextEditingController(text: widget.model.officerName ?? '');
    // Parse hex color
    _color = _hexToColor(widget.model.color);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _officerCtrl.dispose();
    super.dispose();
  }

  Color _hexToColor(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return AppTheme.greenAccent;
    }
  }

  String _colorToHex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')));
      return;
    }
    setState(() => _saving = true);
    final updated = widget.model.copyWith(
      name: newName,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      officerName: _officerCtrl.text.trim().isEmpty ? null : _officerCtrl.text.trim(),
      color: _colorToHex(_color),
    );
    widget.onSaved(updated);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isPolygon = (() {
      try { return (jsonDecode(widget.model.coordinates) as List).length > 1; } catch (_) { return false; }
    })();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16,
        MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.borderColor, borderRadius: BorderRadius.circular(2)),
        )),

        // Header
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _color),
            ),
            child: Icon(
              isPolygon ? Icons.pentagon_rounded : Icons.place_rounded,
              color: _color, size: 18),
          ),
          const SizedBox(width: 12),
          const Text('Edit Shape', style: TextStyle(
            color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'ID: ${widget.model.id ?? '—'}  •  Created: ${widget.model.createdAt.substring(0, 10)}',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        const SizedBox(height: 14),
        const Divider(color: AppTheme.borderColor, height: 1),
        const SizedBox(height: 14),

        // Name field
        _EditorField(label: 'Name', ctrl: _nameCtrl, hint: 'Shape name'),
        const SizedBox(height: 10),

        // Description field
        _EditorField(label: 'Description', ctrl: _descCtrl,
          hint: 'Enter notes or description', maxLines: 3),
        const SizedBox(height: 10),

        // Officer field
        _EditorField(label: 'Officer / Beat', ctrl: _officerCtrl,
          hint: 'Officer or beat name'),
        const SizedBox(height: 14),

        // Color picker row
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(width: 4,
            child: Text('', style: TextStyle(color: AppTheme.textMuted, fontSize: 11))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Color', style: TextStyle(
                color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _colorPalette.map((c) => GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: _color == c
                          ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)]
                          : null,
                    ),
                    child: _color == c
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                        : null,
                  ),
                )).toList(),
              ),
            ]),
          ),
        ]),

        const SizedBox(height: 16),

        // Stats row (read-only)
        if (isPolygon) ...[
          Row(children: [
            _StatBadge(label: 'Area',
              value: '${widget.model.areaHectares.toStringAsFixed(4)} ha'),
            const SizedBox(width: 8),
            _StatBadge(label: 'Perimeter',
              value: '${widget.model.perimeterMeters.toStringAsFixed(1)} m'),
          ]),
          const SizedBox(height: 14),
        ],

        // Save button
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.greenPrimary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded),
          label: Text(_saving ? 'Saving…' : 'Save Changes',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHAPE LIST TILE
// ═══════════════════════════════════════════════════════════════════════════════
class _ShapeListTile extends StatelessWidget {
  final PolygonModel model;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _ShapeListTile({
    required this.model, required this.onEdit,
    required this.onDelete, required this.onShare,
  });

  bool get _isPolygon {
    try { return (jsonDecode(model.coordinates) as List).length > 1; }
    catch (_) { return false; }
  }

  Color get _shapeColor {
    try {
      final clean = model.color.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) { return AppTheme.greenAccent; }
  }

  @override
  Widget build(BuildContext context) {
    final color = _shapeColor;
    final isPolygon = _isPolygon;
    final date = model.createdAt.length >= 10 ? model.createdAt.substring(0, 10) : '';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Color+icon indicator
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(
                isPolygon ? Icons.pentagon_rounded : Icons.place_rounded,
                color: color, size: 22),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(model.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4)),
                    child: Text(isPolygon ? 'Polygon' : 'Marker/Path',
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Text(date, style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 11)),
                ]),
                if (isPolygon) ...[
                  const SizedBox(height: 2),
                  Text('${model.areaHectares.toStringAsFixed(3)} ha  •  ${model.perimeterMeters.toStringAsFixed(0)} m',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
                if (model.description != null && model.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(model.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ],
              ]),
            ),
            // Actions
            PopupMenuButton<String>(
              color: AppTheme.bgCard,
              icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary, size: 20),
              onSelected: (v) {
                if (v == 'edit')   onEdit();
                if (v == 'share')  onShare();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, color: AppTheme.greenAccent, size: 18),
                    SizedBox(width: 8),
                    Text('Edit', style: TextStyle(color: AppTheme.textPrimary)),
                  ])),
                PopupMenuItem(value: 'share',
                  child: Row(children: [
                    Icon(Icons.share_rounded, color: AppTheme.infoColor, size: 18),
                    SizedBox(width: 8),
                    Text('Share', style: TextStyle(color: AppTheme.textPrimary)),
                  ])),
                PopupMenuItem(value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, color: AppTheme.errorColor, size: 18),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
                  ])),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMALL HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(
            color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 11)),
        ]),
      ]),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final String buttonLabel;
  final IconData buttonIcon;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.badge, required this.badgeColor,
    required this.buttonLabel, required this.buttonIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(color: iconColor.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(badge, style: TextStyle(
              color: badgeColor, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 10),
        Text(subtitle, style: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: iconColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            disabledBackgroundColor: iconColor.withValues(alpha: 0.4),
          ),
          onPressed: onTap,
          icon: Icon(buttonIcon, size: 18),
          label: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final String n;
  final String text;
  const _InfoStep({required this.n, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 18, height: 18,
        margin: const EdgeInsets.only(right: 8, top: 1),
        decoration: BoxDecoration(
          color: AppTheme.greenAccent.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(n, style: const TextStyle(
          color: AppTheme.greenAccent, fontSize: 10, fontWeight: FontWeight.bold))),
      ),
      Expanded(child: Text(text, style: const TextStyle(
        color: AppTheme.textSecondary, fontSize: 12, height: 1.4))),
    ]),
  );
}

class _EditorField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final int maxLines;

  const _EditorField({
    required this.label, required this.ctrl, required this.hint, this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(
      color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    const SizedBox(height: 4),
    TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textMuted),
        filled: true,
        fillColor: AppTheme.bgSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.greenAccent, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.borderColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
  ]);
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  const _StatBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.greenPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.greenPrimary.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(
          color: AppTheme.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
    ),
  );
}
