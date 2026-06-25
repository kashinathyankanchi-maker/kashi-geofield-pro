import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../shared/theme.dart';
import '../../core/database/db_helper.dart';
import '../../core/models/kml_file_model.dart';
import 'kml_detail_screen.dart';

class KmlScreen extends StatefulWidget {
  const KmlScreen({super.key});

  @override
  State<KmlScreen> createState() => _KmlScreenState();
}

class _KmlScreenState extends State<KmlScreen> {
  List<KmlFileModel> _kmlFiles = [];
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadKmlFiles();
  }

  Future<void> _loadKmlFiles() async {
    try {
      final files = await DbHelper().getAllKmlFiles();
      if (mounted) setState(() => _kmlFiles = files);
    } catch (e) {
      _showSnack('Failed to load KML files: $e', isError: true);
    }
  }

  Future<void> _importKmlFile() async {
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kml', 'kmz'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isImporting = false);
        return;
      }

      final picked = result.files.first;
      if (picked.path == null) {
        _showSnack('Could not access file', isError: true);
        setState(() => _isImporting = false);
        return;
      }

      final sourceFile = File(picked.path!);
      final appDocDir = await getApplicationDocumentsDirectory();
      final kmlDir = Directory(p.join(appDocDir.path, 'kml_files'));
      if (!await kmlDir.exists()) await kmlDir.create(recursive: true);

      final destName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(picked.path!)}';
      final destPath = p.join(kmlDir.path, destName);
      await sourceFile.copy(destPath);

      final model = KmlFileModel(
        filename: picked.name,
        filepath: destPath,
        layerColor: '#2EA043',
        isVisible: true,
        createdAt: DateTime.now().toIso8601String(),
      );

      await DbHelper().insertKmlFile(model);
      await _loadKmlFiles();
      _showSnack('${picked.name} imported successfully');
    } catch (e) {
      _showSnack('Import failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _deleteKmlFile(KmlFileModel kml) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete KML File?'),
        content: Text('Delete "${kml.filename}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      if (kml.id != null) await DbHelper().deleteKmlFile(kml.id!);
      final file = File(kml.filepath);
      if (await file.exists()) await file.delete();
      await _loadKmlFiles();
      _showSnack('"${kml.filename}" deleted');
    } catch (e) {
      _showSnack('Delete failed: $e', isError: true);
    }
  }

  Future<void> _toggleVisibility(KmlFileModel kml) async {
    try {
      if (kml.id != null) {
        await DbHelper().updateKmlVisibility(kml.id!, !kml.isVisible);
        await _loadKmlFiles();
      }
    } catch (e) {
      _showSnack('Failed to update: $e', isError: true);
    }
  }

  Future<void> _shareKmlFile(KmlFileModel kml) async {
    try {
      if (!await File(kml.filepath).exists()) {
        _showSnack('File not found on disk', isError: true);
        return;
      }
      await Share.shareXFiles([XFile(kml.filepath)], subject: kml.filename);
    } catch (e) {
      _showSnack('Share failed: $e', isError: true);
    }
  }

  Future<void> _showColorPicker(KmlFileModel kml) async {
    Color pickedColor = _hexToColor(kml.layerColor);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Pick Layer Color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: pickedColor,
            availableColors: AppTheme.polygonColors,
            onColorChanged: (c) => pickedColor = c,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed == true && kml.id != null) {
      final hex =
          '#${pickedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      await DbHelper().updateKmlColor(kml.id!, hex);
      await _loadKmlFiles();
    }
  }

  Color _hexToColor(String hex) {
    try {
      final h = hex.replaceFirst('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppTheme.greenPrimary;
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.errorColor : AppTheme.greenPrimary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('KML Files'),
        actions: [
          IconButton(
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_circle_outline),
            tooltip: 'Import KML/KMZ',
            onPressed: _isImporting ? null : _importKmlFile,
          ),
        ],
      ),
      body: _kmlFiles.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadKmlFiles,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _kmlFiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) {
                  final kml = _kmlFiles[i];
                  return _KmlCard(
                    kml: kml,
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => KmlDetailScreen(kml: kml),
                      ),
                    ).then((_) => _loadKmlFiles()),
                    onLongPress: () => _showColorPicker(kml),
                    onToggleVisibility: () => _toggleVisibility(kml),
                    onShare: () => _shareKmlFile(kml),
                    onDelete: () => _deleteKmlFile(kml),
                    hexToColor: _hexToColor,
                  );
                },
              ),
            ),
      floatingActionButton: _kmlFiles.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isImporting ? null : _importKmlFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import KML'),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.layers_outlined,
                size: 64, color: AppTheme.warningColor),
          ),
          const SizedBox(height: 16),
          const Text(
            'No KML Files',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Import KML or KMZ files from your device\nto display them on the map',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _importKmlFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import KML / KMZ'),
          ),
        ],
      ),
    );
  }
}

class _KmlCard extends StatelessWidget {
  final KmlFileModel kml;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleVisibility;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final Color Function(String) hexToColor;

  const _KmlCard({
    required this.kml,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleVisibility,
    required this.onShare,
    required this.onDelete,
    required this.hexToColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = hexToColor(kml.layerColor);
    final ext = kml.filename.split('.').last.toLowerCase();
    final isKmz = ext == 'kmz';

    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Color dot / layer indicator
              GestureDetector(
                onTap: onLongPress,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(
                    isKmz ? Icons.folder_zip_outlined : Icons.map_outlined,
                    color: color,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kml.filename,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kml.createdAt.length >= 10
                          ? 'Added ${kml.createdAt.substring(0, 10)}'
                          : kml.createdAt,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        kml.layerColor.toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 10),
                      ),
                    ]),
                  ],
                ),
              ),
              // Visibility toggle
              Switch(
                value: kml.isVisible,
                onChanged: (_) => onToggleVisibility(),
                activeColor: AppTheme.greenAccent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              // Actions
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: AppTheme.textSecondary, size: 18),
                color: AppTheme.bgCard,
                onSelected: (val) {
                  if (val == 'share') onShare();
                  if (val == 'color') onLongPress();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(children: [
                      Icon(Icons.share, size: 16, color: AppTheme.greenAccent),
                      SizedBox(width: 8),
                      Text('Share'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'color',
                    child: Row(children: [
                      Icon(Icons.palette, size: 16, color: AppTheme.infoColor),
                      SizedBox(width: 8),
                      Text('Change Color'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 16, color: AppTheme.errorColor),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
