import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../duty_diary/duty_diary_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gal/gal.dart';
import 'package:exif/exif.dart';
import '../../shared/theme.dart';
import '../../shared/compass_widget.dart';
import '../../shared/compass_widget.dart';
import '../../core/database/db_helper.dart';
import '../../core/models/kml_file_model.dart';
import '../../core/models/village_model.dart';
import '../../core/models/polygon_model.dart';
import '../../core/utils/geo_calculator.dart';
import '../../core/utils/kml_engine.dart';
import '../../core/utils/pdf_generator.dart';
import 'map_controller.dart';
import 'widgets/draw_toolbar.dart';
import 'widgets/layer_panel.dart';
import 'widgets/shape_detail_sheet.dart';
import '../calculators/cbm_screen.dart';

import '../offline_maps/offline_maps_screen.dart';
import 'offline_tile_provider.dart';
import 'geo_reference_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

// ignore: library_private_types_in_public_api
class MapScreenState extends State<MapScreen> {
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

  // GPS live position dot
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStream;

  // Tapped coordinate (for collecting lat/lng from map)
  LatLng? _tappedPosition;

  String? _appDocDir;

  // Geo-referenced PDF overlay images
  final List<GeoReferencedImage> _geoRefImages = [];

  @override
  void initState() {
    super.initState();
    _flutterMapController = fmap.MapController();
    _loadData();
    // Load persisted shapes from DB
    _mapController.loadFromDatabase();
    // Auto-navigate to current location on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _goToCurrentLocation();
      _startLocationStream();
    });
  }

  /// Called by MainScaffold when switching back to Map tab from KML tab.
  /// Re-parses all visible KML/KMZ files and reloads them on the map.
  Future<void> reloadKmlLayers() async {
    try {
      final db = DbHelper();
      final kmlFiles = await db.getAllKmlFiles();
      final allShapes = <KmlShape>[];
      for (final kf in kmlFiles) {
        if (!kf.isVisible) continue;
        try {
          final shapes = await KmlEngine.parseFile(kf.filepath);
          final coloredShapes = shapes
              .map((s) => s.copyWith(color: kf.layerColor, opacity: kf.opacity))
              .toList();
          allShapes.addAll(coloredShapes);
        } catch (_) {}
      }
      if (mounted) {
        _mapController.loadKmlShapes(allShapes);
        setState(() {});
      }
    } catch (_) {}
  }

  /// Start continuous GPS position stream for the blue dot + live tracking
  void _startLocationStream() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      
      _positionStream?.cancel(); // Cancel any existing stream
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3, // update every 3 metres
        ),
      ).listen((pos) {
        final pt = LatLng(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() => _currentPosition = pt);
          // Feed into live tracker if active
          _mapController.addTrackingPoint(pt);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadData() async {
    final docDir = await getApplicationDocumentsDirectory();
    final db = DbHelper();
    final villages = await db.getAllVillages();
    final polygons = await db.getAllPolygons();
    // Load saved KML files and show on map
    final kmlFiles = await db.getAllKmlFiles();
    final allShapes = <KmlShape>[];
    for (final kf in kmlFiles) {
      if (!kf.isVisible) continue;
      try {
        final shapes = await KmlEngine.parseFile(kf.filepath);
        final coloredShapes = shapes
            .map((s) => s.copyWith(color: kf.layerColor, opacity: kf.opacity))
            .toList();
        allShapes.addAll(coloredShapes);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _appDocDir = docDir.path;
        _villages = villages;
        _savedPolygons = polygons;
      });
      if (allShapes.isNotEmpty) {
        _mapController.loadKmlShapes(allShapes);
      }
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
      
      // Ensure the location stream is running now that we have permission
      if (_positionStream == null) {
        _startLocationStream();
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
      setState(() => _tappedPosition = null);
    }
  }

  /// Long-press on map → collect coordinates at that point
  void _onMapLongPress(fmap.TapPosition tapPos, LatLng latLng) {
    setState(() => _tappedPosition = latLng);
    // Show a snackbar with copy option
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'N ${latLng.latitude.toStringAsFixed(6)}  E ${latLng.longitude.toStringAsFixed(6)}',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Add Marker',
          textColor: AppTheme.greenAccent,
          onPressed: () {
            _mapController.addPoint(latLng);
            setState(() => _tappedPosition = null);
          },
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  // ── Polygon title + part dialog ──────────────────────────────────────────
  Future<Map<String, dynamic>?> _showPolygonTitleDialog() async {
    final titleCtrl = TextEditingController(
        text:
            'Survey ${_mapController.drawnShapes.where((s) => s.type == DrawMode.polygon).length + 1}');
    String selectedPart = 'None';
    final parts = ['None', 'Part 1', 'Part 2', 'Part 3', 'Part 4', 'Part 5'];

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.pentagon_rounded,
                  color: AppTheme.greenAccent, size: 22),
              SizedBox(width: 8),
              Text('Polygon Details',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title field
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Map Title',
                  hintText: 'e.g. Survey Field A',
                  prefixIcon: const Icon(Icons.title_rounded, size: 18),
                  filled: true,
                  fillColor: AppTheme.bgSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.greenPrimary, width: 2),
                  ),
                  labelStyle: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
              // Part selector
              DropdownButtonFormField<String>(
                value: selectedPart,
                dropdownColor: AppTheme.bgCard,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Polygon Part',
                  prefixIcon: const Icon(Icons.layers_rounded, size: 18),
                  filled: true,
                  fillColor: AppTheme.bgSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.greenPrimary, width: 2),
                  ),
                  labelStyle: const TextStyle(color: AppTheme.textSecondary),
                ),
                items: parts
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p),
                        ))
                    .toList(),
                onChanged: (v) => setLocal(() => selectedPart = v ?? 'None'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final title = titleCtrl.text.trim().isEmpty
                    ? 'Polygon'
                    : titleCtrl.text.trim();
                final fullName =
                    selectedPart == 'None' ? title : '$title - $selectedPart';
                Navigator.pop(ctx, {'name': fullName, 'part': selectedPart});
              },
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Save Polygon'),
            ),
          ],
        ),
      ),
    );
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
        color: AppTheme.greenPrimary.withValues(alpha: 0.15),
        borderColor: AppTheme.greenAccent,
        borderStrokeWidth: 4.0,
        isDotted: true,
      ));
    }

    if (_mapController.showPolygonLayer) {
      for (final shape in _mapController.drawnShapes) {
        if (shape.type == DrawMode.polygon) {
          final isSelected = _mapController.selectedShape?.id == shape.id;
          polygons.add(fmap.Polygon(
            points: shape.points,
            color: shape.color.withValues(alpha: isSelected ? 0.35 : 0.22),
            borderColor: isSelected ? Colors.white : shape.color,
            borderStrokeWidth: isSelected ? 5.0 : 4.0,
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
          final cColor = Color(int.parse(kmlShape.color.replaceAll('#', '0xFF')));
          final fillAlpha = (kmlShape.opacity * 0.35).clamp(0.0, 1.0);
          polygons.add(fmap.Polygon(
            points: pts,
            color: cColor.withValues(alpha: fillAlpha),
            borderColor: cColor.withValues(alpha: kmlShape.opacity),
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
          final cColor = Color(int.parse(kmlShape.color.replaceAll('#', '0xFF')));
          lines.add(fmap.Polyline(
            points: kmlShape.coordinates
                .map((c) => LatLng(c['lat']!, c['lng']!))
                .toList(),
            color: cColor.withValues(alpha: kmlShape.opacity),
            strokeWidth: 3,
          ));
        }
      }
    }

    return lines;
  }

  List<fmap.OverlayImage> _buildKmlOverlays() {
    if (!_mapController.showKmlLayer) return [];
    final overlays = <fmap.OverlayImage>[];
    for (final shape in _mapController.kmlShapes) {
      if (shape.type == 'overlay' &&
          shape.north != null &&
          shape.south != null &&
          shape.east != null &&
          shape.west != null &&
          shape.imageUrl != null) {
        final imgFile = File(shape.imageUrl!);
        if (!imgFile.existsSync()) continue; // skip if image not found
        overlays.add(
          fmap.OverlayImage(
            bounds: fmap.LatLngBounds(
              LatLng(shape.south!, shape.west!), // SW
              LatLng(shape.north!, shape.east!), // NE
            ),
            imageProvider: FileImage(imgFile),
            opacity: shape.opacity,
          ),
        );
      }
    }
    return overlays;
  }

  /// Returns a fallback polygon for overlays whose image failed to load.
  /// Draws a visible semi-transparent rectangle so user sees the KMZ area.
  List<fmap.Polygon> _buildOverlayFallbackPolygons() {
    if (!_mapController.showKmlLayer) return [];
    final polys = <fmap.Polygon>[];
    for (final shape in _mapController.kmlShapes) {
      if (shape.type == 'overlay' &&
          shape.north != null &&
          shape.south != null &&
          shape.east != null &&
          shape.west != null &&
          (shape.imageUrl == null || !File(shape.imageUrl!).existsSync())) {
        polys.add(fmap.Polygon(
          points: [
            LatLng(shape.north!, shape.west!),
            LatLng(shape.north!, shape.east!),
            LatLng(shape.south!, shape.east!),
            LatLng(shape.south!, shape.west!),
          ],
          color: const Color(0x330000FF),
          borderColor: const Color(0xFF0000FF),
          borderStrokeWidth: 2.0,
          label: shape.name,
          labelStyle: const TextStyle(
            color: Color(0xFF0000FF),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ));
      }
    }
    return polys;
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
        child: _WaypointPin(
            label: label, color: AppTheme.greenAccent, isActive: true),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
        if (shape.type == DrawMode.path) {
          if (shape.points.isNotEmpty) {
            final pt = shape.points.last;
            markers.add(fmap.Marker(
              point: pt,
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () {
                  _mapController.selectShape(shape);
                  _showShapeDetail();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                    border: Border.all(color: shape.color, width: 2),
                  ),
                  child: Icon(Icons.share, color: shape.color, size: 20),
                ),
              ),
            ));
          }
        }
      }
    }

    if (_mapController.showKmlLayer) {
      for (final kmlShape in _mapController.kmlShapes) {
        if (kmlShape.type == 'marker' && kmlShape.coordinates.isNotEmpty) {
          final cColor = Color(int.parse(kmlShape.color.replaceAll('#', '0xFF')));
          markers.add(fmap.Marker(
            point: LatLng(kmlShape.coordinates.first['lat']!,
                kmlShape.coordinates.first['lng']!),
            width: 30,
            height: 30,
            child: Icon(Icons.room, color: cColor, size: 30),
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
    if (_mapController.drawMode == DrawMode.polygon)
      return 'Drawing Polygon...';
              if (_mapController.selectedShape != null) {
      return _mapController.selectedShape!.name;
    }
    final poly = _mapController.drawnShapes
        .where((s) => s.type == DrawMode.polygon)
        .lastOrNull;
    return poly?.name ?? 'No Polygon';
  }

  // ── Import KML / GeoJSON file ───────────────────────────────────────────────

  Future<void> _importKmlFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['kml', 'kmz', 'json', 'geojson', 'shp'],
      );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      final path = pickedFile.path;
      if (path == null) return;

      _showSnackBar('Importing ${pickedFile.name}…');

      // Copy file to app directory FIRST so extracted KMZ images can be saved alongside it
      final dir = await getApplicationDocumentsDirectory();
      final destPath = '${dir.path}/${pickedFile.name}';
      await File(path).copy(destPath);

      List<KmlShape> shapes = [];
      final ext = pickedFile.extension?.toLowerCase() ?? '';
      if (ext == 'json' || ext == 'geojson') {
        final content = await File(destPath).readAsString();
        shapes = KmlEngine.parseGeoJson(content);
      } else {
        shapes = await KmlEngine.parseFile(destPath);
      }

      if (shapes.isEmpty) {
        if (mounted) _showSnackBar('No shapes found in file', isError: true);
        // Clean up copied file if parsing failed
        try { await File(destPath).delete(); } catch (_) {}
        return;
      }

      // Add to map & auto-enable KML layer
      _mapController.addKmlShapes(shapes);
      if (!_mapController.showKmlLayer) {
        _mapController.toggleKmlLayer();
      }

      // Save to DB
      await DbHelper().insertKmlFile(KmlFileModel(
        filename: pickedFile.name,
        filepath: destPath,
        layerColor: '#2EA043',
        createdAt: DateTime.now().toIso8601String(),
      ));

      // Calculate bounding box and zoom to fit ALL coordinates (like Google Earth)
      double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
      bool hasBounds = false;
      for (final shape in shapes) {
        // For vector shapes (polygons, paths, markers)
        for (final c in shape.coordinates) {
          final lat = c['lat']!;
          final lng = c['lng']!;
          if (lat < minLat) minLat = lat;
          if (lat > maxLat) maxLat = lat;
          if (lng < minLng) minLng = lng;
          if (lng > maxLng) maxLng = lng;
          hasBounds = true;
        }
        // For GroundOverlay (image maps) - use the lat/lon bounding box
        if (shape.type == 'overlay' &&
            shape.north != null &&
            shape.south != null &&
            shape.east != null &&
            shape.west != null) {
          if (shape.south! < minLat) minLat = shape.south!;
          if (shape.north! > maxLat) maxLat = shape.north!;
          if (shape.west! < minLng) minLng = shape.west!;
          if (shape.east! > maxLng) maxLng = shape.east!;
          hasBounds = true;
        }
      }

      if (hasBounds && minLat <= maxLat && minLng <= maxLng) {
        final sw = LatLng(minLat, minLng);
        final ne = LatLng(maxLat, maxLng);
        final bounds = fmap.LatLngBounds(sw, ne);
        _flutterMapController.fitBounds(
          bounds,
          options: const fmap.FitBoundsOptions(
            padding: EdgeInsets.all(50),
            maxZoom: 18,
          ),
        );
      }

      if (mounted) {
        _showSnackBar(
            'Imported ${shapes.length} shape(s) from ${pickedFile.name}');
      }
    } catch (e) {
      if (mounted) _showSnackBar('Import failed: $e', isError: true);
    }
  }

  // ── Export GPS tracking path as KML ────────────────────────────────────────

  Future<void> _exportTrackingKml(DrawnShape shape) async {
    try {
      final coords = [
        ...shape.points.map((p) => '${p.longitude},${p.latitude},0'),
      ].join('\n          ');

      final kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${shape.name}</name>
    <Style id="trackStyle">
      <LineStyle><color>ff006FFF</color><width>4</width></LineStyle>
    </Style>
    <Placemark>
      <name>${shape.name}</name>
      <description>Distance: ${GeoCalculator.formatPerimeter(shape.perimeterMeters)} · ${shape.points.length} points</description>
      <styleUrl>#trackStyle</styleUrl>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>$coords</coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';

      final dir = await getApplicationDocumentsDirectory();
      final safe = shape.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final file = File('${dir.path}/$safe.kml');
      await file.writeAsString(kml);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.google-earth.kml+xml')],
        subject: '${shape.name} — GPS Track KML',
        text:
            'GPS Track: ${GeoCalculator.formatPerimeter(shape.perimeterMeters)}',
      );

      if (mounted) {
        _showSnackBar(
            'GPS track saved & shared (${GeoCalculator.formatPerimeter(shape.perimeterMeters)})');
      }
    } catch (e) {
      if (mounted) _showSnackBar('KML export failed: $e', isError: true);
    }
  }

  // ── Manual Coordinate Entry ─────────────────────────────────────────────────

  Future<void> _showManualCoordinateEntry() async {
    // Each entry is {lat, lng}
    final List<Map<String, double>> coords = [];
    final nameCtrl = TextEditingController(text: 'Manual Polygon');
    bool asClosed = true; // close polygon vs leave as path

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final latCtrl = TextEditingController();
          final lngCtrl = TextEditingController();

          void addPoint() {
            final lat = double.tryParse(latCtrl.text.trim());
            final lng = double.tryParse(lngCtrl.text.trim());
            if (lat == null || lng == null) return;
            if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return;
            setLocal(() => coords.add({'lat': lat, 'lng': lng}));
            latCtrl.clear();
            lngCtrl.clear();
          }

          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.edit_location_alt_rounded,
                    color: AppTheme.greenAccent, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Manual Coordinates',
                      style:
                          TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
                ),
                // Close as polygon / path toggle
                Row(
                  children: [
                    Text('Polygon',
                        style: TextStyle(
                            color: asClosed
                                ? AppTheme.greenAccent
                                : AppTheme.textMuted,
                            fontSize: 11)),
                    Switch(
                      value: asClosed,
                      activeColor: AppTheme.greenPrimary,
                      onChanged: (v) => setLocal(() => asClosed = v),
                    ),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name field
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13),
                    decoration:
                        _inputDeco('Polygon / Path Name', Icons.label_rounded),
                  ),
                  const SizedBox(height: 6),
                  // Coordinate entry row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13),
                          decoration:
                              _inputDeco('Latitude', Icons.north_rounded),
                          onSubmitted: (_) => addPoint(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lngCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13),
                          decoration:
                              _inputDeco('Longitude', Icons.east_rounded),
                          onSubmitted: (_) => addPoint(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: addPoint,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.greenPrimary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Point list
                  if (coords.isNotEmpty) ...[
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: coords.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, color: AppTheme.borderColor),
                        itemBuilder: (_, i) {
                          final pt = coords[i];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: AppTheme.greenPrimary,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Center(
                                child: Text(
                                  (i + 1).toString().padLeft(2, '0'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            title: Text(
                              'N ${pt['lat']!.toStringAsFixed(6)}',
                              style: const TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 12),
                            ),
                            subtitle: Text(
                              'E ${pt['lng']!.toStringAsFixed(6)}',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red, size: 18),
                              onPressed: () =>
                                  setLocal(() => coords.removeAt(i)),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppTheme.textMuted, size: 14),
                        const SizedBox(width: 4),
                        Text('${coords.length} point(s) entered',
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 11)),
                      ],
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Enter lat/lng and tap + to add points',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              // Create on map only
              if (coords.length >= 2)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _createShapeFromCoords(
                        coords, nameCtrl.text.trim(), asClosed);
                  },
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: const Text('Add to Map'),
                ),
              // Create + export KML
              if (coords.length >= 2)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _createShapeFromCoords(
                        coords, nameCtrl.text.trim(), asClosed,
                        exportKml: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        AppTheme.greenPrimary.withValues(alpha: 0.85),
                  ),
                  icon: const Icon(Icons.save_alt_rounded, size: 16),
                  label: const Text('Add + KML'),
                ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 16, color: AppTheme.textMuted),
        filled: true,
        fillColor: AppTheme.bgSurface,
        labelStyle:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.borderColor)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.borderColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: AppTheme.greenPrimary, width: 2)),
      );

  /// Create a DrawnShape from manually entered coordinates
  void _createShapeFromCoords(
    List<Map<String, double>> coords,
    String name,
    bool asClosed, {
    bool exportKml = false,
  }) {
    final pts = coords.map((c) => LatLng(c['lat']!, c['lng']!)).toList();
    final pointMaps = coords.toList();

    final perimeter = GeoCalculator.calculatePerimeterMeters(pointMaps);
    final area = asClosed && pts.length >= 3
        ? GeoCalculator.calculateAreaHectares(pointMaps)
        : 0.0;

    final shape = DrawnShape(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isEmpty ? (asClosed ? 'Manual Polygon' : 'Manual Path') : name,
      type: asClosed && pts.length >= 3 ? DrawMode.polygon : DrawMode.path,
      points: pts,
      areaHectares: area,
      perimeterMeters: perimeter,
      color: asClosed ? const Color(0xFF2EA043) : const Color(0xFF388BFD),
    );

    // Add to map
    _mapController.addManualShape(shape);

    // Zoom to first point
    _flutterMapController.move(pts.first, 15);
    _showSnackBar('${shape.name} created (${pts.length} points)');

    // Export KML if requested
    if (exportKml) {
      _exportManualKml(shape, coords, asClosed);
    }
  }

  Future<void> _exportManualKml(
      DrawnShape shape, List<Map<String, double>> coords, bool asClosed) async {
    try {
      final pts = coords.map((c) => '${c['lng']},${c['lat']},0').toList();
      // Close polygon by repeating first point
      if (asClosed && pts.isNotEmpty) pts.add(pts.first);
      final coordStr = pts.join('\n          ');

      final wpPlacemarks = coords.mapIndexed((i, c) => '''    <Placemark>
      <name>${(i + 1).toString().padLeft(3, '0')}</name>
      <description>Lat: ${c['lat']!.toStringAsFixed(6)}, Lng: ${c['lng']!.toStringAsFixed(6)}</description>
      <Style>
        <IconStyle><color>ff000000</color><scale>0.6</scale>
          <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_square.png</href></Icon>
        </IconStyle>
      </Style>
      <Point><coordinates>${c['lng']},${c['lat']},0</coordinates></Point>
    </Placemark>''').join('\n');

      final geomTag = asClosed && coords.length >= 3
          ? '<Polygon>\n        <outerBoundaryIs><LinearRing>\n          <coordinates>$coordStr</coordinates>\n        </LinearRing></outerBoundaryIs>\n      </Polygon>'
          : '<LineString>\n        <tessellate>1</tessellate>\n        <coordinates>$coordStr</coordinates>\n      </LineString>';

      final kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${shape.name}</name>
    <Style id="s">
      <LineStyle><color>ff2EA043</color><width>3</width></LineStyle>
      <PolyStyle><color>302EA043</color></PolyStyle>
    </Style>
    <Placemark>
      <name>${shape.name}</name>
      <styleUrl>#s</styleUrl>
      $geomTag
    </Placemark>
$wpPlacemarks
  </Document>
</kml>''';

      final dir = await getApplicationDocumentsDirectory();
      final safe = shape.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final file = File('${dir.path}/$safe.kml');
      await file.writeAsString(kml);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.google-earth.kml+xml')],
        subject: '${shape.name} - KML',
      );

      if (mounted) _showSnackBar('KML exported: ${shape.name}');
    } catch (e) {
      if (mounted) _showSnackBar('KML export failed: $e', isError: true);
    }
  }

  // ── Print Dialog ────────────────────────────────────────────────────────────

  Future<void> _printPolygon(
      List<Map<String, dynamic>> waypoints, String name) async {
    if (!mounted) return;

    // Collect all polygon parts for potential multi-part printing
    final allPolygons = _mapController.drawnShapes
        .where((s) => s.type == DrawMode.polygon)
        .toList();

    // Prepare print settings dialog
    final titleCtrl = TextEditingController(text: name);
    final orgCtrl = TextEditingController(text: '');
    final now = DateTime.now();
    final dateCtrl = TextEditingController(
      text:
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}  '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    );
    bool printAllParts = allPolygons.length > 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.print_rounded, color: AppTheme.greenAccent, size: 22),
              SizedBox(width: 8),
              Text('Print Options',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Report title
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Report Title',
                      hintText: 'Title printed on the PDF',
                      prefixIcon: const Icon(Icons.title_rounded, size: 18),
                      filled: true,
                      fillColor: AppTheme.bgSurface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppTheme.borderColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppTheme.borderColor)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppTheme.greenPrimary, width: 2)),
                      labelStyle:
                          const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Organization name (optional — leave blank to hide)
                  TextField(
                    controller: orgCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Organization Name (optional)',
                      hintText: 'Leave blank to hide from header',
                      prefixIcon: const Icon(Icons.business_rounded, size: 18),
                      filled: true,
                      fillColor: AppTheme.bgSurface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppTheme.borderColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppTheme.borderColor)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppTheme.greenPrimary, width: 2)),
                      labelStyle:
                          const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Date/time — editable
                  TextField(
                    controller: dateCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Date & Time',
                      prefixIcon:
                          const Icon(Icons.calendar_today_rounded, size: 18),
                      filled: true,
                      fillColor: AppTheme.bgSurface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppTheme.borderColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppTheme.borderColor)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppTheme.greenPrimary, width: 2)),
                      labelStyle:
                          const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  // Multi-part toggle (only shown when multiple polygons exist)
                  if (allPolygons.length > 1) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.layers_rounded,
                              color: AppTheme.greenAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Print all ${allPolygons.length} parts on same page',
                              style: const TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 13),
                            ),
                          ),
                          Switch(
                            value: printAllParts,
                            activeColor: AppTheme.greenPrimary,
                            onChanged: (v) => setLocal(() => printAllParts = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.print_rounded, size: 16),
              label: const Text('Generate PDF'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      _showSnackBar('Generating PDF...');

      // Build parts list
      final List<PolygonPart> parts;
      if (printAllParts && allPolygons.length > 1) {
        parts = allPolygons
            .map((shape) => PolygonPart(
                  name: shape.name,
                  points: shape.points
                      .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                      .toList(),
                  areaHectares: shape.areaHectares,
                  perimeterMeters: shape.perimeterMeters,
                ))
            .toList();
      } else {
        final pts = waypoints
            .map((w) => {'lat': w['lat'] as double, 'lng': w['lng'] as double})
            .toList();
        final shape = _mapController.selectedShape ??
            _mapController.drawnShapes
                .where((s) => s.type == DrawMode.polygon)
                .lastOrNull;
        parts = [
          PolygonPart(
            name: name,
            points: pts,
            areaHectares:
                shape?.areaHectares ?? GeoCalculator.calculateAreaHectares(pts),
            perimeterMeters: shape?.perimeterMeters ??
                GeoCalculator.calculatePerimeterMeters(pts),
          ),
        ];
      }

      final path = await PdfGenerator.generatePolygonPdf(
        parts: parts,
        reportTitle:
            titleCtrl.text.trim().isEmpty ? name : titleCtrl.text.trim(),
        orgName: orgCtrl.text.trim(),
        customDate: dateCtrl.text.trim().isEmpty ? null : dateCtrl.text.trim(),
      );
      final pdfBytes = await File(path).readAsBytes();
      await Printing.layoutPdf(onLayout: (_) => pdfBytes);
    } catch (e) {
      if (mounted) _showSnackBar('Print failed: $e', isError: true);
    }
  }

  // ── KML Export (all parts combined) ──────────────────────────────────────

  Future<void> _exportKml(
      List<Map<String, dynamic>> waypoints, String name) async {
    try {
      // Check if there are multiple polygon parts to combine
      final allPolygons = _mapController.drawnShapes
          .where((s) => s.type == DrawMode.polygon)
          .toList();

      final String kml;
      final String exportName;

      if (allPolygons.length > 1) {
        // Ask user: export current only, or all parts
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: const Text('KML Export',
                style: TextStyle(color: AppTheme.textPrimary)),
            content: Text(
              '${allPolygons.length} polygon parts found.\nExport all parts in one KML file?',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'current'),
                child: const Text('Current Only'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'all'),
                child: const Text('All Parts'),
              ),
            ],
          ),
        );
        if (choice == null || !mounted) return;
        if (choice == 'all') {
          kml = _buildMultiPartKml(allPolygons);
          exportName = '$name (All Parts)';
        } else {
          final pts = waypoints
              .map(
                  (w) => {'lat': w['lat'] as double, 'lng': w['lng'] as double})
              .toList();
          kml = _buildFullKml(name, pts, waypoints);
          exportName = name;
        }
      } else {
        final pts = waypoints
            .map((w) => {'lat': w['lat'] as double, 'lng': w['lng'] as double})
            .toList();
        kml = _buildFullKml(name, pts, waypoints);
        exportName = name;
      }

      final dir = await getApplicationDocumentsDirectory();
      final safeName = exportName.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final file = File('${dir.path}/$safeName.kml');
      await file.writeAsString(kml);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.google-earth.kml+xml')],
        subject: '$exportName - KML File',
        text: 'KML file: $exportName',
      );

      if (mounted) _showSnackBar('KML ready — choose where to save/share');
    } catch (e) {
      if (mounted) _showSnackBar('KML export failed: $e', isError: true);
    }
  }

  /// Build a single KML combining multiple polygon parts
  String _buildMultiPartKml(List<DrawnShape> shapes) {
    final styleColors = [
      'ff2EA043',
      'ff1565C0',
      'ffC62828',
      'ffE65100',
      'ff6A1B9A'
    ];
    final placemarks = <String>[];

    for (int pi = 0; pi < shapes.length; pi++) {
      final shape = shapes[pi];
      if (shape.points.isEmpty) continue;
      final colorHex = styleColors[pi % styleColors.length];
      final coords = [
        ...shape.points.map((p) => '${p.longitude},${p.latitude},0'),
        '${shape.points.first.longitude},${shape.points.first.latitude},0',
      ].join('\n              ');

      placemarks.add('''    <Style id="style$pi">
      <LineStyle><color>$colorHex</color><width>3</width></LineStyle>
      <PolyStyle><color>30${colorHex.substring(2)}</color></PolyStyle>
    </Style>
    <Placemark>
      <name>${shape.name}</name>
      <styleUrl>#style$pi</styleUrl>
      <Polygon>
        <outerBoundaryIs><LinearRing>
          <coordinates>$coords</coordinates>
        </LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>''');

      // Waypoint placemarks for each vertex
      for (int i = 0; i < shape.points.length; i++) {
        final p = shape.points[i];
        final label = (i + 1).toString().padLeft(3, '0');
        placemarks.add('''    <Placemark>
      <name>$label</name>
      <description>${shape.name} · Lat: ${p.latitude.toStringAsFixed(6)}, Lng: ${p.longitude.toStringAsFixed(6)}</description>
      <Style>
        <IconStyle><color>ff000000</color><scale>0.6</scale>
          <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_square.png</href></Icon>
        </IconStyle>
      </Style>
      <Point><coordinates>${p.longitude},${p.latitude},0</coordinates></Point>
    </Placemark>''');
      }
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Multi-Part Survey</name>
${placemarks.join('\n')}
  </Document>
</kml>''';
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

        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) async {
            if (didPop) return;
            final shouldExit = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppTheme.bgCard,
                title: const Text('Exit App', style: TextStyle(color: Colors.white)),
                content: const Text('Are you sure you want to exit the app?', style: TextStyle(color: AppTheme.textSecondary)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('OK', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            );
            if (shouldExit == true) {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          // Fixed bottom toolbar — always visible
          bottomNavigationBar: DrawToolbar(
            controller: _mapController,
            onPolygonClose: () async {
              final result = await _showPolygonTitleDialog();
              if (result == null) return null; // cancelled
              return result['name'] as String;
            },
            onExtractPhotos: _extractPhotosToMap,
          ),
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
                      onLongPress: _onMapLongPress,
                      interactionOptions: const fmap.InteractionOptions(
                        flags: fmap.InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      if (_appDocDir != null)
                        fmap.TileLayer(
                          urlTemplate: _mapController.mapStyle == 'Satellite'
                              ? 'https://mt0.google.com/vt/lyrs=s&x={x}&y={y}&z={z}'
                              : _mapController.mapStyle == 'Hybrid'
                                  ? 'https://mt0.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.kashi.kashi_geofield_pro',
                          maxZoom: 20,
                          maxNativeZoom: 20,
                          tileProvider: OfflineTileProvider(
                            baseDir: _appDocDir!,
                            isSatellite: _mapController.mapStyle == 'Satellite' || _mapController.mapStyle == 'Hybrid',
                          ),
                        ),
                      // Geo-referenced PDF overlay images
                      if (_geoRefImages.isNotEmpty)
                        fmap.OverlayImageLayer(
                          overlayImages: _geoRefImages
                              .map((img) => fmap.OverlayImage(
                                    bounds: fmap.LatLngBounds(
                                      img.bottomRight,
                                      img.topLeft,
                                    ),
                                    imageProvider: MemoryImage(img.imageBytes),
                                    opacity: 0.75,
                                  ))
                              .toList(),
                        ),
                      // KML GroundOverlays (Image Maps)
                      Builder(builder: (ctx) {
                        final kmlOverlays = _buildKmlOverlays();
                        if (kmlOverlays.isEmpty) return const SizedBox.shrink();
                        return fmap.OverlayImageLayer(
                          overlayImages: kmlOverlays,
                        );
                      }),
                      // Fallback rectangles for overlays whose image couldn't load
                      Builder(builder: (ctx) {
                        final fallbacks = _buildOverlayFallbackPolygons();
                        if (fallbacks.isEmpty) return const SizedBox.shrink();
                        return fmap.PolygonLayer(polygons: fallbacks);
                      }),
                      fmap.PolygonLayer(polygons: _buildPolygons()),
                      fmap.PolylineLayer(polylines: _buildPolylines()),
                      // ── Live tracking path ─────────────────────────────────
                      if (_mapController.trackingPoints.length > 1)
                        fmap.PolylineLayer(
                          polylines: [
                            fmap.Polyline(
                              points: _mapController.trackingPoints,
                              color: const Color(0xFFFF6F00),
                              strokeWidth: 4.0,
                            ),
                          ],
                        ),
                      fmap.MarkerLayer(markers: _buildMarkers()),
                      // ── GPS blue dot ───────────────────────────────────────
                      if (_currentPosition != null)
                        fmap.MarkerLayer(
                          markers: [
                            fmap.Marker(
                              point: _currentPosition!,
                              width: 30,
                              height: 30,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF1565C0)
                                      .withValues(alpha: 0.25),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF1976D2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                    onClose: () => setState(() => _showWaypointPanel = false),
                    onWaypointTap: (wp) {
                      _flutterMapController.move(
                        LatLng(wp['lat'] as double, wp['lng'] as double),
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

              // ── GPS Live Tracking Panel ─────────────────────────────────────
              if (_mapController.trackingState != TrackingState.idle ||
                  _mapController.hasTracking)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _GpsTrackingPanel(
                      controller: _mapController,
                      onStop: () async {
                        final shape = _mapController.stopTracking();
                        if (shape != null) {
                          await _exportTrackingKml(shape);
                        }
                      },
                    ),
                  ),
                ),

              // ── Top: Tactical status bar + Search row ─────────────────
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Tactical Status Header ──────────────────────────────
                    Container(
                      color: AppTheme.bgSecondary.withValues(alpha: 0.92),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: Row(
                        children: [
                          // App name
                          const Text(
                            'KASHI GEOFIELD PRO',
                            style: TextStyle(
                              color: AppTheme.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const Spacer(),
                          // GPS indicator
                          Icon(
                            _currentPosition != null
                                ? Icons.gps_fixed_rounded
                                : Icons.gps_not_fixed_rounded,
                            color: _currentPosition != null
                                ? AppTheme.greenAccent
                                : AppTheme.warningColor,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _currentPosition != null ? 'GPS OK' : 'GPS...',
                            style: TextStyle(
                              color: _currentPosition != null
                                  ? AppTheme.greenAccent
                                  : AppTheme.warningColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Map style indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.borderBright, width: 1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              _mapController.mapStyle.toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 9,
                                letterSpacing: 1.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 1, color: AppTheme.borderBright),

                    // ── Search row ────────────────────────────────────────
                    Container(
                      color: AppTheme.bgSecondary.withValues(alpha: 0.85),
                      padding: EdgeInsets.only(
                        left: _showWaypointPanel ? 228 : 8,
                        right: 8,
                        top: 6,
                        bottom: 6,
                      ),
                      child: Row(
                        children: [
                          // Waypoint panel toggle
                          _RoundBtn(
                            icon: Icons.format_list_numbered_rounded,
                            tooltip: 'Waypoints',
                            isActive: _showWaypointPanel,
                            onTap: () => setState(
                                () => _showWaypointPanel = !_showWaypointPanel),
                          ),
                          const SizedBox(width: 6),
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
                          const SizedBox(width: 6),
                          // Layers toggle
                          _RoundBtn(
                            icon: Icons.layers_rounded,
                            tooltip: 'Layers',
                            isActive: _showLayerPanel,
                            onTap: () => setState(
                                () => _showLayerPanel = !_showLayerPanel),
                          ),
                          const SizedBox(width: 4),
                          // Shapes list
                          _RoundBtn(
                            icon: Icons.list_alt_rounded,
                            tooltip: 'Shapes',
                            isActive: false,
                            onTap: _showShapesList,
                          ),
                          const SizedBox(width: 4),
                          // Camera button
                          _RoundBtn(
                            icon: Icons.camera_alt_rounded,
                            tooltip: 'Capture Photo + GPS Tag',
                            isActive: false,
                            onTap: _openCameraScreen,
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
                top: 150,
                child: Column(
                  children: [
                    // Zoom in
                    _MapFab(
                      icon: Icons.add,
                      tooltip: 'Zoom In',
                      color: const Color(0xFF2D7A3A), // tactical green
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
                      color: const Color(0xFF2D7A3A), // tactical green
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
                      color: const Color(0xFF39D353), // bright green location
                      onTap: _loadingLocation ? null : _goToCurrentLocation,
                      isLoading: _loadingLocation,
                    ),
                    const SizedBox(height: 6),
                    // Download offline
                    _MapFab(
                      icon: Icons.download_rounded,
                      tooltip: 'Download Area',
                      color: const Color(0xFF29B6F6), // tactical blue
                      onTap: _onDownloadMapArea,
                    ),
                    const SizedBox(height: 6),
                    // GPS Track Start/Stop
                    _MapFab(
                      icon: _mapController.isTracking
                          ? Icons.pause_circle_rounded
                          : (_mapController.isTrackingPaused
                              ? Icons.play_circle_rounded
                              : Icons.directions_walk_rounded),
                      tooltip: _mapController.isTracking
                          ? 'Pause Tracking'
                          : (_mapController.isTrackingPaused
                              ? 'Resume Tracking'
                              : 'Start GPS Track'),
                      color: _mapController.isTracking
                          ? const Color(0xFFFF7043) // professional deep orange
                          : (_mapController.isTrackingPaused
                              ? const Color(0xFFFFA726) // professional amber
                              : const Color(0xFF7E57C2)), // professional indigo
                      onTap: () {
                        if (_mapController.isTracking) {
                          _mapController.pauseTracking();
                        } else if (_mapController.isTrackingPaused) {
                          _mapController.resumeTracking();
                        } else {
                          _mapController.startTracking();
                          _showSnackBar(
                              'GPS tracking started — walk to record path');
                        }
                      },
                    ),
                    if (_mapController.isTracking || _mapController.isTrackingPaused) ...[
                      const SizedBox(height: 6),
                      _MapFab(
                        icon: Icons.stop_circle_rounded,
                        tooltip: 'Stop Track',
                        color: AppTheme.errorColor,
                        onTap: () {
                          final shape = _mapController.stopTracking();
                          if (shape != null) {
                            _showSnackBar('Tracking saved: ${shape.name}');
                          } else {
                            _showSnackBar('Tracking stopped (no movement recorded)', isError: true);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Quick Import KML
                    _MapFab(
                      icon: Icons.upload_file_rounded,
                      tooltip: 'Import KML / GeoJSON',
                      color: const Color(0xFF26A69A), // tactical teal
                      onTap: _importKmlFile,
                    ),
                    const SizedBox(height: 6),
                    // Manual lat/lng entry
                    _MapFab(
                      icon: Icons.pin_drop_rounded,
                      tooltip: 'Enter Coordinates Manually',
                      color: const Color(0xFFEF5350), // tactical red
                      onTap: _showManualCoordinateEntry,
                    ),
                    const SizedBox(height: 6),
                    
                    // Duty Diary & Voice Assistant
                    _MapFab(
                      icon: Icons.mic_rounded,
                      tooltip: "Duty Diary & Voice Assistant",
                      color: Colors.orangeAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DutyDiaryScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    
                    // Forestry Calculator
                    _MapFab(
                      icon: Icons.calculate_rounded,
                      tooltip: 'Quarter Girth Calc',
                      color: const Color(0xFFAB47BC), // tactical purple
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CbmScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── Layer panel ──────────────────────────────────────────────────
              if (_showLayerPanel)
                Positioned(
                  right: 75,
                  top: 150,
                  child: LayerPanel(
                    controller: _mapController,
                    onClose: () => setState(() => _showLayerPanel = false),
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
                    child: _ShapeInfoBar(shape: _mapController.selectedShape!),
                  ),
                ),

              // ── GPS coordinate overlay (top-left corner) ──────────────────
              if (_currentPosition != null)
                Positioned(
                  left: 12,
                  top: 140,
                  child: _GpsCoordChip(position: _currentPosition!),
                ),

              // ── Tapped coordinate marker ──────────────────────────────────────
              if (_tappedPosition != null)
                Positioned(
                  top: 200,
                  left: 12,
                  child: _TappedCoordCard(
                    position: _tappedPosition!,
                    onClose: () => setState(() => _tappedPosition = null),
                    onAddMarker: () {
                      _mapController.addPoint(_tappedPosition!);
                      setState(() => _tappedPosition = null);
                    },
                  ),
                ),

              // ── Offline Download Overlay ─────────────────────────────────────
              _LiveDrawingMeasurementCard(controller: _mapController),
              if (_mapController.isOfflineDownloadMode)
                _OfflineOverlay(
                  onCancel: _mapController.toggleOfflineDownloadMode,
                  onDownload: _onDownloadMapArea,
                ),
            ],
          ),
        ));
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

  Future<void> _openCameraScreen() async {
    // Show name dialog ONLY ONCE before starting the camera loop
    final locationNameCtrl = TextEditingController();
    final shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1410),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppTheme.borderBright, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.camera_alt_rounded,
                color: AppTheme.greenAccent, size: 20),
            SizedBox(width: 8),
            Text(
              'ADD LOCATION NOTE',
              style: TextStyle(
                color: AppTheme.greenAccent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        content: TextField(
          controller: locationNameCtrl,
          autofocus: true,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: 'Optional — location or note',
            hintStyle: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.7)),
            filled: true,
            fillColor: AppTheme.bgSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  const BorderSide(color: AppTheme.borderColor, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  const BorderSide(color: AppTheme.borderColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  const BorderSide(color: AppTheme.greenAccent, width: 1.5),
            ),
            prefixIcon: const Icon(Icons.edit_note_rounded,
                color: AppTheme.greenAccent, size: 18),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.borderColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('CANCEL',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontFamily: 'monospace',
                      )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.greenPrimary,
                    foregroundColor: AppTheme.greenAccent,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(
                          color: AppTheme.greenAccent, width: 1),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded, size: 16),
                  label: const Text('START CAMERA',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.5,
                        fontFamily: 'monospace',
                      )),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (shouldProceed != true || !mounted) return;

    final name = locationNameCtrl.text.trim();
    int photoCount = 0;

    // ── Camera loop — keeps shooting until user cancels the camera intent ──
    while (mounted) {
      try {
        final picker = ImagePicker();
        final XFile? photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
        );
        if (photo == null) break; // user backed out of camera, end loop

        _showSnackBar('Saving photo...');

        final bytes = await photo.readAsBytes();

        String latStr = 'N/A';
        String lngStr = 'N/A';
        const String accStr = '3.0 m';
        if (_currentPosition != null) {
          latStr = _currentPosition!.latitude.toStringAsFixed(6);
          lngStr = _currentPosition!.longitude.toStringAsFixed(6);
        }

        final now = DateTime.now();
        final dateStr =
            '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final lines = <String>[
          'Latitude: $latStr',
          'Longitude: $lngStr',
          'Accuracy: $accStr',
          'Time: $dateStr',
        ];
        if (name.isNotEmpty) lines.add('Note: $name');

        // Draw watermark
        final ui.Image bgImage = await decodeImageFromList(bytes);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(bgImage, Offset.zero, Paint());

        final double fontSize = bgImage.height * 0.035;
        final double padding = fontSize * 0.6;
        final double boxWidth = bgImage.width * 0.65;

        final List<TextPainter> painters = [];
        double totalTextHeight = padding * 2;
        for (final line in lines) {
          final textStyle = TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.1,
          );
          final textPainter = TextPainter(
            text: TextSpan(text: line, style: textStyle),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout(maxWidth: boxWidth - padding * 2);
          painters.add(textPainter);
          totalTextHeight += textPainter.height + (fontSize * 0.15);
        }

        final bgRect = Rect.fromLTWH(
          0,
          bgImage.height.toDouble() - totalTextHeight - 10,
          boxWidth,
          totalTextHeight,
        );
        final bgPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.55);
        canvas.drawRect(bgRect, bgPaint);

        double currentDy = bgRect.top + padding;
        for (final painter in painters) {
          painter.paint(canvas, Offset(padding, currentDy));
          currentDy += painter.height + (fontSize * 0.15);
        }

        final picture = recorder.endRecording();
        final finalUiImage =
            await picture.toImage(bgImage.width, bgImage.height);
        final byteData =
            await finalUiImage.toByteData(format: ui.ImageByteFormat.png);
        final watermarkedBytes = byteData!.buffer.asUint8List();

        final dir = await getTemporaryDirectory();
        final filePath =
            '${dir.path}/watermarked_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(watermarkedBytes);

        await Gal.putImage(filePath, album: 'KashiGeoFieldPro');

        photoCount++;
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          _showSnackBar('Photo $photoCount saved ✓');
        }
      } catch (e) {
        if (mounted) _showSnackBar('Error: $e', isError: true);
        break;
      }
    }
  }


  Future<void> _importPdfMap() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      final path = pickedFile.path;
      if (path == null) return;

      if (!mounted) return;
      final geoResult = await Navigator.push<GeoReferencedImage>(
        context,
        MaterialPageRoute(
          builder: (_) => GeoReferenceScreen(
            pdfPath: path,
            fileName: pickedFile.name,
          ),
        ),
      );

      if (geoResult != null && mounted) {
        setState(() => _geoRefImages.add(geoResult));
        // Zoom to the geo-referenced image
        _flutterMapController.fitBounds(
          fmap.LatLngBounds(geoResult.bottomRight, geoResult.topLeft),
          options: const fmap.FitBoundsOptions(
            padding: EdgeInsets.all(30),
            maxZoom: 18,
          ),
        );
        _showSnackBar('PDF map pinned to real-world coordinates!');
      }
    } catch (e) {
      _showSnackBar('Error importing PDF: $e', isError: true);
    }
  }

  Future<void> _extractPhotosToMap() async {
    try {
      final picker = ImagePicker();
      final photos = await picker.pickMultiImage();
      if (photos.isEmpty) return;

      _showSnackBar('Extracting GPS from ${photos.length} photos...');
      
      final points = <LatLng>[];
      for (final photo in photos) {
        final bytes = await photo.readAsBytes();
        final data = await readExifFromBytes(bytes);
        
        IfdTag? latTag;
        IfdTag? lngTag;
        IfdTag? latRefTag;
        IfdTag? lngRefTag;
        
        for (final key in data.keys) {
          final k = key.toLowerCase();
          if (k.endsWith('latitude')) latTag = data[key];
          if (k.endsWith('longitude')) lngTag = data[key];
          if (k.endsWith('latituderef')) latRefTag = data[key];
          if (k.endsWith('longituderef')) lngRefTag = data[key];
        }

        if (latTag != null && lngTag != null) {
          final latData = latTag.values.toList();
          final lngData = lngTag.values.toList();
          final latRef = latRefTag?.printable.trim().toUpperCase() ?? 'N';
          final lngRef = lngRefTag?.printable.trim().toUpperCase() ?? 'E';

          double parseRatio(dynamic ratio) {
            try {
              if (ratio is num) return ratio.toDouble();
              if (ratio is String) {
                if (ratio.contains('/')) {
                  final parts = ratio.split('/');
                  return double.parse(parts[0]) / double.parse(parts[1]);
                }
                return double.parse(ratio);
              }
              try {
                // Ignore types, use dynamic invocation
                final numVal = ratio.numerator;
                final denVal = ratio.denominator;
                if (numVal != null && denVal != null && denVal != 0) {
                  return (numVal as num) / (denVal as num);
                }
              } catch (_) {}
              
              final str = ratio.toString();
              if (str.contains('/')) {
                final parts = str.split('/');
                return double.parse(parts[0]) / double.parse(parts[1]);
              }
              return double.parse(str);
            } catch (_) {}
            return 0.0;
          }

          if (latData.length >= 3 && lngData.length >= 3) {
            final lat = parseRatio(latData[0]) + parseRatio(latData[1]) / 60 + parseRatio(latData[2]) / 3600;
            final lng = parseRatio(lngData[0]) + parseRatio(lngData[1]) / 60 + parseRatio(lngData[2]) / 3600;

            final finalLat = latRef == 'S' ? -lat : lat;
            final finalLng = lngRef == 'W' ? -lng : lng;

            if (finalLat >= -90 && finalLat <= 90 && finalLng >= -180 && finalLng <= 180) {
              if (finalLat != 0.0 || finalLng != 0.0) {
                points.add(LatLng(finalLat, finalLng));
                continue; // Found via EXIF, move to next photo
              }
            }
          }
        }
        
        // --- Fallback: Try OCR if EXIF failed ---
        try {
          final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
          final RecognizedText recognizedText = await textRecognizer.processImage(InputImage.fromFilePath(photo.path));
          String text = recognizedText.text;
          textRecognizer.close();
          
          // Regex to find floating point numbers with at least 4 decimal places (typical for GPS)
          final regex = RegExp(r'(-?\d{1,3}\.\d{4,})');
          final matches = regex.allMatches(text).toList();
          
          if (matches.length >= 2) {
            final lat = double.tryParse(matches[0].group(1)!) ?? 0.0;
            final lng = double.tryParse(matches[1].group(1)!) ?? 0.0;
            if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
               if (lat != 0.0 || lng != 0.0) {
                 points.add(LatLng(lat, lng));
                 continue;
               }
            }
          }
        } catch (e) {
           debugPrint('OCR fallback failed for ${photo.path}: $e');
        }
      }

      if (points.isEmpty) {
        _showSnackBar('No GPS data found in selected photos', isError: true);
        return;
      }

      _showSnackBar('Added ${points.length} coordinates to map');
      _mapController.setDrawMode(DrawMode.polygon);
      for (final pt in points) {
        _mapController.addPoint(pt);
      }
      _flutterMapController.move(points.first, 16);

    } catch (e) {
      _showSnackBar('Error extracting photos: $e', isError: true);
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _searchController.dispose();
    super.dispose();
  }
}

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
                color: isActive ? AppTheme.greenPrimary : AppTheme.borderColor),
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

/// Colorful circular map FAB with gradient background (Dishaank-style)
class _MapFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isLoading;
  final Color? color;

  const _MapFab({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isLoading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.greenAccent;
    final label = tooltip.toUpperCase().split(' ').take(2).join(' '); // max 2 words

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: effectiveColor.withValues(alpha: 0.5), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: effectiveColor,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: effectiveColor,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        color: effectiveColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
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
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search village, city...',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
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
                    strokeWidth: 2, color: AppTheme.greenAccent),
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
          const Icon(Icons.touch_app_rounded, color: Colors.white, size: 16),
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
        border: Border.all(color: shape.color.withValues(alpha: 0.5)),
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
            decoration:
                BoxDecoration(color: shape.color, shape: BoxShape.circle),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
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
                border: Border(top: BorderSide(color: AppTheme.borderColor)),
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
            Icon(Icons.pentagon_outlined, color: AppTheme.textMuted, size: 40),
            SizedBox(height: 12),
            Text(
              'Tap Polygon in toolbar\nthen tap on the map\nto add waypoints',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 11, height: 1.5),
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
            bottom:
                BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.35)),
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
          color: enabled ? color.withValues(alpha: 0.12) : Colors.transparent,
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
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    border: Border.all(color: AppTheme.greenAccent, width: 2.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(top: BorderSide(color: AppTheme.borderColor)),
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

// ── GPS Tracking Panel ────────────────────────────────────────────────────────

class _GpsTrackingPanel extends StatelessWidget {
  final MapController controller;
  final Future<void> Function() onStop;

  const _GpsTrackingPanel({
    required this.controller,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final dist = controller.trackingDistanceMeters;
    final distStr = dist >= 1000
        ? '${(dist / 1000).toStringAsFixed(2)} km'
        : '${dist.toStringAsFixed(0)} m';
    final pts = controller.trackingPoints.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: controller.isTracking ? const Color(0xFFFF6F00) : Colors.amber,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status indicator dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: controller.isTracking
                  ? const Color(0xFFFF6F00)
                  : Colors.amber,
            ),
          ),
          const SizedBox(width: 8),
          // Distance + points
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                controller.isTracking ? 'RECORDING' : 'PAUSED',
                style: TextStyle(
                  color: controller.isTracking
                      ? const Color(0xFFFF6F00)
                      : Colors.amber,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '$distStr  ·  $pts pts',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Pause / Resume
          GestureDetector(
            onTap: () {
              if (controller.isTracking) {
                controller.pauseTracking();
              } else {
                controller.resumeTracking();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                controller.isTracking
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: controller.isTracking
                    ? const Color(0xFFFF6F00)
                    : Colors.amber,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Stop & save
          GestureDetector(
            onTap: onStop,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.stop_rounded,
                color: Colors.red,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsCoordChip extends StatelessWidget {
  final LatLng position;

  const _GpsCoordChip({required this.position});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gps_fixed_rounded,
                  size: 12, color: AppTheme.greenAccent),
              const SizedBox(width: 4),
              Text(
                'Lat: ${position.latitude.toStringAsFixed(6)}',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_outlined,
                  size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Lng: ${position.longitude.toStringAsFixed(6)}',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TappedCoordCard extends StatelessWidget {
  final LatLng position;
  final VoidCallback onClose;
  final VoidCallback onAddMarker;

  const _TappedCoordCard({
    required this.position,
    required this.onClose,
    required this.onAddMarker,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.greenAccent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Selected Point',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
              Text(
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onAddMarker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.greenPrimary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Add Point',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close_rounded,
                color: AppTheme.textMuted, size: 18),
          ),
        ],
      ),
    );
  }
}


class _LiveDrawingMeasurementCard extends StatelessWidget {
  final MapController controller;

  const _LiveDrawingMeasurementCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.drawMode != DrawMode.polygon || controller.currentPoints.length < 3) {
      return const SizedBox.shrink();
    }

    final points = controller.currentPoints
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();
    
    final areaHectares = GeoCalculator.calculateAreaHectares(points);
    final areaAcres = areaHectares * 2.47105;
    final perimeter = GeoCalculator.calculatePerimeterMeters(points);

    return Positioned(
      top: 100, // Just below the search bar
      left: 12,
      right: 80, // Leave room for FABs
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.greenAccent.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.architecture_rounded, color: AppTheme.greenAccent, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Live Measurement',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '${controller.currentPoints.length} pts',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat('Area (Hectares)', '${areaHectares.toStringAsFixed(3)} ha'),
                _buildStat('Area (Acres)', '${areaAcres.toStringAsFixed(3)} ac'),
              ],
            ),
            const SizedBox(height: 8),
            _buildStat('Perimeter', '${perimeter.toStringAsFixed(1)} m'),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.greenAccent,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            fontFamily: 'RobotoMono',
          ),
        ),
      ],
    );
  }
}





