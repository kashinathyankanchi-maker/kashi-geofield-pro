import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../shared/theme.dart';
import '../../core/database/db_helper.dart';
import '../../core/models/village_model.dart';
import '../../core/models/polygon_model.dart';
import '../../core/utils/geo_calculator.dart';
import 'map_controller.dart';
import 'widgets/draw_toolbar.dart';
import 'widgets/layer_panel.dart';
import 'widgets/shape_detail_sheet.dart';
import 'package:screenshot/screenshot.dart';
import '../offline_maps/offline_maps_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  late final fmap.MapController _flutterMapController;
  final ScreenshotController _screenshotController = ScreenshotController();
  final TextEditingController _searchController = TextEditingController();
  
  bool _showLayerPanel = false;
  bool _isSearching = false;
  List<VillageModel> _villages = [];
  List<PolygonModel> _savedPolygons = [];
  bool _loadingLocation = false;
  
  // Draggable toolbar state
  Offset _toolbarOffset = const Offset(0, 120);
  bool _isToolbarOffsetInitialized = false;

  @override
  void initState() {
    super.initState();
    _flutterMapController = fmap.MapController();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DbHelper();
    final villages = await db.getAllVillages();
    final polygons = await db.getAllPolygons();
    setState(() {
      _villages = villages;
      _savedPolygons = polygons;
    });
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Location services are disabled', isError: true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Location permission denied', isError: true);
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _flutterMapController.move(
        LatLng(position.latitude, position.longitude),
        16.0,
      );
      _showSnackBar('Moved to current location');
    } catch (e) {
      _showSnackBar('Could not get location: $e', isError: true);
    } finally {
      setState(() => _loadingLocation = false);
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'kashi_geofield_pro/1.0',
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat'] as String);
          final lng = double.parse(data[0]['lon'] as String);
          _flutterMapController.move(LatLng(lat, lng), 14.0);
          _showSnackBar('Found: ${data[0]['display_name']}');
        } else {
          _showSnackBar('Location not found', isError: true);
        }
      }
    } catch (e) {
      _showSnackBar('Search failed: $e', isError: true);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          isError ? AppTheme.errorColor : AppTheme.greenPrimary,
    ));
  }

  void _onMapTap(fmap.TapPosition tapPos, LatLng latLng) {
    if (_mapController.drawMode != DrawMode.none) {
      _mapController.addPoint(latLng);
      // Show shape detail after adding marker
      if (_mapController.drawMode == DrawMode.none &&
          _mapController.selectedShape != null) {
        _showShapeDetail();
      }
    } else {
      // Check if tapped on a shape
      _mapController.clearSelection();
      setState(() {});
    }
  }

  void _showShapeDetail() {
    final shape = _mapController.selectedShape;
    if (shape == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ShapeDetailSheet(
        shape: shape,
        controller: _mapController,
        takeScreenshot: () async {
          return await _screenshotController.capture();
        },
      ),
    );
  }

  void _onDownloadMapArea() {
    // Get visible bounds
    final bounds = _flutterMapController.camera.visibleBounds;
    final minLat = bounds.south;
    final maxLat = bounds.north;
    final minLng = bounds.west;
    final maxLng = bounds.east;

    _mapController.toggleOfflineDownloadMode();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfflineMapsScreen(
          initialBounds: {
            'minLat': minLat,
            'maxLat': maxLat,
            'minLng': minLng,
            'maxLng': maxLng,
          },
        ),
      ),
    );
  }

  List<fmap.Polygon> _buildPolygons() {
    final polygons = <fmap.Polygon>[];

    // Current drawing polygon
    if (_mapController.currentPoints.length >= 3 &&
        _mapController.drawMode == DrawMode.polygon) {
      polygons.add(fmap.Polygon(
        points: _mapController.currentPoints,
        color: AppTheme.greenPrimary.withOpacity(0.2),
        borderColor: AppTheme.greenAccent,
        borderStrokeWidth: 2,
        isDotted: true,
      ));
    }

    // Drawn shapes (polygons)
    if (_mapController.showPolygonLayer) {
      for (final shape in _mapController.drawnShapes) {
        if (shape.type == DrawMode.polygon) {
          final isSelected = _mapController.selectedShape?.id == shape.id;
          polygons.add(fmap.Polygon(
            points: shape.points,
            color: shape.color.withOpacity(isSelected ? 0.4 : 0.25),
            borderColor: isSelected ? Colors.white : shape.color,
            borderStrokeWidth: isSelected ? 3 : 2,
            label: shape.name,
            labelStyle: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 4),
              ],
            ),
          ));
        }
      }

      // Saved polygons from DB
      for (final poly in _savedPolygons) {
        try {
          final coordList =
              (jsonDecode(poly.coordinates) as List).cast<Map<String, dynamic>>();
          final pts = coordList
              .map((c) => LatLng(c['lat'] as double, c['lng'] as double))
              .toList();
          final colorHex = poly.color.startsWith('#')
              ? poly.color.substring(1)
              : poly.color;
          final color =
              Color(int.parse('FF$colorHex', radix: 16));
          polygons.add(fmap.Polygon(
            points: pts,
            color: color.withOpacity(0.2),
            borderColor: color,
            borderStrokeWidth: 1.5,
            label: poly.name,
            labelStyle: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ));
        } catch (_) {}
      }
    }

    // Village boundaries
    if (_mapController.showVillageLayer) {
      for (final village in _villages) {
        try {
          final coordList = (jsonDecode(village.coordinates) as List)
              .cast<Map<String, dynamic>>();
          final pts = coordList
              .map((c) => LatLng(c['lat'] as double, c['lng'] as double))
              .toList();
          polygons.add(fmap.Polygon(
            points: pts,
            color: const Color(0xFF388BFD).withOpacity(0.15),
            borderColor: const Color(0xFF388BFD),
            borderStrokeWidth: 1.5,
            label: village.villageName,
            labelStyle: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ));
        } catch (_) {}
      }
    }

    // KML shapes
    if (_mapController.showKmlLayer) {
      for (final kmlShape in _mapController.kmlShapes) {
        if (kmlShape.type == 'polygon') {
          final pts = kmlShape.coordinates
              .map((c) => LatLng(c['lat']!, c['lng']!))
              .toList();
          polygons.add(fmap.Polygon(
            points: pts,
            color: const Color(0xFFD29922).withOpacity(0.2),
            borderColor: const Color(0xFFD29922),
            borderStrokeWidth: 2,
            label: kmlShape.name,
            labelStyle: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ));
        }
      }
    }

    return polygons;
  }

  List<fmap.Polyline> _buildPolylines() {
    final lines = <fmap.Polyline>[];

    // Current drawing path
    if (_mapController.currentPoints.length >= 2 &&
        _mapController.drawMode == DrawMode.path) {
      lines.add(fmap.Polyline(
        points: _mapController.currentPoints,
        color: AppTheme.infoColor,
        strokeWidth: 2.5,
        isDotted: true,
      ));
    }

    // Drawn paths
    if (_mapController.showPolygonLayer) {
      for (final shape in _mapController.drawnShapes) {
        if (shape.type == DrawMode.path) {
          lines.add(fmap.Polyline(
            points: shape.points,
            color: shape.color,
            strokeWidth: 3,
          ));
        }
      }
    }

    // KML paths
    if (_mapController.showKmlLayer) {
      for (final kmlShape in _mapController.kmlShapes) {
        if (kmlShape.type == 'path') {
          final pts = kmlShape.coordinates
              .map((c) => LatLng(c['lat']!, c['lng']!))
              .toList();
          lines.add(fmap.Polyline(
            points: pts,
            color: const Color(0xFFD29922),
            strokeWidth: 2,
          ));
        }
      }
    }

    return lines;
  }

  List<fmap.Marker> _buildMarkers() {
    final markers = <fmap.Marker>[];

    // Current drawing points (dots)
    for (final pt in _mapController.currentPoints) {
      markers.add(fmap.Marker(
        point: pt,
        width: 12,
        height: 12,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.greenAccent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ));
    }

    // Drawn markers
    if (_mapController.showPolygonLayer) {
      for (final shape in _mapController.drawnShapes) {
        if (shape.type == DrawMode.marker) {
          markers.add(fmap.Marker(
            point: shape.points.first,
            width: 36,
            height: 40,
            child: GestureDetector(
              onTap: () {
                _mapController.selectShape(shape);
                _showShapeDetail();
              },
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: shape.color),
                    ),
                    child: Text(
                      shape.name,
                      style: TextStyle(color: shape.color, fontSize: 8),
                    ),
                  ),
                  Icon(Icons.place, color: shape.color, size: 28),
                ],
              ),
            ),
          ));
        }
      }
    }

    // KML markers
    if (_mapController.showKmlLayer) {
      for (final kmlShape in _mapController.kmlShapes) {
        if (kmlShape.type == 'marker' && kmlShape.coordinates.isNotEmpty) {
          markers.add(fmap.Marker(
            point: LatLng(
                kmlShape.coordinates.first['lat']!,
                kmlShape.coordinates.first['lng']!),
            width: 30,
            height: 30,
            child: const Icon(Icons.room, color: Color(0xFFD29922), size: 30),
          ));
        }
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isToolbarOffsetInitialized) {
      // Initialize to right side with some padding
      _toolbarOffset = Offset(MediaQuery.of(context).size.width - 64, 120);
      _isToolbarOffsetInitialized = true;
    }

    return ListenableBuilder(
      listenable: _mapController,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          body: Stack(
            children: [
              // ── Map ──────────────────────────────────────────────────────────
              Screenshot(
                controller: _screenshotController,
                child: fmap.FlutterMap(
                  mapController: _flutterMapController,
                  options: fmap.MapOptions(
                    initialCenter: const LatLng(26.9124, 75.7873),
                    initialZoom: 13,
                    onTap: _onMapTap,
                    interactionOptions: const fmap.InteractionOptions(
                      flags: fmap.InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    fmap.TileLayer(
                    urlTemplate: _mapController.mapStyle == 'Satellite'
                        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.kashi.kashi_geofield_pro',
                    maxZoom: 19,
                  ),
                  fmap.PolygonLayer(polygons: _buildPolygons()),
                  fmap.PolylineLayer(polylines: _buildPolylines()),
                  fmap.MarkerLayer(markers: _buildMarkers()),
                ],
              ),
              ), // Close Screenshot

              // ── Top search bar ────────────────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.borderColor),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 10),
                                  const Icon(Icons.search,
                                      color: AppTheme.textSecondary, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 14),
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Search village, town, city...',
                                        border: InputBorder.none,
                                        filled: false,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onSubmitted: _searchLocation,
                                    ),
                                  ),
                                  if (_isSearching)
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  else if (_searchController.text.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.clear,
                                          size: 16,
                                          color: AppTheme.textSecondary),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {});
                                      },
                                    ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _MapIconBtn(
                            icon: Icons.layers,
                            isActive: _showLayerPanel,
                            onTap: () =>
                                setState(() => _showLayerPanel = !_showLayerPanel),
                          ),
                        ],
                      ),
                    ),
                    // Drawing mode indicator banner
                    if (_mapController.drawMode != DrawMode.none)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.greenPrimary.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.touch_app,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _drawModeHint(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _mapController.setDrawMode(DrawMode.none),
                              child: const Text('Cancel',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // ── Right-side draw toolbar (Draggable) ───────────────────────
              Positioned(
                left: _toolbarOffset.dx,
                top: _toolbarOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _toolbarOffset += details.delta;
                      // Safe bounds
                      final size = MediaQuery.of(context).size;
                      double dx = _toolbarOffset.dx;
                      double dy = _toolbarOffset.dy;
                      if (dx < 0) dx = 0;
                      if (dy < 40) dy = 40;
                      if (dx > size.width - 64) dx = size.width - 64;
                      if (dy > size.height - 200) dy = size.height - 200;
                      _toolbarOffset = Offset(dx, dy);
                    });
                  },
                  child: DrawToolbar(controller: _mapController),
                ),
              ),

              // ── Layer panel ───────────────────────────────────────────────
              if (_showLayerPanel)
                Positioned(
                  right: 12,
                  top: 80,
                  child: LayerPanel(
                    controller: _mapController,
                    onClose: () => setState(() => _showLayerPanel = false),
                  ),
                ),

              // ── Bottom stats bar (when shape selected) ────────────────────
              if (_mapController.selectedShape != null)
                Positioned(
                  bottom: 16,
                  left: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: _showShapeDetail,
                    child: _SelectedShapeBar(
                        shape: _mapController.selectedShape!),
                  ),
                ),

              // ── GPS button (bottom-left) ──────────────────────────────────
              Positioned(
                bottom: _mapController.selectedShape != null ? 80 : 16,
                left: 12,
                child: _MapIconBtn(
                  icon: Icons.my_location,
                  isActive: false,
                  isLoading: _loadingLocation,
                  onTap: _goToCurrentLocation,
                ),
              ),

              // ── Zoom controls ─────────────────────────────────────────────
              Positioned(
                bottom: _mapController.selectedShape != null ? 80 : 16,
                right: 72,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapIconBtn(
                        icon: Icons.add,
                        isActive: false,
                        onTap: () {
                          final c = _flutterMapController.camera;
                          _flutterMapController.move(c.center, c.zoom + 1);
                        }),
                    const SizedBox(height: 4),
                    _MapIconBtn(
                        icon: Icons.remove,
                        isActive: false,
                        onTap: () {
                          final c = _flutterMapController.camera;
                          _flutterMapController.move(c.center, c.zoom - 1);
                        }),
                  ],
                ),
              ),

              // ── FAB (show shapes list) ────────────────────────────────────
              Positioned(
                bottom: _mapController.selectedShape != null ? 80 : 16,
                right: 16,
                child: FloatingActionButton(
                  heroTag: 'shapes_list',
                  mini: false,
                  onPressed: _showShapesList,
                  child: const Icon(Icons.list_alt),
                ),
              ),
              // ── Offline Download Mode Overlay ──────────────────────────────
              if (_mapController.isOfflineDownloadMode)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.4),
                    child: SafeArea(
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Position the area to download',
                              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Spacer(),
                          // Center frame
                          Container(
                            width: MediaQuery.of(context).size.width * 0.8,
                            height: MediaQuery.of(context).size.width * 0.8,
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.greenPrimary, width: 3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Icon(Icons.add, color: AppTheme.greenPrimary.withOpacity(0.5), size: 30),
                            ),
                          ),
                          const Spacer(),
                          // Bottom buttons
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _mapController.toggleOfflineDownloadMode(),
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _onDownloadMapArea,
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                                    child: const Text('Download'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _drawModeHint() {
    switch (_mapController.drawMode) {
      case DrawMode.polygon:
        final n = _mapController.currentPoints.length;
        return 'Tap to add points ($n). Need 3+ to close polygon.';
      case DrawMode.path:
        return 'Tap to add path points. Press ✓ to save.';
      case DrawMode.marker:
        return 'Tap to place marker.';
      default:
        return '';
    }
  }

  void _showShapesList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ShapesListPanel(
        controller: _mapController,
        onShapeTap: (shape) {
          _mapController.selectShape(shape);
          if (shape.points.isNotEmpty) {
            _flutterMapController.move(shape.points.first, 15);
          }
          Navigator.pop(context);
          _showShapeDetail();
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// ─── Helper widgets ────────────────────────────────────────────────────────────

class _MapIconBtn extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final bool isLoading;

  const _MapIconBtn({
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.greenPrimary
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isActive ? AppTheme.greenPrimary : AppTheme.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.greenAccent,
                  ),
                ),
              )
            : Icon(
                icon,
                color: isActive ? Colors.white : AppTheme.textSecondary,
                size: 20,
              ),
      ),
    );
  }
}

