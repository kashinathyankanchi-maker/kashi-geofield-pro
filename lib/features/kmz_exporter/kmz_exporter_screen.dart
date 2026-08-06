import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/theme.dart';
import '../../core/utils/storage_helper.dart';
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
  bool _isGeoTiff = false;
  bool _isParsing = false;
  bool _isExporting = false;
  String? _exportedPath;
  String? _error;

  GeoBounds? _bounds;

  // Controllers for manual coordinate entry
  final _northCtrl = TextEditingController();
  final _southCtrl = TextEditingController();
  final _eastCtrl = TextEditingController();
  final _westCtrl = TextEditingController();
  final _layerNameCtrl = TextEditingController(text: 'My Overlay');

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _northCtrl.dispose();
    _southCtrl.dispose();
    _eastCtrl.dispose();
    _westCtrl.dispose();
    _layerNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _exportedPath = null;
      _isGeoTiff = false;
      _bounds = null;
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

    // Try to parse as GeoTIFF
    final ext = name.toLowerCase();
    if (ext.endsWith('.tif') || ext.endsWith('.tiff')) {
      try {
        final bytes = await file.readAsBytes();
        final parser = GeoTiffParser(bytes);
        final bounds = parser.parse();

        if (bounds != null) {
          setState(() {
            _isGeoTiff = true;
            _bounds = bounds;
            _northCtrl.text = bounds.north.toStringAsFixed(8);
            _southCtrl.text = bounds.south.toStringAsFixed(8);
            _eastCtrl.text = bounds.east.toStringAsFixed(8);
            _westCtrl.text = bounds.west.toStringAsFixed(8);
          });
        } else {
          setState(() {
            _isGeoTiff = false;
            _error = 'This TIFF file does not contain geographic coordinate data (not a GeoTIFF). Please enter coordinates manually.';
          });
        }
      } catch (e) {
        setState(() {
          _error = 'Failed to read TIFF: $e';
        });
      }
    }

    setState(() => _isParsing = false);
  }

  void _updateBoundsFromFields() {
    final n = double.tryParse(_northCtrl.text);
    final s = double.tryParse(_southCtrl.text);
    final e = double.tryParse(_eastCtrl.text);
    final w = double.tryParse(_westCtrl.text);
    if (n != null && s != null && e != null && w != null && n > s && e > w) {
      setState(() {
        _bounds = GeoBounds(north: n, south: s, east: e, west: w);
      });
    }
  }

  Future<void> _exportKmz() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) return;

    _updateBoundsFromFields();
    if (_bounds == null) {
      setState(() => _error = 'Please enter valid coordinates.');
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
        bounds: _bounds!,
        layerName: _layerNameCtrl.text.trim(),
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
            duration: const Duration(seconds: 3),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Image / TIFF → KMZ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Step 1: Pick File ──────────────────────────────────────────
              _buildSectionHeader('Step 1: Select Image File', Icons.folder_open_rounded),
              const SizedBox(height: 10),
              _buildPickerCard(),
              const SizedBox(height: 20),

              // ── Step 2: Coordinates ────────────────────────────────────────
              _buildSectionHeader('Step 2: Geographic Coordinates', Icons.place_rounded),
              const SizedBox(height: 4),
              if (_isGeoTiff)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade900.withValues(alpha:0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade700),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 8),
                      const Text('GeoTIFF detected — coordinates auto-filled!',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                    ],
                  ),
                )
              else if (_selectedFile != null && !_isParsing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade900.withValues(alpha:0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade700),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Colors.orangeAccent, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Regular image — enter coordinates manually',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                    ],
                  ),
                ),

              const SizedBox(height: 6),
              _buildCoordinateFields(),
              const SizedBox(height: 20),

              // ── Map Preview ────────────────────────────────────────────────
              if (_bounds != null) ...[
                _buildSectionHeader('Preview', Icons.map_rounded),
                const SizedBox(height: 10),
                _buildMapPreview(),
                const SizedBox(height: 20),
              ],

              // ── Step 3: Layer Name ─────────────────────────────────────────
              _buildSectionHeader('Step 3: Layer Name', Icons.label_rounded),
              const SizedBox(height: 10),
              TextFormField(
                controller: _layerNameCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Enter name for the KMZ overlay...',
                  hintStyle: TextStyle(color: AppTheme.textMuted),
                  filled: true,
                  fillColor: AppTheme.bgCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.greenPrimary, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.edit_rounded, color: AppTheme.textMuted),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 24),

              // ── Error ──────────────────────────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha:0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade700),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                    ],
                  ),
                ),

              // ── Export Button ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (_selectedFile == null || _isExporting || _isParsing) ? null : _exportKmz,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    disabledBackgroundColor: Colors.grey.shade800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isExporting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.download_rounded, color: Colors.white),
                  label: Text(
                    _isExporting ? 'Exporting...' : 'Export KMZ File',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // ── Success ────────────────────────────────────────────────────
              if (_exportedPath != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade900.withValues(alpha:0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade600),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                          SizedBox(width: 8),
                          Text('KMZ Exported!', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_exportedPath!, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Share.shareXFiles([XFile(_exportedPath!)]),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.green.shade500),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.share_rounded, color: Colors.greenAccent, size: 18),
                              label: const Text('Share', style: TextStyle(color: Colors.greenAccent)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.greenAccent, size: 18),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildPickerCard() {
    return GestureDetector(
      onTap: _isParsing ? null : _pickFile,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedFile != null ? AppTheme.greenPrimary : AppTheme.borderColor,
            width: _selectedFile != null ? 2 : 1,
          ),
        ),
        child: _isParsing
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Reading file...', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              )
            : _selectedFile == null
                ? Column(
                    children: [
                      Icon(Icons.add_photo_alternate_rounded, size: 48, color: AppTheme.textMuted),
                      const SizedBox(height: 8),
                      const Text('Tap to select a file', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Supports: GeoTIFF (.tif), JPG, PNG', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.greenPrimary.withValues(alpha:0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.image_rounded, color: AppTheme.greenAccent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_fileName, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('Tap to change file', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.refresh_rounded, color: AppTheme.textMuted),
                    ],
                  ),
      ),
    );
  }

  Widget _buildCoordinateFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildCoordField('North', _northCtrl, 'e.g. 14.95')),
            const SizedBox(width: 10),
            Expanded(child: _buildCoordField('South', _southCtrl, 'e.g. 14.85')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildCoordField('East', _eastCtrl, 'e.g. 74.67')),
            const SizedBox(width: 10),
            Expanded(child: _buildCoordField('West', _westCtrl, 'e.g. 74.57')),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _updateBoundsFromFields,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.borderColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16, color: AppTheme.greenAccent),
            label: const Text('Update Preview', style: TextStyle(color: AppTheme.greenAccent, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildCoordField(String label, TextEditingController ctrl, String hint) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      onChanged: (_) {},
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 11),
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.bgCard,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.greenPrimary, width: 2)),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (double.tryParse(v.trim()) == null) return 'Invalid';
        return null;
      },
    );
  }

  Widget _buildMapPreview() {
    final bounds = _bounds!;
    final center = LatLng(bounds.centerLat, bounds.centerLon);

    // Calculate zoom based on span size
    double zoom = 12.0;
    final maxSpan = bounds.latSpan > bounds.lonSpan ? bounds.latSpan : bounds.lonSpan;
    if (maxSpan > 10) { zoom = 5; }
    else if (maxSpan > 5) { zoom = 7; }
    else if (maxSpan > 1) { zoom = 9; }
    else if (maxSpan > 0.1) { zoom = 12; }
    else { zoom = 15; }

    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      clipBehavior: Clip.hardEdge,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: zoom,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
            userAgentPackageName: 'com.kashi.geofieldpro',
          ),
          PolygonLayer(
            polygons: [
              Polygon(
                points: [
                  LatLng(bounds.north, bounds.west),
                  LatLng(bounds.north, bounds.east),
                  LatLng(bounds.south, bounds.east),
                  LatLng(bounds.south, bounds.west),
                ],
                color: Colors.blue.withValues(alpha:0.25),
                borderColor: Colors.blueAccent,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
