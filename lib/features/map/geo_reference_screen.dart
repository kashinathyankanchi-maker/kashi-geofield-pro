import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/theme.dart';
import '../../core/utils/kml_engine.dart';

/// Result of geo-referencing a PDF map image
class GeoReferencedImage {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final LatLng topLeft;
  final LatLng bottomRight;
  final String sourceName;

  GeoReferencedImage({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.topLeft,
    required this.bottomRight,
    required this.sourceName,
  });
}

/// Ground Control Point — a known pixel↔geo mapping
class _GCP {
  final Offset pixel;
  final LatLng geo;
  _GCP({required this.pixel, required this.geo});
}

/// Screen that lets user geo-reference a PDF image by placing control points
/// with Zoomable PDF, Satellite Map Overlay, and Opacity Controls.
class GeoReferenceScreen extends StatefulWidget {
  final String pdfPath;
  final String fileName;

  const GeoReferenceScreen({
    super.key,
    required this.pdfPath,
    required this.fileName,
  });

  @override
  State<GeoReferenceScreen> createState() => _GeoReferenceScreenState();
}

class _GeoReferenceScreenState extends State<GeoReferenceScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _imageBytes;
  int _imgWidth = 0;
  int _imgHeight = 0;
  bool _loading = true;
  String? _error;

  final List<_GCP> _gcps = [];
  bool _addingGcp = false;
  Offset? _tappedPixel;

  double _pdfOpacity = 0.65;
  int _activeViewIndex = 0; // 0 = PDF View, 1 = Satellite Overlay

  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  late final fmap.MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = fmap.MapController();
    _renderPdf();
  }

  Future<void> _renderPdf() async {
    try {
      final doc = await PdfDocument.openFile(widget.pdfPath);
      final page = await doc.getPage(1);
      final pageImage = await page.render(
        width: page.width * 3,
        height: page.height * 3,
        format: PdfPageImageFormat.png,
      );
      await page.close();
      await doc.close();

      if (pageImage != null && pageImage.bytes.isNotEmpty) {
        final uiImage = await decodeImageFromList(pageImage.bytes);
        if (mounted) {
          setState(() {
            _imageBytes = pageImage.bytes;
            _imgWidth = uiImage.width;
            _imgHeight = uiImage.height;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to render PDF: $e';
          _loading = false;
        });
      }
    }
  }

  void _onImageTap(TapDownDetails details, BoxConstraints constraints) {
    if (!_addingGcp || _imageBytes == null) return;

    final scaleX = _imgWidth / constraints.maxWidth;
    final scaleY = _imgHeight / constraints.maxHeight;
    final px = details.localPosition.dx * scaleX;
    final py = details.localPosition.dy * scaleY;

    setState(() {
      _tappedPixel = Offset(px, py);
    });

    _showCoordinateDialog();
  }

  void _showCoordinateDialog() async {
    _latCtrl.clear();
    _lngCtrl.clear();

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _latCtrl.text = pos.latitude.toStringAsFixed(6);
      _lngCtrl.text = pos.longitude.toStringAsFixed(6);
    } catch (_) {}

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Enter Real-World Coordinates',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Point ${_gcps.length + 1}: Enter GPS for tapped position',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _latCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Latitude',
                prefixIcon: const Icon(Icons.north, size: 18),
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _lngCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Longitude',
                prefixIcon: const Icon(Icons.east, size: 18),
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.greenAccent,
                side: const BorderSide(color: AppTheme.greenAccent),
              ),
              onPressed: () async {
                final picked = await _pickOnSatelliteMap();
                if (picked != null) {
                  _latCtrl.text = picked.latitude.toStringAsFixed(6);
                  _lngCtrl.text = picked.longitude.toStringAsFixed(6);
                }
              },
              icon: const Icon(Icons.satellite_alt_rounded, size: 18),
              label: const Text('Pick on Satellite Map'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.greenPrimary),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add Point')),
        ],
      ),
    );

    if (confirmed == true && _tappedPixel != null) {
      final lat = double.tryParse(_latCtrl.text.trim());
      final lng = double.tryParse(_lngCtrl.text.trim());
      if (lat != null && lng != null) {
        setState(() {
          _gcps.add(_GCP(pixel: _tappedPixel!, geo: LatLng(lat, lng)));
          _tappedPixel = null;
          _addingGcp = false;
        });
      }
    } else {
      setState(() {
        _tappedPixel = null;
      });
    }
  }

  Future<LatLng?> _pickOnSatelliteMap() async {
    final ref = _computeGeoReference();
    LatLng? selected;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        contentPadding: EdgeInsets.zero,
        title: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Tap Landmark on Satellite Map',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: Stack(
            children: [
              fmap.FlutterMap(
                options: fmap.MapOptions(
                  initialCenter: _gcps.isNotEmpty
                      ? _gcps.last.geo
                      : const LatLng(14.96, 74.71),
                  initialZoom: 14,
                  onTap: (tapPos, point) {
                    selected = point;
                    Navigator.pop(ctx);
                  },
                ),
                children: [
                  fmap.TileLayer(
                    urlTemplate: 'https://mt0.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                    tileProvider: fmap.NetworkTileProvider(),
                    userAgentPackageName: 'com.kashi.kashi_geofield_pro',
                  ),
                  if (_imageBytes != null)
                    fmap.OverlayImageLayer(
                      overlayImages: [
                        if (ref != null)
                          fmap.OverlayImage(
                            bounds: fmap.LatLngBounds(ref.bottomRight, ref.topLeft),
                            imageProvider: MemoryImage(_imageBytes!),
                            opacity: _pdfOpacity,
                          )
                        else if (_gcps.isNotEmpty)
                          fmap.OverlayImage(
                            bounds: fmap.LatLngBounds(
                              LatLng(_gcps.first.geo.latitude - 0.005, _gcps.first.geo.longitude - 0.005),
                              LatLng(_gcps.first.geo.latitude + 0.005, _gcps.first.geo.longitude + 0.005),
                            ),
                            imageProvider: MemoryImage(_imageBytes!),
                            opacity: _pdfOpacity,
                          )
                        else
                          fmap.OverlayImage(
                            bounds: fmap.LatLngBounds(
                              const LatLng(14.96 - 0.005, 74.71 - 0.005),
                              const LatLng(14.96 + 0.005, 74.71 + 0.005),
                            ),
                            imageProvider: MemoryImage(_imageBytes!),
                            opacity: _pdfOpacity,
                          ),
                      ],
                    ),
                  fmap.MarkerLayer(
                    markers: _gcps
                        .map((g) => fmap.Marker(
                              point: g.geo,
                              child: const Icon(Icons.location_on,
                                  color: Colors.redAccent, size: 24),
                            ))
                        .toList(),
                  ),
                ],
              ),
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  color: const Color(0xB3000000),
                  child: const Text('Tap any landmark on satellite map to select GPS',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return selected;
  }

  GeoReferencedImage? _computeGeoReference() {
    if (_gcps.length < 2 || _imageBytes == null) return null;

    double minPxX = double.infinity, maxPxX = -double.infinity;
    double minPxY = double.infinity, maxPxY = -double.infinity;
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;

    for (final gcp in _gcps) {
      if (gcp.pixel.dx < minPxX) minPxX = gcp.pixel.dx;
      if (gcp.pixel.dx > maxPxX) maxPxX = gcp.pixel.dx;
      if (gcp.pixel.dy < minPxY) minPxY = gcp.pixel.dy;
      if (gcp.pixel.dy > maxPxY) maxPxY = gcp.pixel.dy;
      if (gcp.geo.latitude < minLat) minLat = gcp.geo.latitude;
      if (gcp.geo.latitude > maxLat) maxLat = gcp.geo.latitude;
      if (gcp.geo.longitude < minLng) minLng = gcp.geo.longitude;
      if (gcp.geo.longitude > maxLng) maxLng = gcp.geo.longitude;
    }

    final pxRangeX = maxPxX - minPxX;
    final pxRangeY = maxPxY - minPxY;
    if (pxRangeX <= 0 || pxRangeY <= 0) return null;

    final lngPerPx = (maxLng - minLng) / pxRangeX;
    final latPerPx = (maxLat - minLat) / pxRangeY;

    final topLeftLat = maxLat + (minPxY) * latPerPx;
    final topLeftLng = minLng - (minPxX) * lngPerPx;
    final bottomRightLat = minLat - (_imgHeight - maxPxY) * latPerPx;
    final bottomRightLng = maxLng + (_imgWidth - maxPxX) * lngPerPx;

    final n = math.max(topLeftLat, bottomRightLat);
    final s = math.min(topLeftLat, bottomRightLat);
    final e = math.max(topLeftLng, bottomRightLng);
    final w = math.min(topLeftLng, bottomRightLng);

    return GeoReferencedImage(
      imageBytes: _imageBytes!,
      width: _imgWidth,
      height: _imgHeight,
      topLeft: LatLng(n, w),
      bottomRight: LatLng(s, e),
      sourceName: widget.fileName,
    );
  }

  Future<void> _exportAsKmz() async {
    final ref = _computeGeoReference();
    if (ref == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Need at least 2 well-separated points')),
        );
      }
      return;
    }

    try {
      final imgName = widget.fileName
          .replaceAll('.pdf', '.png')
          .replaceAll('.PDF', '.png');
      final kmzBytes = KmlEngine.generateGeoReferencedKmz(
        imageBytes: ref.imageBytes.toList(),
        imageFileName: imgName,
        name: widget.fileName.replaceAll(RegExp(r'\.[^.]+$'), ''),
        north: ref.topLeft.latitude,
        south: ref.bottomRight.latitude,
        east: ref.bottomRight.longitude,
        west: ref.topLeft.longitude,
      );

      final dir = await getTemporaryDirectory();
      final safeName = widget.fileName.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final kmzFile = File('${dir.path}/$safeName.kmz');
      await kmzFile.writeAsBytes(kmzBytes);

      await Share.shareXFiles(
        [XFile(kmzFile.path, mimeType: 'application/vnd.google-earth.kmz')],
        subject: '${widget.fileName} - Geo-Referenced KMZ',
        text: 'Geo-referenced KMZ file for Google Earth',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('KMZ file created for Google Earth!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = _computeGeoReference();

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: Text(widget.fileName, style: const TextStyle(fontSize: 14)),
        backgroundColor: AppTheme.bgSecondary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf, size: 15),
                      SizedBox(width: 4),
                      Text('PDF Image', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  selected: _activeViewIndex == 0,
                  selectedColor: AppTheme.greenPrimary,
                  backgroundColor: AppTheme.bgSurface,
                  labelStyle: TextStyle(
                    color: _activeViewIndex == 0
                        ? Colors.white
                        : AppTheme.textSecondary,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _activeViewIndex = 0);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.satellite_alt, size: 15),
                      SizedBox(width: 4),
                      Text('Satellite Map', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  selected: _activeViewIndex == 1,
                  selectedColor: AppTheme.greenPrimary,
                  backgroundColor: AppTheme.bgSurface,
                  labelStyle: TextStyle(
                    color: _activeViewIndex == 1
                        ? Colors.white
                        : AppTheme.textSecondary,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _activeViewIndex = 1);
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_gcps.length >= 2) ...[
            TextButton.icon(
              onPressed: _exportAsKmz,
              icon:
                  const Icon(Icons.save_alt, color: Colors.orangeAccent, size: 20),
              label: const Text('KMZ',
                  style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            TextButton.icon(
              onPressed: () {
                final result = _computeGeoReference();
                if (result != null) {
                  Navigator.pop(context, result);
                }
              },
              icon:
                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
              label: const Text('Apply',
                  style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF7B1FA2)],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _gcps.isEmpty
                        ? 'Pinch to Zoom PDF. Tap "Add Point" then tap on PDF to mark GCPs.'
                        : '${_gcps.length} control point(s) placed. Check alignment on Satellite map.',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_gcps.length} GCPs',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Main View (PDF Image or Live Satellite Overlay)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: AppTheme.errorColor)))
                    : IndexedStack(
                        index: _activeViewIndex,
                        children: [
                          // 0: Zoomable PDF Image View
                          InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 20.0,
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: _imgWidth > 0 && _imgHeight > 0
                                    ? _imgWidth / _imgHeight
                                    : 1.0,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return GestureDetector(
                                      onTapDown: (details) =>
                                          _onImageTap(details, constraints),
                                      child: Stack(
                                        children: [
                                          Image.memory(
                                            _imageBytes!,
                                            width: constraints.maxWidth,
                                            height: constraints.maxHeight,
                                            fit: BoxFit.fill,
                                          ),
                                          ..._gcps.asMap().entries.map((entry) {
                                            final idx = entry.key;
                                            final gcp = entry.value;
                                            final sx = constraints.maxWidth /
                                                (_imgWidth > 0 ? _imgWidth : 1);
                                            final sy = constraints.maxHeight /
                                                (_imgHeight > 0 ? _imgHeight : 1);
                                            return Positioned(
                                              left: gcp.pixel.dx * sx - 12,
                                              top: gcp.pixel.dy * sy - 24,
                                              child: Column(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 4,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red,
                                                      borderRadius:
                                                          BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'P${idx + 1}',
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ),
                                                  const Icon(Icons.push_pin,
                                                      color: Colors.red,
                                                      size: 20),
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),

                          // 1: Satellite Map Layer with PDF Overlaid & Opacity
                          fmap.FlutterMap(
                            mapController: _mapController,
                            options: fmap.MapOptions(
                              initialCenter: ref != null
                                  ? LatLng(
                                      (ref.topLeft.latitude +
                                              ref.bottomRight.latitude) /
                                          2,
                                      (ref.topLeft.longitude +
                                              ref.bottomRight.longitude) /
                                          2,
                                    )
                                  : (_gcps.isNotEmpty
                                      ? _gcps.first.geo
                                      : const LatLng(14.96, 74.71)),
                              initialZoom: ref != null ? 15 : 13,
                            ),
                            children: [
                              fmap.TileLayer(
                                urlTemplate:
                                    'https://mt0.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                                tileProvider: fmap.NetworkTileProvider(),
                                userAgentPackageName:
                                    'com.kashi.kashi_geofield_pro',
                              ),
                              if (_imageBytes != null)
                                fmap.OverlayImageLayer(
                                  overlayImages: [
                                    if (ref != null)
                                      fmap.OverlayImage(
                                        bounds: fmap.LatLngBounds(
                                            ref.bottomRight, ref.topLeft),
                                        imageProvider: MemoryImage(_imageBytes!),
                                        opacity: _pdfOpacity,
                                      )
                                    else if (_gcps.isNotEmpty)
                                      fmap.OverlayImage(
                                        bounds: fmap.LatLngBounds(
                                          LatLng(_gcps.first.geo.latitude - 0.005,
                                              _gcps.first.geo.longitude - 0.005),
                                          LatLng(_gcps.first.geo.latitude + 0.005,
                                              _gcps.first.geo.longitude + 0.005),
                                        ),
                                        imageProvider: MemoryImage(_imageBytes!),
                                        opacity: _pdfOpacity,
                                      )
                                    else
                                      fmap.OverlayImage(
                                        bounds: fmap.LatLngBounds(
                                          const LatLng(14.96 - 0.005, 74.71 - 0.005),
                                          const LatLng(14.96 + 0.005, 74.71 + 0.005),
                                        ),
                                        imageProvider: MemoryImage(_imageBytes!),
                                        opacity: _pdfOpacity,
                                      ),
                                  ],
                                ),
                              fmap.MarkerLayer(
                                markers: _gcps
                                    .asMap()
                                    .entries
                                    .map(
                                      (e) => fmap.Marker(
                                        point: e.value.geo,
                                        child: Column(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(2),
                                              color: Colors.red,
                                              child: Text('P${e.key + 1}',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 8)),
                                            ),
                                            const Icon(Icons.location_on,
                                                color: Colors.redAccent,
                                                size: 22),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ],
                      ),
          ),

          // Opacity Slider Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: AppTheme.bgSecondary,
            child: Row(
              children: [
                const Icon(Icons.opacity, color: AppTheme.greenAccent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'PDF Opacity: ${(_pdfOpacity * 100).round()}%',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: Slider(
                    value: _pdfOpacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    activeColor: AppTheme.greenAccent,
                    inactiveColor: AppTheme.bgSurface,
                    onChanged: (val) {
                      setState(() {
                        _pdfOpacity = val;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Bottom Controls
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(top: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _addingGcp = !_addingGcp;
                      _activeViewIndex = 0; // Switch to PDF image view to tap
                    }),
                    icon: Icon(
                      _addingGcp ? Icons.touch_app : Icons.add_location_alt,
                      size: 18,
                    ),
                    label: Text(_addingGcp ? 'Tap on PDF...' : 'Add Point'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _addingGcp
                          ? const Color(0xFFFF6F00)
                          : AppTheme.greenPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_gcps.isNotEmpty)
                  IconButton(
                    onPressed: () => setState(() => _gcps.removeLast()),
                    icon: const Icon(Icons.undo, color: AppTheme.textSecondary),
                    tooltip: 'Remove Last Point',
                  ),
              ],
            ),
          ),

          // GCP list preview
          if (_gcps.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              color: AppTheme.bgSurface,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _gcps.length,
                itemBuilder: (_, i) {
                  final gcp = _gcps[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.red,
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9)),
                    ),
                    title: Text(
                      'Lat: ${gcp.geo.latitude.toStringAsFixed(6)}, Lng: ${gcp.geo.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 11),
                    ),
                    subtitle: Text(
                      'Pixel: (${gcp.pixel.dx.round()}, ${gcp.pixel.dy.round()})',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }
}
