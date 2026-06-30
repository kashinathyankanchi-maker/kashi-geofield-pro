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
    if (mounted) {
      setState(() {
        _villages = villages;
        _savedPolygons = polygons;
      });
    }
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
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
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
      _showSnackBar('Search failed', isError: true);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.errorColor : AppTheme.greenPrimary,
    ));
  }

  void _onMapTap(fmap.TapPosition tapPos, LatLng latLng) {
    if (_mapController.drawMode != DrawMode.none) {
      _mapController.addPoint(latLng);
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
        takeScreenshot: () async => await _screenshotController.capture(),
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

  // ── Map layer builders ─────────────────────────────────────────────────────

  List<fmap.Polygon> _buildPolygons() {
    final polygons = <fmap.Polygon>[];

    // Live drawing preview
    if (_mapController.currentPoints.length >= 2 &&
        _mapController.drawMode == DrawMode.polygon) {
      polygons.add(fmap.Polygon(
        points: _mapController.currentPoints,
        color: AppTheme.greenPrimary.withValues(alpha: 0.12),
        borderColor: AppTheme.greenAccent,
        borderStrokeWidth: 2,
        isDotted: true,
      ));
    }

    if (_mapController.showPolygonLayer) {
      for (final shape in _mapController.drawnShapes) {
        if (shape.type == DrawMode.polygon) {
          final isSelected = _mapController.selectedShape?.id == shape.id;
          polygons.add(fmap.Polygon(
            points: shape.points,
            color: shape.color.withValues(alpha: isSelected ? 0.35 : 0.18),
            borderColor: isSelected ? Colors.white : shape.color,
            borderStrokeWidth: isSelected ? 3.5 : 2.5,
          ));
        }
      }
    }

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
            color: AppTheme.infoColor.withValues(alpha: 0.12),
            borderColor: AppTheme.infoColor,
            borderStrokeWidth: 1.5,
          ));
        } catch (_) {}
      }
    }

    if (_mapController.showKmlLayer) {
      for (final kmlShape in _mapController.kmlShapes) {
        if (kmlShape.type == 'polygon' && kmlShape.coordinates.isNotEmpty) {
          final pts = kmlShape.coordinates
              .map((c) => LatLng(c['lat']!, c['lng']!))
              .toList();
          polygons.add(fmap.Polygon(
            points: pts,
            color: const Color(0xFFD29922).withValues(alpha: 0.18),
            borderColor: const Color(0xFFD29922),
            borderStrokeWidth: 2,
          ));
        }
      }
    }

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
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
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

    // In-progress drawing: numbered dots
    for (int i = 0; i < _mapController.currentPoints.length; i++) {
      final pt = _mapController.currentPoints[i];
      final label = (i + 1).toString().padLeft(3, '0');
      markers.add(fmap.Marker(
        point: pt,
        width: 54,
        height: 46,
        alignment: Alignment.bottomCenter,
        child: _WaypointPin(label: label, color: AppTheme.greenAccent, isActive: true),
      ));
    }

    // Completed polygon vertices
    if (_mapController.showPolygonLayer) {
      for (final shape in _mapController.drawnShapes) {
        if (shape.type == DrawMode.polygon) {
          final isSelected = _mapController.selectedShape?.id == shape.id;
          for (int i = 0; i < shape.points.length; i++) {
            final pt = shape.points[i];
            final label = (i + 1).toString().padLeft(3, '0');
            markers.add(fmap.Marker(
              point: pt,
              width: 54,
              height: 46,
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () {
                  _mapController.selectShape(shape);
                  setState(() => _showWaypointPanel = true);
                  _showShapeDetail();
                },
                child: _WaypointPin(
                  label: label,
                  color: shape.color,
                  isActive: isSelected,
                ),
              ),
            ));
          }
        }

        if (shape.type == DrawMode.marker) {
          markers.add(fmap.Marker(
            point: shape.points.first,
            width: 40,
            height: 44,
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: shape.color),
                    ),
                    child: Text(shape.name,
                        style: TextStyle(color: shape.color, fontSize: 8)),
                  ),
                  Icon(Icons.place, color: shape.color, size: 28),
                ],
              ),
            ),
          ));
        }
      }
    }

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

  // ── Waypoints data ─────────────────────────────────────────────────────────

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
    if (_mapController.drawMode == DrawMode.polygon) return 'Drawing Polygon...';
    if (_mapController.selectedShape != null) {
      return _mapController.selectedShape!.name;
    }
    final poly = _mapController.drawnShapes
        .where((s) => s.type == DrawMode.polygon)
        .lastOrNull;
    return poly?.name ?? 'No Polygon';
  }

  // ── Print / KML ────────────────────────────────────────────────────────────

  Future<void> _printPolygon(
      List<Map<String, dynamic>> waypoints, String name) async {
    try {
      _showSnackBar('Generating PDF...');
      final Uint8List? mapShot = await _screenshotController.capture();
      final pts = waypoints
          .map((w) => {'lat': w['lat'] as double, 'lng': w['lng'] as double})
          .toList();
      final shape = _mapController.selectedShape ??
          _mapController.drawnShapes
              .where((s) => s.type == DrawMode.polygon)
              .lastOrNull;
      final area =
          shape?.areaHectares ?? GeoCalculator.calculateAreaHectares(pts);
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
        if (mounted) _showSnackBar('KML saved successfully');
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
    if (pts.isEmpty) return '';
    final coordString = [
      ...pts.map((p) => '${p['lng']},${p['lat']},0'),
      '${pts.first['lng']},${pts.first['lat']},0',
    ].join('\n              ');

    final wpPlacemarks = waypoints.map((w) {
      final label = w['label'] as String;
      final lat = w['lat'] as double;
      final lng = w['lng'] as double;
      return '''    <Placemark>
      <name>$label</name>
      <description>Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}</description>
      <Style>
        <IconStyle><color>ff000000</color><scale>0.7</scale>
          <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_square.png</href></Icon>
        </IconStyle>
        <LabelStyle><scale>0.9</scale></LabelStyle>
      </Style>
      <Point><coordinates>$lng,$lat,0</coordinates></Point>
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
      <name>$name</name>
      <styleUrl>#polyStyle</styleUrl>
      <Polygon>
        <outerBoundaryIs><LinearRing>
          <coordinates>$coordString</coordinates>
        </LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>
$wpPlacemarks
  </Document>
</kml>''';
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _mapController,
      builder: (context, _) {
        final waypoints = _getActiveWaypoints();
        final shapeName = _getActiveShapeName();

        return Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          // Fixed bottom toolbar — always visible
          bottomNavigationBar: DrawToolbar(controller: _mapController),
          body: Stack(
            children: [
              // ── Map (full screen) ───────────────────────────────────────────
              Positioned.fill(
                child: Screenshot(
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
              ),

              // ── Left: Waypoint Panel ─────────────────────────────────────────
              if (_showWaypointPanel)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 220,
                  child: _WaypointPanel(
                    waypoints: waypoints,
                    shapeName: shapeName,
                    onClose: () =>
                        setState(() => _showWaypointPanel = false),
                    onWaypointTap: (wp) {
                      _flutterMapController.move(
                        LatLng(
                            wp['lat'] as double, wp['lng'] as double),
                        17,
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

              // ── Top: Search bar + action buttons ────────────────────────────
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Search row ─────────────────────────────────────────────
                    Padding(
                      padding: EdgeInsets.only(
                        left: _showWaypointPanel ? 228 : 12,
                        right: 12,
                        top: 10,
                        bottom: 6,
                      ),
                      child: Row(
                        children: [
                          // Waypoint panel toggle
                          _RoundBtn(
                            icon: Icons.format_list_numbered_rounded,
                            tooltip: 'Waypoints',
                            isActive: _showWaypointPanel,
                            onTap: () => setState(() =>
                                _showWaypointPanel = !_showWaypointPanel),
                          ),
                          const SizedBox(width: 8),
                          // Search field
                          Expanded(
                            child: _SearchBar(
                              controller: _searchController,
                              isSearching: _isSearching,
                              onSubmitted: _searchLocation,
                              onClear: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Layers toggle
                          _RoundBtn(
                            icon: Icons.layers_rounded,
                            tooltip: 'Layers',
                            isActive: _showLayerPanel,
                            onTap: () => setState(
                                () => _showLayerPanel = !_showLayerPanel),
                          ),
                          const SizedBox(width: 6),
                          // Shapes list
                          _RoundBtn(
                            icon: Icons.list_alt_rounded,
                            tooltip: 'Shapes',
                            isActive: false,
                            onTap: _showShapesList,
                          ),
                        ],
                      ),
                    ),

                    // ── Drawing banner ─────────────────────────────────────────
                    if (_mapController.drawMode != DrawMode.none)
                      Padding(
                        padding: EdgeInsets.only(
                          left: _showWaypointPanel ? 228 : 12,
                          right: 12,
                          bottom: 4,
                        ),
                        child: _DrawingBanner(
                          controller: _mapController,
                          pointCount: _mapController.currentPoints.length,
                        ),
                      ),
                  ],
                ),
              ),

              // ── Right: Map controls ──────────────────────────────────────────
              Positioned(
                right: 12,
                top: 80,
                child: Column(
                  children: [
                    // Zoom in
                    _MapFab(
                      icon: Icons.add,
                      tooltip: 'Zoom In',
                      onTap: () {
                        final c = _flutterMapController.camera;
                        _flutterMapController.move(c.center, c.zoom + 1);
                      },
                    ),
                    const SizedBox(height: 6),
                    // Zoom out
                    _MapFab(
                      icon: Icons.remove,
                      tooltip: 'Zoom Out',
                      onTap: () {
                        final c = _flutterMapController.camera;
                        _flutterMapController.move(c.center, c.zoom - 1);
                      },
                    ),
                    const SizedBox(height: 6),
                    // GPS location
                    _MapFab(
                      icon: _loadingLocation
                          ? Icons.hourglass_top_rounded
                          : Icons.my_location_rounded,
                      tooltip: 'My Location',
                      onTap: _loadingLocation ? null : _goToCurrentLocation,
                      isLoading: _loadingLocation,
                    ),
                    const SizedBox(height: 6),
                    // Download offline
                    _MapFab(
                      icon: Icons.download_rounded,
                      tooltip: 'Download Area',
                      onTap: _onDownloadMapArea,
                    ),
                  ],
                ),
              ),

              // ── Layer panel ──────────────────────────────────────────────────
              if (_showLayerPanel)
                Positioned(
                  right: 12,
                  top: 80,
                  child: LayerPanel(
                    controller: _mapController,
                    onClose: () =>
                        setState(() => _showLayerPanel = false),
                  ),
                ),

              // ── Bottom: Selected shape info bar ──────────────────────────────
              if (_mapController.selectedShape != null)
                Positioned(
                  bottom: 8,
                  left: _showWaypointPanel ? 228 : 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: _showShapeDetail,
                    child: _ShapeInfoBar(
                        shape: _mapController.selectedShape!),
                  ),
                ),

              // ── Offline Download Overlay ─────────────────────────────────────
              if (_mapController.isOfflineDownloadMode)
                _OfflineOverlay(
                  onCancel: _mapController.toggleOfflineDownloadMode,
                  onDownload: _onDownloadMapArea,
                ),
            ],
          ),
        );
      },
    );
  }

  void _showShapesList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ShapesListSheet(
        controller: _mapController,
        onShapeTap: (shape) {
          _mapController.selectShape(shape);
          if (shape.points.isNotEmpty) {
            _flutterMapController.move(shape.points.first, 15);
          }
          Navigator.pop(context);
          if (shape.type == DrawMode.polygon) {
            setState(() => _showWaypointPanel = true);
          }
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

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Numbered waypoint pin displayed on the map
class _WaypointPin extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;

  const _WaypointPin({
    required this.label,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isActive ? Colors.yellow : Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black38),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.black : color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 3,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact round icon button for map controls
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _RoundBtn({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.greenPrimary : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isActive
                    ? AppTheme.greenPrimary
                    : AppTheme.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Square map FAB (zoom/GPS/download)
class _MapFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isLoading;

  const _MapFab({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderColor),
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
              : Icon(icon, size: 20, color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// Search bar widget
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final void Function(String) onSubmitted;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.isSearching,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded,
              color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search village, city...',
                hintStyle: TextStyle(
                    color: AppTheme.textMuted, fontSize: 13),
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: onSubmitted,
            ),
          ),
          if (isSearching)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.greenAccent),
              ),
            )
          else if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.close_rounded,
                    size: 16, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Drawing mode status banner
class _DrawingBanner extends StatelessWidget {
  final MapController controller;
  final int pointCount;

  const _DrawingBanner({
    required this.controller,
    required this.pointCount,
  });

  @override
  Widget build(BuildContext context) {
    String hint;
    switch (controller.drawMode) {
      case DrawMode.polygon:
        hint = pointCount < 3
            ? 'Tap map to add points ($pointCount added, need 3+)'
            : 'Tap to add more points ($pointCount added) · Press ✓ to close';
        break;
      case DrawMode.path:
        hint = pointCount < 2
            ? 'Tap map to add path points ($pointCount added)'
            : 'Tap to add more · Press ✓ to save';
        break;
      case DrawMode.marker:
        hint = 'Tap on map to place a marker';
        break;
      default:
        hint = '';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.greenPrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenPrimary.withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app_rounded,
              color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(hint,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Selected shape info bar at the bottom
class _ShapeInfoBar extends StatelessWidget {
  final DrawnShape shape;
  const _ShapeInfoBar({required this.shape});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: shape.color.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: shape.color.withValues(alpha: 0.18),
            blurRadius: 14,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: shape.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(shape.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                if (shape.type == DrawMode.polygon)
                  Text(
                    '${GeoCalculator.formatArea(shape.areaHectares)} · ${shape.points.length} pts',
                    style: TextStyle(color: shape.color, fontSize: 11),
                  ),
              ],
            ),
          ),
          const Icon(Icons.expand_less_rounded,
              color: AppTheme.textSecondary, size: 18),
        ],
      ),
    );
  }
}

/// Waypoint side panel
class _WaypointPanel extends StatelessWidget {
  final List<Map<String, dynamic>> waypoints;
  final String shapeName;
  final VoidCallback onClose;
  final void Function(Map<String, dynamic>) onWaypointTap;
  final VoidCallback? onPrint;
  final VoidCallback? onExportKml;

  const _WaypointPanel({
    required this.waypoints,
    required this.shapeName,
    required this.onClose,
    required this.onWaypointTap,
    this.onPrint,
    this.onExportKml,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: AppTheme.bgCard,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                border: Border(
                    bottom: BorderSide(color: AppTheme.borderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
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
                    child: const Icon(Icons.close_rounded,
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
                    width: 42,
                    child: Text('WPT',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Text('Latitude / Longitude',
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
                  ? const _EmptyWaypointState()
                  : ListView.builder(
                      itemCount: waypoints.length,
                      itemBuilder: (_, i) {
                        final wp = waypoints[i];
                        return _WaypointRow(
                          wp: wp,
                          isEven: i % 2 == 0,
                          onTap: () => onWaypointTap(wp),
                        );
                      },
                    ),
            ),

            // Footer actions
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                border:
                    Border(top: BorderSide(color: AppTheme.borderColor)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.place_rounded,
                          color: AppTheme.textMuted, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '${waypoints.length} waypoints',
                        style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.print_rounded,
                          label: 'Print Map',
                          color: AppTheme.infoColor,
                          onTap: onPrint,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.download_rounded,
                          label: 'Save KML',
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

class _EmptyWaypointState extends StatelessWidget {
  const _EmptyWaypointState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pentagon_outlined,
                color: AppTheme.textMuted, size: 40),
            SizedBox(height: 12),
            Text(
              'Tap Polygon in toolbar\nthen tap on the map\nto add waypoints',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaypointRow extends StatelessWidget {
  final Map<String, dynamic> wp;
  final bool isEven;
  final VoidCallback onTap;

  const _WaypointRow({
    required this.wp,
    required this.isEven,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lat = (wp['lat'] as double).toStringAsFixed(6);
    final lng = (wp['lng'] as double).toStringAsFixed(6);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isEven
              ? Colors.transparent
              : const Color(0xFF0D1B2A).withValues(alpha: 0.6),
          border: Border(
            bottom: BorderSide(
                color: AppTheme.borderColor.withValues(alpha: 0.35)),
          ),
        ),
        child: Row(
          children: [
            // Yellow badge
            Container(
              width: 42,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.yellow,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.black26),
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
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'N $lat°',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 9.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'E $lng°',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
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

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionBtn({
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
                  ? color.withValues(alpha: 0.5)
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

/// Shapes list bottom sheet
class _ShapesListSheet extends StatelessWidget {
  final MapController controller;
  final void Function(DrawnShape) onShapeTap;

  const _ShapesListSheet({
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
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.layers_rounded, color: AppTheme.greenAccent, size: 20),
              SizedBox(width: 8),
              Text('Drawn Shapes',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
        ),
        if (shapes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.draw_rounded, color: AppTheme.textMuted, size: 52),
                SizedBox(height: 12),
                Text('No shapes drawn yet',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                SizedBox(height: 4),
                Text('Use the bottom toolbar to draw polygons',
                    style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 12)),
              ],
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: shapes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                          ? Icons.pentagon_rounded
                          : s.type == DrawMode.path
                              ? Icons.polyline_rounded
                              : Icons.place_rounded,
                      color: s.color,
                      size: 18,
                    ),
                  ),
                  title: Text(s.name,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    s.type == DrawMode.polygon
                        ? '${s.points.length} pts · ${GeoCalculator.formatArea(s.areaHectares)}'
                        : s.type == DrawMode.path
                            ? GeoCalculator.formatPerimeter(s.perimeterMeters)
                            : '${s.points.first.latitude.toStringAsFixed(5)}, ${s.points.first.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textMuted, size: 18),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Offline download mode overlay
class _OfflineOverlay extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onDownload;

  const _OfflineOverlay({
    required this.onCancel,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download_rounded,
                        color: AppTheme.greenAccent, size: 18),
                    SizedBox(width: 8),
                    Text('Pan & zoom to frame the download area',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              ),
              const Spacer(),
              Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.75,
                  height: MediaQuery.of(context).size.width * 0.75,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppTheme.greenAccent, width: 2.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20)),
                  border: Border(
                      top: BorderSide(color: AppTheme.borderColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onDownload,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.greenPrimary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
