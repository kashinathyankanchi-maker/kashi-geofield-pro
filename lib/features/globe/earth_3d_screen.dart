import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_earth_globe/flutter_earth_globe.dart';
import 'package:flutter_earth_globe/flutter_earth_globe_controller.dart';
import 'package:flutter_earth_globe/globe_coordinates.dart';
import 'package:flutter_earth_globe/point.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../core/database/db_helper.dart';
import '../../shared/theme.dart';

class GlobePlaceItem {
  final String id;
  final String title;
  final String subtitle;
  final String type; // 'village', 'polygon', 'kml'
  final double lat;
  final double lng;
  final double areaHectares;

  GlobePlaceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.lat,
    required this.lng,
    required this.areaHectares,
  });
}

class Earth3dScreen extends StatefulWidget {
  const Earth3dScreen({super.key});

  @override
  State<Earth3dScreen> createState() => _Earth3dScreenState();
}

class _Earth3dScreenState extends State<Earth3dScreen> {
  late FlutterEarthGlobeController _controller;
  bool _isLoading = true;
  bool _isDayNightCycle = false;
  double _currentZoom = 1.0;

  List<GlobePlaceItem> _allPlaces = [];
  String _selectedFilter = 'all'; // 'all', 'village', 'polygon', 'kml'
  GlobePlaceItem? _selectedPlace;

  @override
  void initState() {
    super.initState();
    _initController();
    _loadEarthTextures();
    _loadSavedPlaces();
  }

  void _initController() {
    _controller = FlutterEarthGlobeController(
      rotationSpeed: 0.02,
      isZoomEnabled: true,
      zoom: 1.0,
      maxZoom: 3.5,
      minZoom: 0.5,
      showAtmosphere: true,
      atmosphereColor: const Color.fromARGB(255, 57, 123, 185),
      atmosphereBlur: 35.0,
      surfaceLightingEnabled: true,
      lightAngle: -45.0,
      lightIntensity: 0.85,
      ambientLight: 0.45,
    );
  }

  Future<void> _loadEarthTextures() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dayFile = File(path.join(dir.path, 'earth_topo_2048.jpg'));
      final nightFile = File(path.join(dir.path, 'earth_lights_2048.jpg'));

      if (dayFile.existsSync()) {
        _controller.loadSurface(FileImage(dayFile));
      } else {
        const dayUrl =
            'https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57752/land_shallow_topo_2048.jpg';
        _controller.loadSurface(const NetworkImage(dayUrl));
        _downloadAndCacheTexture(dayUrl, dayFile);
      }

