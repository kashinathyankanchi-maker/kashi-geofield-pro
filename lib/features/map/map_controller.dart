import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/utils/geo_calculator.dart';
import '../../core/utils/kml_engine.dart';
import '../../core/models/polygon_model.dart';
import '../../core/database/db_helper.dart';

enum DrawMode { none, polygon, path, marker }

/// GPS live-tracking state
enum TrackingState { idle, tracking, paused }

class DrawnShape {
  final String id;
  String name;
  final DrawMode type;
  final List<LatLng> points;
  Color color;
  double areaHectares;
  double perimeterMeters;
  // DB row id for persistence
  int? dbId;

  DrawnShape({
    required this.id,
    required this.name,
    required this.type,
    required this.points,
    this.color = const Color(0xFF2EA043),
    this.areaHectares = 0,
    this.perimeterMeters = 0,
    this.dbId,
  });
}

class MapController extends ChangeNotifier {
  // Drawing state
  DrawMode _drawMode = DrawMode.none;
  final List<LatLng> _currentPoints = [];
  final List<DrawnShape> _drawnShapes = [];
  DrawnShape? _selectedShape;

  // Undo/redo stacks
  final List<List<LatLng>> _undoStack = [];
  final List<List<LatLng>> _redoStack = [];

  // Layer visibility
  bool showPolygonLayer = true;
  bool showVillageLayer = true;
  bool showKmlLayer = true;

  // KML shapes loaded on map
  List<KmlShape> _kmlShapes = [];

  // Map Style (Street / Satellite / Hybrid)
  String _mapStyle = 'Satellite';

  // Offline Download Mode
  bool _isOfflineDownloadMode = false;

  // ── GPS Live Tracking ──────────────────────────────────────────────────────
  TrackingState _trackingState = TrackingState.idle;
  final List<LatLng> _trackingPoints = [];
  double _trackingDistanceMeters = 0.0;

  // Getters
  DrawMode get drawMode => _drawMode;
  List<LatLng> get currentPoints => List.unmodifiable(_currentPoints);
  List<DrawnShape> get drawnShapes => List.unmodifiable(_drawnShapes);
  DrawnShape? get selectedShape => _selectedShape;
  List<KmlShape> get kmlShapes => _kmlShapes;
  String get mapStyle => _mapStyle;
  bool get isOfflineDownloadMode => _isOfflineDownloadMode;
  bool get isDrawing => _drawMode != DrawMode.none;
  bool get canUndo => _currentPoints.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // Tracking getters
  TrackingState get trackingState => _trackingState;
  bool get isTracking => _trackingState == TrackingState.tracking;
  bool get isTrackingPaused => _trackingState == TrackingState.paused;
  bool get hasTracking => _trackingPoints.isNotEmpty;
  List<LatLng> get trackingPoints => List.unmodifiable(_trackingPoints);
  double get trackingDistanceMeters => _trackingDistanceMeters;

  // ── Drawing ────────────────────────────────────────────────────────────────

  void setDrawMode(DrawMode mode) {
    if (_drawMode != mode) {
      _drawMode = mode;
      _currentPoints.clear();
      _undoStack.clear();
      _redoStack.clear();
      _selectedShape = null;
      notifyListeners();
    }
  }

