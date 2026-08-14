import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../shared/theme.dart';
import '../../core/models/kml_file_model.dart';
import '../../core/utils/kml_engine.dart';
import '../../core/database/db_helper.dart';
import '../../core/utils/storage_helper.dart';

class KmlDetailScreen extends StatefulWidget {
  final KmlFileModel kml;
  const KmlDetailScreen({super.key, required this.kml});

  @override
  State<KmlDetailScreen> createState() => _KmlDetailScreenState();
}

class _KmlDetailScreenState extends State<KmlDetailScreen> {
  late KmlFileModel _kml;
  List<KmlShape> _shapes = [];
  bool _isParsing = false;
  bool _isExporting = false;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _kml = widget.kml;
    _parseKmlFile();
  }

  Future<void> _parseKmlFile() async {
    setState(() { _isParsing = true; _parseError = null; });
    try {
      final shapes = await KmlEngine.parseFile(_kml.filepath);
      if (mounted) setState(() { _shapes = shapes; _isParsing = false; });
    } catch (e) {
      if (mounted) setState(() { _parseError = e.toString(); _isParsing = false; });
    }
  }

  Future<void> _shareKmlFile() async {
    try {
      if (!await File(_kml.filepath).exists()) {
        _showSnack('File not found on disk', isError: true);
        return;
      }
      await Share.shareXFiles([XFile(_kml.filepath)], subject: _kml.filename);
    } catch (e) {
      _showSnack('Share failed: $e', isError: true);
    }
  }

  Future<void> _exportAsKmz() async {
    setState(() => _isExporting = true);
    try {
      final sourceFile = File(_kml.filepath);
      if (!await sourceFile.exists()) {
        _showSnack('Source KML file not found', isError: true);
        return;
      }
      final kmlContent = await sourceFile.readAsString();

      // Save directly to the main 'kashi geofild pro' folder (visible in file manager)
      final appDir = Directory(await StorageHelper.getAppStorageDirectory());
      if (!await appDir.exists()) await appDir.create(recursive: true);

      final baseName = p.basenameWithoutExtension(_kml.filename);
      final kmzFileName = '${baseName}_${DateTime.now().millisecondsSinceEpoch}.kmz';
      final kmzPath = p.join(appDir.path, kmzFileName);
      final kmzBytes = KmlEngine.generateKmz(kmlContent, '$baseName.kml');
      await File(kmzPath).writeAsBytes(kmzBytes);

      if (mounted) {
        // Show dialog with save path and share/done options
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 28),
                SizedBox(width: 10),
                Text('KMZ Saved!', style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('File saved to internal storage:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    kmzPath,
                    style: const TextStyle(color: Color(0xFF80CBC4), fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Open your Files app → Internal Storage → "kashi geofild pro" to find it.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await Share.shareXFiles(
                    [XFile(kmzPath, mimeType: 'application/vnd.google-earth.kmz')],
                    subject: '$baseName.kmz',
                  );
                },
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share / Send'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showSnack('Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _changeLayerColor() async {
    final colors = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.cyan, Colors.teal,
      Colors.green, Colors.lightGreen, Colors.yellow, Colors.orange,
    ];
    Color picked = _hexToColor(_kml.layerColor);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Choose Layer Color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) {
            final isSelected = (color.value == picked.value);
            return GestureDetector(
              onTap: () {
                picked = color;
                Navigator.pop(ctx, true);
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 2.5,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)]
                      : [],
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
        ],
      ),
    );

    if (confirmed == true && _kml.id != null) {
      try {
        final hex =
            '#${picked.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
        await DbHelper().updateKmlColor(_kml.id!, hex);
        if (mounted) {
          setState(() => _kml = _kml.copyWith(layerColor: hex));
          _showSnack('Layer color updated');
        }
      } catch (e) {
        _showSnack('Failed to update color: $e', isError: true);
      }
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.errorColor : AppTheme.greenPrimary,
    ));
  }

  IconData _shapeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'marker':
        return Icons.place_outlined;
      case 'path':
        return Icons.timeline_outlined;
      case 'polygon':
        return Icons.hexagon_outlined;
      default:
        return Icons.shape_line_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final layerColor = _hexToColor(_kml.layerColor);
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: Text(_kml.filename, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share KML',
            onPressed: _shareKmlFile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── File Info ─────────────────────────────────────────────────
            _buildCard(
              title: 'File Information',
              icon: Icons.info_outline,
              child: Column(
                children: [
                  _infoRow('Filename', _kml.filename),
                  const Divider(height: 12, color: AppTheme.borderColor),
                  _infoRow('File Path', _kml.filepath, small: true),
                  const Divider(height: 12, color: AppTheme.borderColor),
                  _infoRow('Added',
                      _kml.createdAt.length >= 10 ? _kml.createdAt.substring(0, 10) : _kml.createdAt),
                  const Divider(height: 12, color: AppTheme.borderColor),
                  Row(children: [
                    const Icon(Icons.visibility_outlined,
                        color: AppTheme.textSecondary, size: 16),
                    const SizedBox(width: 8),
                    const Text('Visibility',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (_kml.isVisible ? AppTheme.greenPrimary : AppTheme.textMuted)
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _kml.isVisible ? 'Visible' : 'Hidden',
                        style: TextStyle(
                          color: _kml.isVisible ? AppTheme.greenAccent : AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ]),
                  const Divider(height: 12, color: AppTheme.borderColor),
                  Row(children: [
                    const Icon(Icons.palette_outlined,
                        color: AppTheme.textSecondary, size: 16),
                    const SizedBox(width: 8),
                    const Text('Layer Color',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    const Spacer(),
                    Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: layerColor, shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_kml.layerColor.toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Parsed Shapes ─────────────────────────────────────────────
            _buildCard(
              title: 'Parsed Shapes',
              icon: Icons.layers_outlined,
              child: _isParsing
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _parseError != null
                      ? Column(children: [
                          const Icon(Icons.error_outline,
                              color: AppTheme.errorColor, size: 32),
                          const SizedBox(height: 8),
                          Text('Parse error: $_parseError',
                              style: const TextStyle(
                                  color: AppTheme.errorColor, fontSize: 12)),
                          const SizedBox(height: 8),
                          TextButton(
                              onPressed: _parseKmlFile,
                              child: const Text('Retry')),
                        ])
                      : _shapes.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No shapes found in this file',
                                  style: TextStyle(color: AppTheme.textMuted)),
                            )
                          : Column(
                              children: _shapes.take(20).map((shape) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: Icon(_shapeIcon(shape.type),
                                      color: layerColor, size: 18),
                                  title: Text(shape.name,
                                      style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 13)),
                                  subtitle: Text(
                                    '${shape.type} · ${shape.coordinates.length} pts',
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary, fontSize: 11),
                                  ),
                                );
                              }).toList(),
                            ),
            ),
            const SizedBox(height: 12),

            // ── Layer Color ────────────────────────────────────────────────
            _buildCard(
              title: 'Layer Color',
              icon: Icons.color_lens_outlined,
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: layerColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _kml.layerColor.toUpperCase(),
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'monospace'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _changeLayerColor,
                    icon: const Icon(Icons.palette, size: 16),
                    label: const Text('Change'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Export Actions ─────────────────────────────────────────────
            _buildCard(
              title: 'Export & Share',
              icon: Icons.upload_outlined,
              child: Column(
                children: [
                  _actionTile(
                    icon: Icons.share,
                    label: 'Share KML File',
                    subtitle: 'Share the original KML file',
                    onTap: _shareKmlFile,
                  ),
                  const SizedBox(height: 8),
                  _actionTile(
                    icon: Icons.folder_zip_outlined,
                    label: 'Export as KMZ',
                    subtitle: 'Package KML as a compressed KMZ archive',
                    isLoading: _isExporting,
                    onTap: _exportAsKmz,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: AppTheme.greenAccent, size: 16),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ]),
          ),
          const Divider(height: 1, color: AppTheme.borderColor),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool small = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: small ? 11 : 12,
                  fontWeight: FontWeight.w500),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppTheme.greenPrimary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.greenAccent),
                      ),
                    )
                  : Icon(icon, color: AppTheme.greenAccent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textMuted, size: 16),
          ],
        ),
      ),
    );
  }
}
