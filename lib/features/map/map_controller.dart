import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/utils/geo_calculator.dart';
import '../../core/utils/kml_engine.dart';
import '../../core/models/polygon_model.dart';
import '../../core/database/db_helper.dart';

enum DrawMode { none, polygon, path, marker }

class DrawnShape {
  final String id;
  String name;
  final DrawMode type;
  final List<LatLng> points;
  Color color;
  double areaHectares;
  double perimeterMeters;

  DrawnShape({
    required this.id,
    required this.name,
    required this.type,
    required this.points,
    this.color = const Color(0xFF2EA043),
    this.areaHectares = 0,
    this.perimeterMeters = 0,
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

  // Map Style (Street / Satellite)
  String _mapStyle = 'Street';
  
  // Offline Download Mode
  bool _isOfflineDownloadMode = false;

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
  void closePolygon(BuildContext context) {
    if (_drawMode != DrawMode.polygon || _currentPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least 3 points to close polygon')),
      );
      return;
    }
    _finalizePolygon(context);
  }

  void _finalizePolygon(BuildContext context) {
    final pts = List<LatLng>.from(_currentPoints);
    final pointMaps = pts
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();

    final area = GeoCalculator.calculateAreaHectares(pointMaps);
    final perimeter = GeoCalculator.calculatePerimeterMeters(pointMaps);

    final shape = DrawnShape(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Polygon ${_drawnShapes.length + 1}',
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
  }

  void selectShape(DrawnShape shape) {
    _selectedShape = shape;
    notifyListeners();
  }

  void clearSelection() {
    _selectedShape = null;
    notifyListeners();
  }

  void deleteShape(String id) {
    _drawnShapes.removeWhere((s) => s.id == id);
    if (_selectedShape?.id == id) _selectedShape = null;
    notifyListeners();
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

  /// Save selected polygon to database
  Future<bool> saveSelectedPolygon() async {
    final shape = _selectedShape;
    if (shape == null || shape.type != DrawMode.polygon) return false;

    final coordList = shape.points
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();

    final model = PolygonModel(
      name: shape.name,
      coordinates: jsonEncode(coordList),
      areaHectares: shape.areaHectares,
      perimeterMeters: shape.perimeterMeters,
      color: '#${shape.color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      createdAt: DateTime.now().toIso8601String(),
    );

    await DbHelper().insertPolygon(model);
    return true;
  }

  /// Load KML shapes for display
  void loadKmlShapes(List<KmlShape> shapes) {
    _kmlShapes = shapes;
    notifyListeners();
  }

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