  void addPoint(LatLng point) {
    if (_drawMode == DrawMode.none) return;
    _undoStack.add(List.from(_currentPoints));
    _redoStack.clear();
    _currentPoints.add(point);

    if (_drawMode == DrawMode.marker) {
      _finalizeMarker(point);
    } else {
      notifyListeners();
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.from(_currentPoints));
    final prev = _undoStack.removeLast();
    _currentPoints
      ..clear()
      ..addAll(prev);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.from(_currentPoints));
    final next = _redoStack.removeLast();
    _currentPoints
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// Close the current polygon if drawing polygon mode
  void closePolygon(BuildContext context, {String? name}) {
    if (_drawMode != DrawMode.polygon || _currentPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least 3 points to close polygon')),
      );
      return;
    }
    _finalizePolygon(name: name);
  }

  void _finalizePolygon({String? name}) {
    final pts = List<LatLng>.from(_currentPoints);
    final pointMaps = pts
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();

    final area = GeoCalculator.calculateAreaHectares(pointMaps);
    final perimeter = GeoCalculator.calculatePerimeterMeters(pointMaps);

    final shape = DrawnShape(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name ?? 'Polygon ${_drawnShapes.length + 1}',
      type: DrawMode.polygon,
      points: pts,
      areaHectares: area,
      perimeterMeters: perimeter,
    );

    _drawnShapes.add(shape);
    _currentPoints.clear();
    _undoStack.clear();
    _redoStack.clear();
    _selectedShape = shape;
    setDrawMode(DrawMode.none);
    notifyListeners();

    // Auto-save to database immediately
    _autoSaveShape(shape);
  }

  void _finalizeMarker(LatLng point) {
    final shape = DrawnShape(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Marker ${_drawnShapes.length + 1}',
      type: DrawMode.marker,
      points: [point],
    );
    _drawnShapes.add(shape);
    _currentPoints.clear();
    _selectedShape = shape;
    setDrawMode(DrawMode.none);
    notifyListeners();
    _autoSaveShape(shape);
  }

  void finalizePath() {
    if (_drawMode != DrawMode.path || _currentPoints.length < 2) return;
    final pts = List<LatLng>.from(_currentPoints);
    final pointMaps =
        pts.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    final perimeter = GeoCalculator.calculatePerimeterMeters(pointMaps);

    final shape = DrawnShape(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Path ${_drawnShapes.length + 1}',
      type: DrawMode.path,
      points: pts,
      perimeterMeters: perimeter,
      color: const Color(0xFF388BFD),
    );
    _drawnShapes.add(shape);
    _currentPoints.clear();
    _undoStack.clear();
    _redoStack.clear();
    _selectedShape = shape;
    setDrawMode(DrawMode.none);
    notifyListeners();
    _autoSaveShape(shape);
  }

  // ── GPS Live Tracking ──────────────────────────────────────────────────────

  void startTracking() {
    _trackingState = TrackingState.tracking;
    notifyListeners();
  }

  void pauseTracking() {
    if (_trackingState == TrackingState.tracking) {
      _trackingState = TrackingState.paused;
      notifyListeners();
    }
  }

  void resumeTracking() {
    if (_trackingState == TrackingState.paused) {
      _trackingState = TrackingState.tracking;
      notifyListeners();
    }
  }

  /// Add a GPS position to the live tracking path (called by map_screen on each location update)
  void addTrackingPoint(LatLng point) {
    if (_trackingState != TrackingState.tracking) return;
    if (_trackingPoints.isNotEmpty) {
      final last = _trackingPoints.last;
      final dist = const Distance().as(LengthUnit.Meter, last, point);
      // Only add if moved more than 3 metres (filter GPS noise)
      if (dist < 3) return;
      _trackingDistanceMeters += dist;
    }
    _trackingPoints.add(point);
    notifyListeners();
  }

  /// Stop tracking — returns the DrawnShape created, or null if < 2 points
  DrawnShape? stopTracking() {
    _trackingState = TrackingState.idle;
    if (_trackingPoints.length < 2) {
      _trackingPoints.clear();
      _trackingDistanceMeters = 0;
      notifyListeners();
      return null;
    }

    final pts = List<LatLng>.from(_trackingPoints);
    final shape = DrawnShape(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'GPS Track ${_drawnShapes.where((s) => s.type == DrawMode.path).length + 1}',
      type: DrawMode.path,
      points: pts,
      perimeterMeters: _trackingDistanceMeters,
      color: const Color(0xFFFF6F00),
    );
    _drawnShapes.add(shape);
    _selectedShape = shape;
    _trackingPoints.clear();
    _trackingDistanceMeters = 0;
    notifyListeners();
    _autoSaveShape(shape);
    return shape;
  }

  void clearTrackingPath() {
    _trackingState = TrackingState.idle;
    _trackingPoints.clear();
    _trackingDistanceMeters = 0;
    notifyListeners();
  }

  // ── Shape management ───────────────────────────────────────────────────────

  void selectShape(DrawnShape shape) {
    _selectedShape = shape;
    notifyListeners();
  }

  void clearSelection() {
    _selectedShape = null;
    notifyListeners();
  }

  void deleteShape(String id) {
    final shape = _drawnShapes.firstWhere((s) => s.id == id, orElse: () => DrawnShape(id: '', name: '', type: DrawMode.none, points: []));
    if (shape.dbId != null) {
      DbHelper().deletePolygon(shape.dbId!);
    }
    _drawnShapes.removeWhere((s) => s.id == id);
    if (_selectedShape?.id == id) _selectedShape = null;
    notifyListeners();
  }

  Future<void> convertPathToPolygon(String id) async {
    final idx = _drawnShapes.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final oldShape = _drawnShapes[idx];
    if (oldShape.type != DrawMode.path) return;

    final pointMaps = oldShape.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    final area = GeoCalculator.calculateAreaHectares(pointMaps);
    
    final newShape = DrawnShape(
      id: oldShape.id,
      name: oldShape.name.replaceAll('Track', 'Polygon').replaceAll('Path', 'Polygon'),
      type: DrawMode.polygon,
      points: oldShape.points,
      areaHectares: area,
      perimeterMeters: oldShape.perimeterMeters,
      dbId: oldShape.dbId,
    );
    newShape.color = oldShape.color;
    
    _drawnShapes[idx] = newShape;
    if (_selectedShape?.id == id) _selectedShape = newShape;
    notifyListeners();
    
    if (newShape.dbId != null) {
      final model = PolygonModel(
        id: newShape.dbId,
        name: newShape.name,
        coordinates: jsonEncode(newShape.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList()),
        areaHectares: newShape.areaHectares,
        perimeterMeters: newShape.perimeterMeters,
        color: "#\${newShape.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}",
        createdAt: DateTime.now().toIso8601String(),
      );
      await DbHelper().updatePolygon(model);
    }
  }

  void renameShape(String id, String newName) {
    final idx = _drawnShapes.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      _drawnShapes[idx].name = newName;
      notifyListeners();
    }
  }

  void changeShapeColor(String id, Color color) {
    final idx = _drawnShapes.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      _drawnShapes[idx].color = color;
      notifyListeners();
    }
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Auto-save a shape to DB immediately after creation
  Future<void> _autoSaveShape(DrawnShape shape) async {
    try {
      final coordList = shape.points
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();

      final colorHex = '#${shape.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      final model = PolygonModel(
        name: shape.name,
        coordinates: jsonEncode(coordList),
        areaHectares: shape.areaHectares,
        perimeterMeters: shape.perimeterMeters,
        color: colorHex,
        createdAt: DateTime.now().toIso8601String(),
      );
      final id = await DbHelper().insertPolygon(model);
      shape.dbId = id;
    } catch (e) {
      // Silent — persistence failure should not crash the app
    }
  }

  /// Load all previously saved shapes from the database
  Future<void> loadFromDatabase() async {
    try {
      final polygons = await DbHelper().getAllPolygons();
      for (final poly in polygons) {
        final List<dynamic> rawCoords = jsonDecode(poly.coordinates);
        final pts = rawCoords
            .map((c) => LatLng(
                  (c['lat'] as num).toDouble(),
                  (c['lng'] as num).toDouble(),
                ))
            .toList();
        if (pts.isEmpty) continue;

        // Determine type from name prefix
        final isPath = poly.name.startsWith('Path') || poly.name.startsWith('GPS Track');
        final isMarker = poly.name.startsWith('Marker') && pts.length == 1;

        Color color = const Color(0xFF2EA043);
        try {
          final hex = poly.color.replaceFirst('#', '');
          color = Color(int.parse('FF$hex', radix: 16));
        } catch (_) {}

        final shape = DrawnShape(
          id: poly.id?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          name: poly.name,
          type: isMarker
              ? DrawMode.marker
              : isPath
                  ? DrawMode.path
                  : DrawMode.polygon,
          points: pts,
          color: color,
          areaHectares: poly.areaHectares,
          perimeterMeters: poly.perimeterMeters,
          dbId: poly.id,
        );
        _drawnShapes.add(shape);
      }
      notifyListeners();
    } catch (e) {
      // Silent
    }
  }

  /// Save selected polygon to database (manual save)
  Future<bool> saveSelectedPolygon() async {
    final shape = _selectedShape;
    if (shape == null || shape.type != DrawMode.polygon) return false;
    await _autoSaveShape(shape);
    return true;
  }

  // ── KML ────────────────────────────────────────────────────────────────────

  /// Load KML shapes for display
  void loadKmlShapes(List<KmlShape> shapes) {
    _kmlShapes = shapes;
    notifyListeners();
  }

  void addKmlShapes(List<KmlShape> shapes) {
    _kmlShapes.addAll(shapes);
    notifyListeners();
  }

  /// Add a manually created shape directly (bypasses draw mode)
  void addManualShape(DrawnShape shape) {
    _drawnShapes.add(shape);
    _selectedShape = shape;
    notifyListeners();
    _autoSaveShape(shape);
  }

  // ── Layer toggles ──────────────────────────────────────────────────────────

  void togglePolygonLayer() {
    showPolygonLayer = !showPolygonLayer;
    notifyListeners();
  }

  void toggleVillageLayer() {
    showVillageLayer = !showVillageLayer;
    notifyListeners();
  }

  void toggleKmlLayer() {
    showKmlLayer = !showKmlLayer;
    notifyListeners();
  }

  void clearAllShapes() {
    _drawnShapes.clear();
    _currentPoints.clear();
    _selectedShape = null;
    notifyListeners();
  }

  void setMapStyle(String style) {
    if (_mapStyle != style) {
      _mapStyle = style;
      notifyListeners();
    }
  }

  void toggleOfflineDownloadMode() {
    _isOfflineDownloadMode = !_isOfflineDownloadMode;
    notifyListeners();
  }
}
