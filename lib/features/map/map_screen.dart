import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../../shared/theme.dart';
import '../../core/database/db_helper.dart';
import '../../core/models/village_model.dart';
import '../../core/models/polygon_model.dart';
import '../../core/utils/geo_calculator.dart';
import '../../core/utils/pdf_generator.dart';
import 'map_controller.dart';
import 'widgets/draw_toolbar.dart';
import 'widgets/layer_panel.dart';
import 'widgets/shape_detail_sheet.dart';
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
  bool _showWaypointPanel = false;
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
      backgroundColor: isError ? AppTheme.errorColor : AppTheme.greenPrimary,
    ));
  }

  void _onMapTap(fmap.TapPosition tapPos, LatLng latLng) {
    if (_mapController.drawMode != DrawMode.none) {
      _mapController.addPoint(latLng);
      // Auto-open waypoint panel when drawing
      if (!_showWaypointPanel && _mapController.drawMode == DrawMode.polygon) {
        setState(() => _showWaypointPanel = true);
      }
    } else {
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
    final bounds = _flutterMapController.camera.visibleBounds;
    _mapController.toggleOfflineDownloadMode();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfflineMapsScreen(
          initialBounds: {
            'minLat': bounds.south,
            'maxLat': bounds.north,
            'minLng': bounds.west,
            'maxLng': bounds.east,
          },
        ),
      ),
    );
  }

  List<fmap.Polygon> _buildPolygons() {
    final polygons = <fmap.Polygon>[];

    // Current drawing polygon preview
    if (_mapController.currentPoints.length >= 3 &&
        _mapController.drawMode == DrawMode.polygon) {
      polygons.add(fmap.Polygon(
        points: _mapController.currentPoints,
        color: const Color(0xFF2EA043).withValues(alpha: 0.15),
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
            color: shape.color.withValues(alpha: isSelected ? 0.35 : 0.2),
            borderColor: isSelected ? Colors.white : shape.color,
            borderStrokeWidth: isSelected ? 3 : 2,
          ));
        }
      }
    }

    // Village polygons
    if (_mapController.showVillageLayer) {
      for (final v in _villages) {
        try {
          final coords = jsonDecode(v.coordinates) as List;
          final pts = coords
              .map((c) => LatLng(
                    (c['lat'] as num).toDouble(),
                    (c['lng'] as num).toDouble(),
                  ))
              .toList();
          polygons.add(fmap.Polygon(
            points: pts,
            color: AppTheme.infoColor.withValues(alpha: 0.15),
            borderColor: AppTheme.infoColor,
            borderStrokeWidth: 1.5,
          ));
        } catch (_) {}
      }
    }

    // KML polygons
    if (_mapController.showKmlLayer) {
      for (final kmlShape in _mapController.kmlShapes) {
        if (kmlShape.type == 'polygon' && kmlShape.coordinates.isNotEmpty) {
          final pts = kmlShape.coordinates
              .map((c) => LatLng(c['lat']!, c['lng']!))
              .toList();
          polygons.add(fmap.Polygon(
            points: pts,
            color: const Color(0xFFD29922).withValues(alpha: 0.2),
            borderColor: const Color(0xFFD29922),
            borderStrokeWidth: 2,
          ));
        }
      }
    }

    // Saved polygons from DB
    for (final poly in _savedPolygons) {
      try {
        final coords = jsonDecode(poly.coordinates) as List;
        final pts = coords
            .map((c) => LatLng(
                  (c['lat'] as num).toDouble(),
                  (c['lng'] as num).toDouble(),
                ))
            .toList();
        polygons.add(fmap.Polygon(
          points: pts,
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
          borderColor: const Color(0xFF8B5CF6),
          borderStrokeWidth: 1.5,
          isDotted: true,
        ));
      } catch (_) {}
    }

    return polygons;
  }

  List<fmap.Polyline> _buildPolylines() {
    final lines = <fmap.Polyline>[];

    if (_mapController.showPolygonLayer) {
      for (final shape in _mapController.drawnShapes) {
        if (shape.type == DrawMode.path) {
          final isSelected = _mapController.selectedShape?.id == shape.id;
          lines.add(fmap.Polyline(
            points: shape.points,
            color: isSelected ? Colors.white : shape.color,
            strokeWidth: isSelected ? 4 : 3,
          ));
        }
      }
    }

    // KML paths
    if (_mapController.showKmlLayer) {
      for (final kmlShape in _mapController.kmlShapes) {
        if (kmlShape.type == 'path' && kmlShape.coordinates.isNotEmpty) {
          lines.add(fmap.Polyline(
            points: kmlShape.coordinates
                .map((c) => LatLng(c['lat']!, c['lng']!))
                .toList(),
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

    // ── In-progress drawing points with sequential numbered labels ──
    for (int i = 0; i < _mapController.currentPoints.length; i++) {
      final pt = _mapController.currentPoints[i];
      final label = (i + 1).toString().padLeft(3, '0');
      markers.add(fmap.Marker(
        point: pt,
        width: 52,
        height: 46,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.yellow,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black54),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ],
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: AppTheme.greenAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ],
        ),
      ));
    }

    // ── Drawn polygon vertices with numbered labels ──
    if (_mapController.showPolygonLayer) {
      for (final shape in _mapController.drawnShapes) {
        if (shape.type == DrawMode.polygon) {
          final isSelected = _mapController.selectedShape?.id == shape.id;
          for (int i = 0; i < shape.points.length; i++) {
            final pt = shape.points[i];
            final label = (i + 1).toString().padLeft(3, '0');
            markers.add(fmap.Marker(
              point: pt,
              width: 52,
              height: 46,
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () {
                  _mapController.selectShape(shape);
                  _showShapeDetail();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.yellow : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black38),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.black : shape.color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: shape.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ],
                ),
              ),
            ));
          }
        }

        // Drawn standalone markers
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

  // ── Get active waypoints for the panel ──
  List<Map<String, dynamic>> _getActiveWaypoints() {
    final points = <LatLng>[];

    if (_mapController.drawMode == DrawMode.polygon &&
        _mapController.currentPoints.isNotEmpty) {
      points.addAll(_mapController.currentPoints);
    } else if (_mapController.selectedShape != null &&
        _mapController.selectedShape!.type == DrawMode.polygon) {
      points.addAll(_mapController.selectedShape!.points);
    } else {
      final poly = _mapController.drawnShapes
          .where((s) => s.type == DrawMode.polygon)
          .lastOrNull;
      if (poly != null) points.addAll(poly.points);
    }

    return [
      for (int i = 0; i < points.length; i++)
        {
          'index': i,
          'label': (i + 1).toString().padLeft(3, '0'),
          'lat': points[i].latitude,
          'lng': points[i].longitude,
        }
    ];
  }

  String _getActiveShapeName() {
    if (_mapController.drawMode == DrawMode.polygon) return 'Drawing...';
    if (_mapController.selectedShape != null) {
      return _mapController.selectedShape!.name;
    }
    final poly = _mapController.drawnShapes
        .where((s) => s.type == DrawMode.polygon)
        .lastOrNull;
    return poly?.name ?? 'Polygon';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isToolbarOffsetInitialized) {
      _toolbarOffset = Offset(MediaQuery.of(context).size.width - 64, 120);
      _isToolbarOffsetInitialized = true;
    }

    return ListenableBuilder(
      listenable: _mapController,
      builder: (context, _) {
        final waypoints = _getActiveWaypoints();
        final shapeName = _getActiveShapeName();

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
              ),

              // ── Waypoint Side Panel ──────────────────────────────────────────
              if (_showWaypointPanel)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 225,
                  child: _WaypointPanel(
                    waypoints: waypoints,
                    shapeName: shapeName,
                    onClose: () => setState(() => _showWaypointPanel = false),
                    onWaypointTap: (wp) {
                      _flutterMapController.move(
                        LatLng(wp['lat'] as double, wp['lng'] as double),
                        16,
                      );
                    },
                    onPrint: waypoints.isNotEmpty
                        ? () => _printPolygon(waypoints, shapeName)
                        : null,
                    onExportKml: waypoints.isNotEmpty
                        ? () => _exportKml(waypoints, shapeName)
                        : null,
                  ),
                ),

              // ── Top search bar ────────────────────────────────────────────
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: _showWaypointPanel ? 233 : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _MapIconBtn(
                              icon: Icons.table_rows_rounded,
                              isActive: _showWaypointPanel,
                              onTap: () => setState(() =>
                                  _showWaypointPanel = !_showWaypointPanel),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.bgCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: AppTheme.borderColor),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 10),
                                    const Icon(Icons.search,
                                        color: AppTheme.textSecondary,
                                        size: 18),
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
                              onTap: () => setState(
                                  () => _showLayerPanel = !_showLayerPanel),
                            ),
                          ],
                        ),
                      ),
                      // Drawing mode indicator banner
                      if (_mapController.drawMode != DrawMode.none)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.greenPrimary
                                  .withValues(alpha: 0.92),
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
                                  onPressed: () => _mapController
                                      .setDrawMode(DrawMode.none),
                                  child: const Text('Cancel',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Draggable Draw Toolbar ──────────────────────────────────────
              Positioned(
                left: _toolbarOffset.dx,
                top: _toolbarOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _toolbarOffset += details.delta;
                      final size = MediaQuery.of(context).size;
                      double dx = _toolbarOffset.dx;
                      double dy = _toolbarOffset.dy;
                      if (dx < 0) dx = 0;
                      if (dy < 40) dy = 40;
                      if (dx > size.width - 64) dx = size.width - 64;
                      if (dy > size.height - 220) dy = size.height - 220;
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
                  left: _showWaypointPanel ? 237 : 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: _showShapeDetail,
                    child: _SelectedShapeBar(
                        shape: _mapController.selectedShape!),
                  ),
                ),

              // ── GPS button ────────────────────────────────────────────────
              Positioned(
                bottom: _mapController.selectedShape != null ? 80 : 16,
                left: _showWaypointPanel ? 244 : 12,
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

              // ── FAB ──────────────────────────────────────────────────────
              Positioned(
                bottom: _mapController.selectedShape != null ? 80 : 16,
                right: 16,
                child: FloatingActionButton(
                  heroTag: 'shapes_list',
                  onPressed: _showShapesList,
                  child: const Icon(Icons.list_alt),
                ),
              ),

              // ── Offline Download Mode Overlay ─────────────────────────────
              if (_mapController.isOfflineDownloadMode)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: SafeArea(
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Position the area to download',
                              style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: MediaQuery.of(context).size.width * 0.8,
                            height: MediaQuery.of(context).size.width * 0.8,
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppTheme.greenPrimary, width: 3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Icon(Icons.add,
                                  color: AppTheme.greenPrimary
                                      .withValues(alpha: 0.5),
                                  size: 30),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _mapController
                                        .toggleOfflineDownloadMode(),
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _onDownloadMapArea,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryColor,
                                        foregroundColor: Colors.white),
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
        return 'Tap map to add points ($n added). Press ✓ to close.';
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
          setState(() => _showWaypointPanel = true);
          _showShapeDetail();
        },
      ),
    );
  }

  Future<void> _printPolygon(
      List<Map<String, dynamic>> waypoints, String name) async {
    try {
      _showSnackBar('Generating PDF report...');
      final Uint8List? mapShot = await _screenshotController.capture();

      final pts = waypoints
          .map((w) => {'lat': w['lat'] as double, 'lng': w['lng'] as double})
          .toList();

      final shape = _mapController.selectedShape ??
          _mapController.drawnShapes
              .where((s) => s.type == DrawMode.polygon)
              .lastOrNull;

      final area = shape?.areaHectares ??
          GeoCalculator.calculateAreaHectares(pts);
      final perimeter = shape?.perimeterMeters ??
          GeoCalculator.calculatePerimeterMeters(pts);

      final path = await PdfGenerator.generatePolygonPdf(
        polygonName: name,
        points: pts,
        areaHectares: area,
        perimeterMeters: perimeter,
        color: '#2EA043',
        mapScreenshot: mapShot,
      );

      final pdfBytes = await File(path).readAsBytes();
      await Printing.layoutPdf(onLayout: (_) => pdfBytes);
    } catch (e) {
      if (mounted) _showSnackBar('Print failed: $e', isError: true);
    }
  }

  Future<void> _exportKml(
      List<Map<String, dynamic>> waypoints, String name) async {
    try {
      final pts = waypoints
          .map((w) => {'lat': w['lat'] as double, 'lng': w['lng'] as double})
          .toList();

      final kml = _buildFullKml(name, pts, waypoints);

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save KML File',
        fileName: '$name.kml',
        type: FileType.custom,
        allowedExtensions: ['kml'],
      );

      if (outputPath != null) {
        await File(outputPath).writeAsString(kml);
        if (mounted) _showSnackBar('KML saved: $outputPath');
      }
    } catch (e) {
      if (mounted) _showSnackBar('KML export failed: $e', isError: true);
    }
  }

  String _buildFullKml(
    String name,
    List<Map<String, double>> pts,
    List<Map<String, dynamic>> waypoints,
  ) {
    final coordString = pts
        .map((p) => '${p['lng']},${p['lat']},0')
        .followedBy(['${pts.first['lng']},${pts.first['lat']},0'])
        .join('\n              ');

    final waypointPlacemarks = waypoints.map((w) {
      final label = w['label'] as String;
      final lat = w['lat'] as double;
      final lng = w['lng'] as double;
      return '''    <Placemark>
      <name>$label</name>
      <description>Waypoint $label&#10;Lat: ${lat.toStringAsFixed(6)}&#10;Lng: ${lng.toStringAsFixed(6)}</description>
      <Style>
        <IconStyle>
          <color>ff000000</color>
          <scale>0.7</scale>
          <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_square.png</href></Icon>
        </IconStyle>
        <LabelStyle><scale>0.9</scale></LabelStyle>
      </Style>
      <Point>
        <coordinates>$lng,$lat,0</coordinates>
      </Point>
    </Placemark>''';
    }).join('\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$name</name>
    <Style id="polyStyle">
      <LineStyle><color>ff2EA043</color><width>3</width></LineStyle>
      <PolyStyle><color>302EA043</color></PolyStyle>
    </Style>
    <Placemark>
      <name>$name (Polygon)</name>
      <styleUrl>#polyStyle</styleUrl>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              $coordString
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
$waypointPlacemarks
  </Document>
</kml>''';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// ─── Waypoint Side Panel ──────────────────────────────────────────────────────
class _WaypointPanel extends StatelessWidget {
  final List<Map<String, dynamic>> waypoints;
  final VoidCallback onClose;
  final void Function(Map<String, dynamic>) onWaypointTap;
  final VoidCallback? onPrint;
  final VoidCallback? onExportKml;
  final String shapeName;

  const _WaypointPanel({
    required this.waypoints,
    required this.onClose,
    required this.onWaypointTap,
    required this.shapeName,
    this.onPrint,
    this.onExportKml,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: AppTheme.bgCard,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pentagon,
                      color: AppTheme.greenAccent, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      shapeName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close,
                        color: AppTheme.textMuted, size: 18),
                  ),
                ],
              ),
            ),

            // Column headers
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              color: const Color(0xFF0D1B2A),
              child: const Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text('Name',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text('Position',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            // Waypoints list
            Expanded(
              child: waypoints.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app,
                                color: AppTheme.textMuted, size: 36),
                            SizedBox(height: 10),
                            Text(
                              'Tap the Polygon tool\nthen tap the map to\nadd waypoints',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: waypoints.length,
                      itemBuilder: (ctx, i) {
                        final wp = waypoints[i];
                        final lat = (wp['lat'] as double).toStringAsFixed(5);
                        final lng = (wp['lng'] as double).toStringAsFixed(5);
                        return InkWell(
                          onTap: () => onWaypointTap(wp),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: i % 2 == 0
                                  ? Colors.transparent
                                  : const Color(0xFF0D1B2A)
                                      .withValues(alpha: 0.5),
                              border: Border(
                                bottom: BorderSide(
                                    color: AppTheme.borderColor
                                        .withValues(alpha: 0.4)),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Label badge
                                Container(
                                  width: 40,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 3, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.yellow,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: Colors.black38),
                                  ),
                                  child: Text(
                                    wp['label'] as String,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'N${lat}°',
                                        style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 9.5,
                                            fontFamily: 'monospace'),
                                      ),
                                      Text(
                                        'E${lng}°',
                                        style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 9.5,
                                            fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Action buttons footer
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                border: Border(top: BorderSide(color: AppTheme.borderColor)),
              ),
              child: Column(
                children: [
                  Text(
                    '${waypoints.length} Waypoints',
                    style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _PanelBtn(
                          icon: Icons.print_rounded,
                          label: 'Print Map',
                          color: AppTheme.infoColor,
                          onTap: onPrint,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PanelBtn(
                          icon: Icons.download_rounded,
                          label: 'KML File',
                          color: AppTheme.greenPrimary,
                          onTap: onExportKml,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _PanelBtn({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.45)
                  : AppTheme.borderColor),
        ),
        child: Column(
          children: [
            Icon(icon, color: enabled ? color : AppTheme.textMuted, size: 18),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: enabled ? color : AppTheme.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

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
          color: isActive ? AppTheme.greenPrimary : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isActive ? AppTheme.greenPrimary : AppTheme.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
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
        border: Border.all(color: shape.color.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: shape.color.withValues(alpha: 0.15),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: shape.color, shape: BoxShape.circle),
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
                Text('No shapes drawn yet',
                    style: TextStyle(color: AppTheme.textSecondary)),
                SizedBox(height: 4),
                Text(
                  'Use the toolbar to draw polygons, paths, or markers',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: ListView.separated(
              shrinkWrap: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: shapes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final s = shapes[i];
                return ListTile(
                  onTap: () => onShapeTap(s),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  tileColor: AppTheme.bgSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  leading: CircleAvatar(
                    backgroundColor: s.color.withValues(alpha: 0.2),
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
                        ? '${s.points.length} pts · ${GeoCalculator.formatArea(s.areaHectares)}'
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