      if (nightFile.existsSync()) {
        _controller.loadNightSurface(FileImage(nightFile));
      } else {
        const nightUrl =
            'https://eoimages.gsfc.nasa.gov/images/imagerecords/55000/55167/earth_lights_lrg.jpg';
        _controller.loadNightSurface(const NetworkImage(nightUrl));
        _downloadAndCacheTexture(nightUrl, nightFile);
      }
    } catch (e) {
      debugPrint('Error loading earth textures: $e');
    }
  }

  Future<void> _downloadAndCacheTexture(String url, File targetFile) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        await targetFile.writeAsBytes(bytes);
      }
      client.close();
    } catch (e) {
      debugPrint('Error caching texture $url: $e');
    }
  }

  Future<void> _loadSavedPlaces() async {
    setState(() => _isLoading = true);
    final places = <GlobePlaceItem>[];
    final db = DbHelper();

    try {
      // 1. Load Villages
      final villages = await db.getAllVillages();
      for (final v in villages) {
        try {
          final coords = jsonDecode(v.coordinates) as List;
          if (coords.isNotEmpty) {
            final first = coords.first;
            final lat = (first['lat'] as num).toDouble();
            final lng = (first['lng'] as num).toDouble();
            places.add(GlobePlaceItem(
              id: 'village_${v.id}',
              title: v.villageName,
              subtitle: '${v.district}, ${v.state}',
              type: 'village',
              lat: lat,
              lng: lng,
              areaHectares: v.areaHectares,
            ));
          }
        } catch (e) {
          debugPrint('Parse error for village ${v.villageName}: $e');
        }
      }

      // 2. Load Polygons
      final polygons = await db.getAllPolygons();
      for (final p in polygons) {
        try {
          final coords = jsonDecode(p.coordinates) as List;
          if (coords.isNotEmpty) {
            final first = coords.first;
            final lat = (first['lat'] as num).toDouble();
            final lng = (first['lng'] as num).toDouble();
            places.add(GlobePlaceItem(
              id: 'polygon_${p.id}',
              title: p.name,
              subtitle: '${p.areaHectares.toStringAsFixed(2)} ha (${(p.areaHectares * 2.47105).toStringAsFixed(2)} acres)',
              type: 'polygon',
              lat: lat,
              lng: lng,
              areaHectares: p.areaHectares,
            ));
          }
        } catch (e) {
          debugPrint('Parse error for polygon ${p.name}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading saved places from DB: $e');
    }

    setState(() {
      _allPlaces = places;
      _isLoading = false;
    });

    _plotPointsOnGlobe();
  }

  void _plotPointsOnGlobe() {
    for (final place in _allPlaces) {
      Color dotColor = AppTheme.greenAccent;
      if (place.type == 'polygon') dotColor = AppTheme.warningColor;
      if (place.type == 'kml') dotColor = AppTheme.infoColor;

      _controller.addPoint(
        Point(
          id: place.id,
          coordinates: GlobeCoordinates(place.lat, place.lng),
          label: place.title,
          style: PointStyle(
            color: dotColor,
            size: 7.0,
            altitude: 0.02,
          ),
          onTap: () => _onPlaceSelected(place),
        ),
      );
    }
  }

  void _onPlaceSelected(GlobePlaceItem place) {
    setState(() {
      _selectedPlace = place;
    });
    _controller.focusOnCoordinates(
      GlobeCoordinates(place.lat, place.lng),
      animate: true,
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOutCubic,
    );
  }

  void _toggleDayNightCycle() {
    setState(() {
      _isDayNightCycle = !_isDayNightCycle;
    });
    if (_isDayNightCycle) {
      _controller.startDayNightCycle(
        cycleDuration: const Duration(seconds: 45),
        direction: DayNightCycleDirection.leftToRight,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day-Night Orbital Lighting Started')),
      );
    } else {
      _controller.stopDayNightCycle();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orbital Lighting Paused')),
      );
    }
  }

  List<GlobePlaceItem> get _filteredPlaces {
    if (_selectedFilter == 'all') return _allPlaces;
    return _allPlaces.where((p) => p.type == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final globeRadius = (screenWidth * 0.42).clamp(150.0, 320.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17), // Deep space dark
      body: Stack(
        children: [
          // ── 1. 3D Globe View ──────────────────────────────────────────
          Center(
            child: FlutterEarthGlobe(
              radius: globeRadius,
              controller: _controller,
              onZoomChanged: (zoom) {
                setState(() => _currentZoom = zoom);
              },
            ),
          ),

          // ── 2. Top Header & Navigation ───────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.public_rounded, color: Color(0xFF00E5FF), size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            '3D GOOGLE EARTH MODE',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_allPlaces.length} PLOTS | ZOOM: ${_currentZoom.toStringAsFixed(1)}X',
                            style: const TextStyle(
                              color: AppTheme.greenAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 3. Right Floating Tools Panel ─────────────────────────────
          Positioned(
            right: 16,
            top: 100,
            child: Column(
              children: [
                _ToolBtn(
                  icon: _isDayNightCycle ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                  tooltip: 'Toggle Day/Night Orbit',
                  color: _isDayNightCycle ? const Color(0xFFFFD54F) : const Color(0xFF64B5F6),
                  onTap: _toggleDayNightCycle,
                ),
                const SizedBox(height: 10),
                _ToolBtn(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Reload Places',
                  color: AppTheme.greenAccent,
                  onTap: _loadSavedPlaces,
                ),
                const SizedBox(height: 10),
                _ToolBtn(
                  icon: Icons.zoom_out_map_rounded,
                  tooltip: 'Reset Camera',
                  color: AppTheme.textSecondary,
                  onTap: () {
                    setState(() => _selectedPlace = null);
                    _controller.focusOnCoordinates(
                      const GlobeCoordinates(20.5937, 78.9629),
                      animate: true,
                      duration: const Duration(milliseconds: 1000),
                    );
                  },
                ),
              ],
            ),
          ),

          // ── 4. Selected Place Info Card ───────────────────────────────
          if (_selectedPlace != null)
            Positioned(
              top: 100,
              left: 16,
              right: 80,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _selectedPlace!.type == 'village' ? Icons.location_on : Icons.pentagon,
                          color: _selectedPlace!.type == 'village' ? AppTheme.greenAccent : AppTheme.warningColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedPlace!.title,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => setState(() => _selectedPlace = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedPlace!.subtitle,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lat: ${_selectedPlace!.lat.toStringAsFixed(5)}, Lng: ${_selectedPlace!.lng.toStringAsFixed(5)}',
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.greenPrimary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_selectedPlace!.type.toUpperCase()} PINNED',
                            style: const TextStyle(
                              color: AppTheme.greenAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ── 5. Bottom Places Drawer ───────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 240,
              decoration: BoxDecoration(
                color: AppTheme.bgCard.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: const Border(
                  top: BorderSide(color: AppTheme.borderColor, width: 1),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textSecondary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        const Text(
                          'FLY TO LOCATION:',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FilterChip(
                                  label: 'All (${_allPlaces.length})',
                                  isSelected: _selectedFilter == 'all',
                                  onTap: () => setState(() => _selectedFilter = 'all'),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Villages (${_allPlaces.where((p) => p.type == 'village').length})',
                                  isSelected: _selectedFilter == 'village',
                                  onTap: () => setState(() => _selectedFilter = 'village'),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Polygons (${_allPlaces.where((p) => p.type == 'polygon').length})',
                                  isSelected: _selectedFilter == 'polygon',
                                  onTap: () => setState(() => _selectedFilter = 'polygon'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.borderColor),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: AppTheme.greenAccent))
                        : _filteredPlaces.isEmpty
                            ? const Center(
                                child: Text(
                                  'No places saved yet. Import villages or draw polygons on the 2D map!',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                scrollDirection: Axis.horizontal,
                                itemCount: _filteredPlaces.length,
                                itemBuilder: (context, idx) {
                                  final place = _filteredPlaces[idx];
                                  final isSelected = _selectedPlace?.id == place.id;
                                  return GestureDetector(
                                    onTap: () => _onPlaceSelected(place),
                                    child: Container(
                                      width: 200,
                                      margin: const EdgeInsets.only(right: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                                            : AppTheme.bgSecondary,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF00E5FF)
                                              : AppTheme.borderColor,
                                          width: isSelected ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                place.type == 'village'
                                                    ? Icons.location_on
                                                    : Icons.pentagon,
                                                color: place.type == 'village'
                                                    ? AppTheme.greenAccent
                                                    : AppTheme.warningColor,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  place.title,
                                                  style: TextStyle(
                                                    color: isSelected
                                                        ? const Color(0xFF00E5FF)
                                                        : AppTheme.textPrimary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            place.subtitle,
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 12,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const Spacer(),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Text(
                                                'TAP TO FLY ✈️',
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? const Color(0xFF00E5FF)
                                                      : AppTheme.greenAccent,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.bgCard.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.2) : AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E5FF) : AppTheme.borderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00E5FF) : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
