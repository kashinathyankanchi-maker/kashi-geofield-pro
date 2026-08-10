import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/theme.dart';
import '../../core/utils/storage_helper.dart';
import '../map/geo_reference_screen.dart';
import 'geotiff_parser.dart';
import 'kmz_builder.dart';

class KmzExporterScreen extends StatefulWidget {
  const KmzExporterScreen({super.key});

  @override
  State<KmzExporterScreen> createState() => _KmzExporterScreenState();
}

class _KmzExporterScreenState extends State<KmzExporterScreen> {
  File? _selectedFile;
  String _fileName = '';
  bool _isParsing = false;
  bool _isExporting = false;
  String? _exportedPath;
  String? _error;
  GeoBounds? _autoBounds; // Only set when GeoTIFF auto-detected

  final _layerNameCtrl = TextEditingController(text: 'My Overlay');

  @override
  void dispose() {
    _layerNameCtrl.dispose();
    super.dispose();
  }

  // ── Step 1: Pick File ─────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _exportedPath = null;
      _autoBounds = null;
      _selectedFile = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tif', 'tiff', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);
    final name = result.files.single.name;

    setState(() {
      _selectedFile = file;
      _fileName = name;
      _layerNameCtrl.text = name.replaceAll(RegExp(r'\.[^.]+$'), '');
      _isParsing = true;
    });

    // ── GeoTIFF: try to auto-extract bounds ──────────────────────────────────
    final ext = name.toLowerCase();
    if (ext.endsWith('.tif') || ext.endsWith('.tiff')) {
      try {
        final bytes = await file.readAsBytes();
        final parser = GeoTiffParser(bytes);
        final bounds = parser.parse();

        if (bounds != null) {
          // GeoTIFF with embedded coords — can export immediately
          setState(() {
            _autoBounds = bounds;
            _isParsing = false;
          });
          return; // skip visual alignment
        }
      } catch (_) {}
    }

    setState(() => _isParsing = false);

    // ── Regular image / non-GeoTIFF: open visual GeoReference screen ─────────
    if (!mounted) return;
    final geoResult = await Navigator.push<GeoReferencedImage>(
      context,
      MaterialPageRoute(
        builder: (_) => GeoReferenceScreen(
          filePath: file.path,
          fileName: name,
        ),
      ),
    );

    if (geoResult == null) {
      // User cancelled visual alignment
      setState(() {
        _selectedFile = null;
        _fileName = '';
      });
      return;
    }

    // Convert GeoReferencedImage corners → GeoBounds
    final north = geoResult.topLeft.latitude;
    final west  = geoResult.topLeft.longitude;
    final south = geoResult.bottomRight.latitude;
    final east  = geoResult.bottomRight.longitude;

    setState(() {
      _autoBounds = GeoBounds(north: north, south: south, east: east, west: west);
    });

    // Auto-export straight away after alignment
    await _exportKmz();
  }

  // ── Step 2: Export KMZ ───────────────────────────────────────────────────

  Future<void> _exportKmz() async {
    if (_selectedFile == null) return;

    final bounds = _autoBounds;
    if (bounds == null) {
      setState(() => _error = 'No geographic bounds available. Please pick a file first.');
      return;
    }

    setState(() {
      _isExporting = true;
      _error = null;
      _exportedPath = null;
    });

    try {
      final baseDir = await StorageHelper.getAppStorageDirectory();
      final kmzDir = '$baseDir/KMZ Exports';

      final outputPath = await KmzBuilder.build(
        imageFile: _selectedFile!,
        bounds: bounds,
        layerName: _layerNameCtrl.text.trim().isEmpty
            ? _fileName.replaceAll(RegExp(r'\.[^.]+$'), '')
            : _layerNameCtrl.text.trim(),
        outputDir: kmzDir,
      );

      setState(() {
        _exportedPath = outputPath;
        _isExporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ KMZ exported successfully!'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(outputPath)]),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isExporting = false;
        _error = 'Export failed: $e';
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Image / TIFF → KMZ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isParsing || _isExporting
          ? _buildLoading()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── How it works card ──────────────────────────────────
                  _buildInfoCard(),
                  const SizedBox(height: 20),

                  // ── Layer name ─────────────────────────────────────────
                  _buildSectionHeader('Layer Name', Icons.label_rounded),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _layerNameCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Name shown in Google Earth',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.bgCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.label_outline,
                          color: AppTheme.greenAccent),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Pick & Align ───────────────────────────────────────
                  _buildSectionHeader(
                      'Pick Image / TIFF', Icons.folder_open_rounded),
                  const SizedBox(height: 10),

                  if (_selectedFile == null) _buildPickerCard(),

                  if (_selectedFile != null && _autoBounds != null)
                    _buildReadyCard(),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorCard(),
                  ],

                  if (_exportedPath != null) ...[
                    const SizedBox(height: 16),
                    _buildSuccessCard(),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.greenAccent),
          const SizedBox(height: 16),
          Text(
            _isParsing ? 'Analysing file...' : 'Building KMZ...',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.greenAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.greenAccent, size: 18),
              SizedBox(width: 8),
              Text('How it works',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• GeoTIFF → bounds auto-detected → KMZ exported instantly\n'
            '• Regular image/TIFF → opens satellite map for visual alignment\n'
            '  (tap 2 corners on the satellite map to set position)',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.greenAccent, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
      ],
    );
  }

  Widget _buildPickerCard() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppTheme.greenAccent.withValues(alpha: 0.4),
              style: BorderStyle.solid),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_rounded,
                color: AppTheme.greenAccent, size: 40),
            SizedBox(height: 10),
            Text('Tap to pick image / TIFF',
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            SizedBox(height: 4),
            Text('JPG · PNG · TIF · TIFF',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyCard() {
    final b = _autoBounds!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppTheme.greenAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppTheme.greenAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _fileName,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'N ${b.north.toStringAsFixed(6)}  S ${b.south.toStringAsFixed(6)}\n'
            'E ${b.east.toStringAsFixed(6)}  W ${b.west.toStringAsFixed(6)}',
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isExporting ? null : _exportKmz,
                  icon: const Icon(Icons.file_download_rounded, size: 18),
                  label: const Text('Export KMZ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Change'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.borderBright),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: AppTheme.errorColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!,
                style: const TextStyle(
                    color: AppTheme.errorColor, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.greenAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.greenAccent, size: 18),
              SizedBox(width: 8),
              Text('KMZ Exported!',
                  style: TextStyle(
                      color: AppTheme.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _exportedPath!.split('/').last,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Share.shareXFiles([XFile(_exportedPath!)]),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Share KMZ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
                label: const Text('New'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.borderBright),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
