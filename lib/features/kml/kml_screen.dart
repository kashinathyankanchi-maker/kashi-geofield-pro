import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../core/utils/storage_helper.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../shared/theme.dart';
import '../../core/database/db_helper.dart';
import '../../core/models/kml_file_model.dart';
import '../../core/utils/kml_engine.dart';
import 'kml_detail_screen.dart';
import '../kmz_exporter/kmz_exporter_screen.dart';

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
      final appDocDir = Directory(await StorageHelper.getAppStorageDirectory());
      final kmlDir = Directory(p.join(appDocDir.path, 'kml_files'));
      if (!await kmlDir.exists()) await kmlDir.create(recursive: true);

      final destName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(picked.path!)}';
      final destPath = p.join(kmlDir.path, destName);
      await sourceFile.copy(destPath);

      // Ask for Smart Opacity if it's a KMZ or KML
      bool useSmartOpacity = false;
      if (mounted) {
        useSmartOpacity = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: const Text('Smart Background Opacity', style: TextStyle(color: AppTheme.textPrimary)),
            content: const Text(
                'Would you like to separate the white/cyan background from the lines? '
                'If enabled, the opacity slider will ONLY fade the background, keeping lines fully visible.',
                style: TextStyle(color: AppTheme.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No, Standard Import'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.greenPrimary),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Yes, Enable'),
              ),
            ],
          ),
        ) ?? false;
      }

      if (useSmartOpacity) {
        _showSnack('Processing smart opacity... This may take a moment.');
        // This will extract images and create the fg/bg split files
        await KmlEngine.parseFile(destPath, smartOpacity: true);
      }

      final model = KmlFileModel(
        filename: picked.name,
        filepath: destPath,
        layerColor: '#2EA043',
        isVisible: true,
        opacity: 1.0,
        smartOpacity: useSmartOpacity,
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
        title: const Text('Delete KML/KMZ File?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Are you sure you want to delete "${kml.filename}"?', style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      if (kml.id != null) await DbHelper().deleteKmlFile(kml.id!);
      
      // Clean up extracted image overlays if any
      try {
        final shapes = await KmlEngine.parseFile(kml.filepath);
        for (final s in shapes) {
          if (s.type == 'overlay' && s.imageUrl != null) {
            final imgFile = File(s.imageUrl!);
            if (await imgFile.exists()) await imgFile.delete();
          }
        }
      } catch (_) {}

      final file = File(kml.filepath);
      if (await file.exists()) await file.delete();
      await _loadKmlFiles();
      _showSnack('"${kml.filename}" deleted');
    } catch (e) {
      _showSnack('Error deleting file: $e', isError: true);
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

  Future<void> _updateOpacity(KmlFileModel kml, int opacityPercent) async {
    try {
      if (kml.id != null) {
        await DbHelper().updateKmlOpacity(kml.id!, opacityPercent);
        await _loadKmlFiles();
      }
    } catch (e) {
      _showSnack('Failed to update opacity: $e', isError: true);
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
        title: const Text('Pick Layer Color', style: TextStyle(color: AppTheme.textPrimary)),
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

  Future<void> _showOpacityDialog(KmlFileModel kml) async {
    int currentOpacity = (kml.opacity * 100).round();
    int selectedOpacity = currentOpacity;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Layer Opacity', style: TextStyle(color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${selectedOpacity}%',
                style: const TextStyle(
                    color: AppTheme.greenAccent,
                    fontSize: 32,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Slider(
                min: 0,
                max: 100,
                divisions: 20,
                value: selectedOpacity.toDouble(),
                activeColor: AppTheme.greenAccent,
                inactiveColor: AppTheme.bgSurface,
                label: '$selectedOpacity%',
                onChanged: (v) =>
                    setDlgState(() => selectedOpacity = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('0% (Transparent)',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 10)),
                  const Text('100% (Opaque)',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 10)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.greenPrimary),
              onPressed: () {
                Navigator.pop(ctx);
                _updateOpacity(kml, selectedOpacity);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
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
        title: const Text('KML / KMZ Files'),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _kmlFiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) {
                  final kml = _kmlFiles[i];
                  return _KmlCard(
                    kml: kml,
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                          builder: (_) => KmlDetailScreen(kml: kml)),
                    ).then((_) => _loadKmlFiles()),
                    onLongPress: () => _showColorPicker(kml),
                    onToggleVisibility: () => _toggleVisibility(kml),
                    onOpacity: () => _showOpacityDialog(kml),
                    onShare: () => _shareKmlFile(kml),
                    onDelete: () => _deleteKmlFile(kml),
                    hexToColor: _hexToColor,
                  );
                },
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Image / TIFF → KMZ
          FloatingActionButton.extended(
            heroTag: 'fab_image_kmz',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KmzExporterScreen()),
            ),
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text('Image / TIFF → KMZ'),
            backgroundColor: const Color(0xFF00695C),
          ),
          const SizedBox(height: 10),
          // Import KML / KMZ
          FloatingActionButton.extended(
            heroTag: 'fab_import_kml',
            onPressed: _isImporting ? null : _importKmlFile,
            icon: _isImporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('Import KML / KMZ'),
            backgroundColor: AppTheme.greenPrimary,
          ),
        ],
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
            'No KML / KMZ Files',
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
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.greenPrimary),
          ),
        ],
      ),
    );
  }
}

