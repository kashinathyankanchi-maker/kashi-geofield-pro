import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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

class _GeoReferenceScreenState extends State<GeoReferenceScreen> {
  Uint8List? _imageBytes;
  int _imgWidth = 0;
  int _imgHeight = 0;
  bool _loading = true;
  String? _error;

  final List<_GCP> _gcps = [];
  bool _addingGcp = false;
  Offset? _tappedPixel;

  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
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
        // Decode to get dimensions
        final uiImage = await decodeImageFromList(pageImage.bytes);
        setState(() {
          _imageBytes = pageImage.bytes;
          _imgWidth = uiImage.width;
          _imgHeight = uiImage.height;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to render PDF: $e';
        _loading = false;
      });
    }
  }

  void _onImageTap(TapDownDetails details, BoxConstraints constraints) {
    if (!_addingGcp || _imageBytes == null) return;

    // Convert tap position to image pixel coordinates
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

    // Try to get current GPS as default
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
              'Point ${_gcps.length + 1}: Tap location on PDF',
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
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
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

  GeoReferencedImage? _computeGeoReference() {
    if (_gcps.length < 2 || _imageBytes == null) return null;

    // Find bounding box from GCPs — use min/max pixel positions to extrapolate
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

    // Calculate scale (degrees per pixel)
    final pxRangeX = maxPxX - minPxX;
    final pxRangeY = maxPxY - minPxY;
    if (pxRangeX == 0 || pxRangeY == 0) return null;

    final lngPerPx = (maxLng - minLng) / pxRangeX;
    final latPerPx = (maxLat - minLat) / pxRangeY;

    // Extrapolate to full image corners
    final topLeftLat = maxLat + (minPxY) * latPerPx; // top of image
    final topLeftLng = minLng - (minPxX) * lngPerPx; // left of image
    final bottomRightLat = minLat - (_imgHeight - maxPxY) * latPerPx;
    final bottomRightLng = maxLng + (_imgWidth - maxPxX) * lngPerPx;

    return GeoReferencedImage(
      imageBytes: _imageBytes!,
      width: _imgWidth,
      height: _imgHeight,
      topLeft: LatLng(topLeftLat, topLeftLng),
      bottomRight: LatLng(bottomRightLat, bottomRightLng),
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
      // Generate KMZ with GroundOverlay
      final imgName = widget.fileName.replaceAll('.pdf', '.png').replaceAll('.PDF', '.png');
      final kmzBytes = KmlEngine.generateGeoReferencedKmz(
        imageBytes: ref.imageBytes.toList(),
        imageFileName: imgName,
        name: widget.fileName.replaceAll(RegExp(r'\.[^.]+$'), ''),
        north: ref.topLeft.latitude,
        south: ref.bottomRight.latitude,
        east: ref.bottomRight.longitude,
        west: ref.topLeft.longitude,
      );

      // Save to temp and share
      final dir = await getTemporaryDirectory();
      final safeName = widget.fileName.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final kmzFile = File('${dir.path}/${safeName}.kmz');
      await kmzFile.writeAsBytes(kmzBytes);

      await Share.shareXFiles(
        [XFile(kmzFile.path, mimeType: 'application/vnd.google-earth.kmz')],
        subject: '${widget.fileName} - Geo-Referenced KMZ',
        text: 'Geo-referenced KMZ file',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KMZ file exported successfully!')),
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
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: Text(widget.fileName, style: const TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.bgSecondary,
        actions: [
          if (_gcps.length >= 2) ...[
            // Export as KMZ file
            TextButton.icon(
              onPressed: _exportAsKmz,
              icon: const Icon(Icons.save_alt, color: Colors.orangeAccent, size: 20),
              label: const Text('KMZ',
                  style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            // Apply to map overlay
            TextButton.icon(
              onPressed: () {
                final result = _computeGeoReference();
                if (result != null) {
                  Navigator.pop(context, result);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Need at least 2 well-separated points')),
                  );
                }
              },
              icon: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
              label: const Text('Apply',
                  style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF7B1FA2)],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _gcps.isEmpty
                        ? 'Tap "Add Point" then tap on the PDF image to place a control point'
                        : '${_gcps.length} control point(s) placed. Need at least 2.',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_gcps.length} GCPs',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // PDF image
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: AppTheme.errorColor)))
                    : LayoutBuilder(
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
                                  fit: BoxFit.contain,
                                ),
                                // Draw GCP markers
                                ..._gcps.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final gcp = entry.value;
                                  final sx = constraints.maxWidth / _imgWidth;
                                  final sy = constraints.maxHeight / _imgHeight;
                                  return Positioned(
                                    left: gcp.pixel.dx * sx - 12,
                                    top: gcp.pixel.dy * sy - 24,
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 2),
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
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const Icon(Icons.push_pin,
                                            color: Colors.red, size: 20),
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

          // Bottom controls
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(top: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => _addingGcp = !_addingGcp),
                    icon: Icon(
                      _addingGcp ? Icons.touch_app : Icons.add_location_alt,
                      size: 18,
                    ),
                    label: Text(_addingGcp ? 'Tap on Image...' : 'Add Point'),
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

          // GCP list
          if (_gcps.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              color: AppTheme.bgSurface,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _gcps.length,
                itemBuilder: (_, i) {
                  final gcp = _gcps[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.red,
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
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