class _SelectedShapeBar extends StatelessWidget {
  final DrawnShape shape;
  const _SelectedShapeBar({required this.shape});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: shape.color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: shape.color.withOpacity(0.15),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: shape.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              shape.name,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
          if (shape.type == DrawMode.polygon)
            Text(
              GeoCalculator.formatArea(shape.areaHectares),
              style: TextStyle(color: shape.color, fontSize: 12),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.expand_less,
              color: AppTheme.textSecondary, size: 18),
        ],
      ),
    );
  }
}

class _ShapesListPanel extends StatelessWidget {
  final MapController controller;
  final void Function(DrawnShape) onShapeTap;

  const _ShapesListPanel({
    required this.controller,
    required this.onShapeTap,
  });

  @override
  Widget build(BuildContext context) {
    final shapes = controller.drawnShapes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.list_alt, color: AppTheme.greenAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'Drawn Shapes',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
            ],
          ),
        ),
        if (shapes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.draw, color: AppTheme.textMuted, size: 48),
                SizedBox(height: 8),
                Text('No shapes drawn yet', style: TextStyle(color: AppTheme.textSecondary)),
                Text(
                  'Use the toolbar on the right to draw polygons, paths, or markers',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          )
        else
          ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: shapes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final s = shapes[i];
                return ListTile(
                  onTap: () => onShapeTap(s),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  tileColor: AppTheme.bgSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  leading: CircleAvatar(
                    backgroundColor: s.color.withOpacity(0.2),
                    child: Icon(
                      s.type == DrawMode.polygon
                          ? Icons.pentagon
                          : s.type == DrawMode.path
                              ? Icons.polyline
                              : Icons.place,
                      color: s.color,
                      size: 18,
                    ),
                  ),
                  title: Text(s.name,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    s.type == DrawMode.polygon
                        ? GeoCalculator.formatArea(s.areaHectares)
                        : s.type == DrawMode.path
                            ? GeoCalculator.formatPerimeter(s.perimeterMeters)
                            : '${s.points.first.latitude.toStringAsFixed(5)}, ${s.points.first.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppTheme.textMuted, size: 16),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