// ── KML Card Widget ──────────────────────────────────────────────────────────

class _KmlCard extends StatelessWidget {
  final KmlFileModel kml;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleVisibility;
  final VoidCallback onOpacity;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final Color Function(String) hexToColor;

  const _KmlCard({
    required this.kml,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleVisibility,
    required this.onOpacity,
    required this.onShare,
    required this.onDelete,
    required this.hexToColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = hexToColor(kml.layerColor);
    final ext = kml.filename.split('.').last.toLowerCase();
    final isKmz = ext == 'kmz';
    final opacityPct = (kml.opacity * 100).round();

    return Card(
      color: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Icon with color
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
                        isKmz
                            ? Icons.folder_zip_outlined
                            : Icons.map_outlined,
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
                          isKmz ? 'KMZ File' : 'KML File',
                          style: TextStyle(
                              color: isKmz
                                  ? Colors.orangeAccent
                                  : AppTheme.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          kml.createdAt.length >= 10
                              ? 'Added ${kml.createdAt.substring(0, 10)}'
                              : kml.createdAt,
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  // ON/OFF Toggle
                  Column(
                    children: [
                      Switch(
                        value: kml.isVisible,
                        onChanged: (_) => onToggleVisibility(),
                        activeColor: AppTheme.greenAccent,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text(
                        kml.isVisible ? 'ON' : 'OFF',
                        style: TextStyle(
                          color: kml.isVisible
                              ? AppTheme.greenAccent
                              : AppTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  // More menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: AppTheme.textSecondary, size: 18),
                    color: AppTheme.bgCard,
                    onSelected: (val) {
                      if (val == 'share') onShare();
                      if (val == 'color') onLongPress();
                      if (val == 'opacity') onOpacity();
                      if (val == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'share',
                        child: Row(children: [
                          Icon(Icons.share,
                              size: 16, color: AppTheme.greenAccent),
                          SizedBox(width: 8),
                          Text('Share', style: TextStyle(color: AppTheme.textPrimary)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'color',
                        child: Row(children: [
                          Icon(Icons.palette,
                              size: 16, color: AppTheme.infoColor),
                          SizedBox(width: 8),
                          Text('Change Color', style: TextStyle(color: AppTheme.textPrimary)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'opacity',
                        child: Row(children: [
                          Icon(Icons.opacity,
                              size: 16, color: Colors.lightBlueAccent),
                          SizedBox(width: 8),
                          Text('Set Opacity', style: TextStyle(color: AppTheme.textPrimary)),
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
              const SizedBox(height: 10),
              // Opacity bar row
              Row(
                children: [
                  const Icon(Icons.opacity,
                      size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  const Text('Opacity',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 11)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: kml.opacity,
                        backgroundColor:
                            AppTheme.bgSurface,
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$opacityPct%',
                    style: TextStyle(
                        color: opacityPct < 30
                            ? AppTheme.textMuted
                            : color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onOpacity,
                    child: const Icon(Icons.edit,
                        size: 14, color: AppTheme.textSecondary),
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
