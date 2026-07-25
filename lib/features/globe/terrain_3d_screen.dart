import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../../core/database/db_helper.dart';
import '../../shared/theme.dart';
import 'earth_3d_screen.dart';

class Terrain3dScreen extends StatefulWidget {
  final LatLng? initialCenter;
  final String? initialTitle;

  const Terrain3dScreen({super.key, this.initialCenter, this.initialTitle});

  @override
  State<Terrain3dScreen> createState() => _Terrain3dScreenState();
}

class _Terrain3dScreenState extends State<Terrain3dScreen> {
  late final WebViewController _webController;
  bool _isLoading = true;
  bool _is3dPitch = true; // starts in 3D tilted terrain mode
  String _selectedFilter = 'all';

  List<_TerrainItem> _allPlaces = [];
  _TerrainItem? _selectedPlace;

  @override
  void initState() {
    super.initState();
    _loadDatabasePlaces();
    _initWebView();
  }

  Future<void> _loadDatabasePlaces() async {
    try {
      final db = DbHelper();
      final vList = await db.getAllVillages();
      final pList = await db.getAllPolygons();
      final kList = await db.getAllKmlFiles();

      final List<_TerrainItem> items = [];

      for (final v in vList) {
        try {
          final List<dynamic> coords = jsonDecode(v.coordinates);
          if (coords.isNotEmpty) {
            double lat = 0, lng = 0;
            for (final c in coords) {
              lat += (c['lat'] as num).toDouble();
              lng += (c['lng'] as num).toDouble();
            }
            lat /= coords.length;
            lng /= coords.length;
            items.add(_TerrainItem(
              id: 'v_${v.id}',
              title: v.villageName,
              subtitle: '${v.district}, ${v.state}',
              lat: lat,
              lng: lng,
              type: 'village',
              areaHectares: v.areaHectares,
              coordsJson: v.coordinates,
              color: '#00FF66',
            ));
          }
        } catch (_) {}
      }

      for (final p in pList) {
        try {
          final List<dynamic> coords = jsonDecode(p.coordinates);
          if (coords.isNotEmpty) {
            double lat = 0, lng = 0;
            for (final c in coords) {
              lat += (c['lat'] as num).toDouble();
              lng += (c['lng'] as num).toDouble();
            }
            lat /= coords.length;
            lng /= coords.length;
            items.add(_TerrainItem(
              id: 'p_${p.id}',
              title: p.name,
              subtitle: 'Field Area: ${p.areaHectares.toStringAsFixed(2)} Ha',
              lat: lat,
              lng: lng,
              type: 'polygon',
              areaHectares: p.areaHectares,
              coordsJson: p.coordinates,
              color: p.color.isNotEmpty ? p.color : '#00E5FF',
            ));
          }
        } catch (_) {}
      }

      for (final k in kList) {
        if (k.isVisible) {
          items.add(_TerrainItem(
            id: 'k_${k.id}',
            title: k.filename,
            subtitle: 'Imported KML Layer',
            lat: 20.5937,
            lng: 78.9629,
            type: 'kml',
            areaHectares: 0,
            coordsJson: '[]',
            color: k.layerColor,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _allPlaces = items;
          if (_allPlaces.isNotEmpty && widget.initialCenter == null) {
            _selectedPlace = _allPlaces.first;
          }
        });
        _injectGeoJsonToMap();
      }
    } catch (_) {}
  }

  void _initWebView() {
    final lat = widget.initialCenter?.latitude ?? (_allPlaces.isNotEmpty ? _allPlaces.first.lat : 20.5937);
    final lng = widget.initialCenter?.longitude ?? (_allPlaces.isNotEmpty ? _allPlaces.first.lng : 78.9629);

    final htmlContent = _buildMapLibreHtml(lat, lng);

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
              _injectGeoJsonToMap();
            }
          },
        ),
      )
      ..loadHtmlString(htmlContent, baseUrl: 'https://localhost/');
  }

  String _buildMapLibreHtml(double centerLat, double centerLng) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <title>3D Google Earth Terrain</title>
    <script src="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.js"></script>
    <link href="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.css" rel="stylesheet" />
    <style>
        body { margin: 0; padding: 0; background-color: #000; overflow: hidden; font-family: sans-serif; }
        #map { position: absolute; top: 0; bottom: 0; width: 100%; height: 100%; }
        .maplibregl-ctrl-attribution { display: none !important; }
        .maplibregl-ctrl-logo { display: none !important; }
    </style>
</head>
<body>
    <div id="map"></div>
    <script>
        const map = new maplibregl.Map({
            container: 'map',
            style: {
                version: 8,
                sources: {
                    'satellite-tiles': {
                        type: 'raster',
                        tiles: [
                            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                            'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}'
                        ],
                        tileSize: 256
                    },
                    'terrain-dem': {
                        type: 'raster-dem',
                        tiles: [
                            'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'
                        ],
                        encoding: 'terrarium',
                        tileSize: 256
                    }
                },
                layers: [
                    {
                        id: 'satellite-layer',
                        type: 'raster',
                        source: 'satellite-tiles',
                        minzoom: 0,
                        maxzoom: 22
                    }
                ],
                terrain: {
                    source: 'terrain-dem',
                    exaggeration: 1.5
                }
            },
            center: [$centerLng, $centerLat],
            zoom: 13.5,
            pitch: 60,
            bearing: -15,
            maxPitch: 85,
            attributionControl: false
        });

        map.addControl(new maplibregl.NavigationControl({
            showCompass: true,
            showZoom: false,
            visualizePitch: true
        }), 'top-right');

        map.on('load', () => {
            map.addSource('user-polygons', {
                type: 'geojson',
                data: {
                    type: 'FeatureCollection',
                    features: []
                }
            });

            map.addLayer({
                id: 'user-polygons-fill',
                type: 'fill',
                source: 'user-polygons',
                paint: {
                    'fill-color': ['get', 'color'],
                    'fill-opacity': 0.35
                }
            });

            map.addLayer({
                id: 'user-polygons-line',
                type: 'line',
                source: 'user-polygons',
                paint: {
                    'line-color': ['get', 'color'],
                    'line-width': 3
                }
            });
        });

        function updateGeoJson(geojsonStr) {
            if (map && map.getSource('user-polygons')) {
                try {
                    const data = JSON.parse(geojsonStr);
                    map.getSource('user-polygons').setData(data);
                } catch(e) {}
            }
        }

        function flyToPlace(lat, lng, zoom, pitch, bearing) {
            if (map) {
                map.flyTo({
                    center: [lng, lat],
                    zoom: zoom || 14,
                    pitch: pitch !== undefined ? pitch : 60,
                    bearing: bearing || 0,
                    duration: 2000,
                    essential: true
                });
            }
        }

        function toggle3dMode(is3d) {
            if (map) {
                map.easeTo({
                    pitch: is3d ? 60 : 0,
                    bearing: is3d ? -15 : 0,
                    duration: 1000
                });
            }
        }

        function resetNorth() {
            if (map) {
                map.resetNorthPitch({ duration: 1000 });
            }
        }
    </script>
</body>
</html>
''';
  }

  void _injectGeoJsonToMap() {
    if (_allPlaces.isEmpty) return;
    try {
      final List<Map<String, dynamic>> features = [];

      for (final place in _allPlaces) {
        if (place.type == 'village' || place.type == 'polygon') {
          try {
            final List<dynamic> coords = jsonDecode(place.coordsJson);
            if (coords.length >= 3) {
              final List<List<double>> ring = coords
                  .map((c) => [(c['lng'] as num).toDouble(), (c['lat'] as num).toDouble()])
                  .toList();
              ring.add(ring.first); // close polygon

              features.add({
                'type': 'Feature',
                'properties': {
                  'id': place.id,
                  'title': place.title,
                  'color': place.color,
                },
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [ring],
                }
              });
            }
          } catch (_) {}
        }
      }

      final geoJson = {
        'type': 'FeatureCollection',
        'features': features,
      };

      final jsonString = jsonEncode(geoJson).replaceAll("'", "\\'");
      _webController.runJavaScript("updateGeoJson('$jsonString');");
    } catch (_) {}
  }

  void _onPlaceSelected(_TerrainItem place) {
    setState(() => _selectedPlace = place);
    _webController.runJavaScript("flyToPlace(${place.lat}, ${place.lng}, 14.5, ${_is3dPitch ? 60 : 0}, -15);");
  }

  void _toggle2d3d() {
    setState(() => _is3dPitch = !_is3dPitch);
    _webController.runJavaScript("toggle3dMode($_is3dPitch);");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_is3dPitch ? '3D Mountain Terrain Mode (60° Pitch)' : '2D Top-Down Satellite Mode'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _resetNorth() {
    _webController.runJavaScript("resetNorth();");
  }

  List<_TerrainItem> get _filteredPlaces {
    if (_selectedFilter == 'all') return _allPlaces;
    return _allPlaces.where((p) => p.type == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. 3D Terrain MapLibre WebView ──────────────────────────────
          WebViewWidget(controller: _webController),

          // ── 2. Loading Indicator ────────────────────────────────────────
          if (_isLoading)
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF00E5FF)),
                  const SizedBox(height: 16),
                  const Text(
                    'LOADING 3D TERRAIN & SATELLITE MAP...',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rendering 3D elevation topography & satellite tiles',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                  ),
                ],
              ),
            ),

          // ── 3. Top Header Bar ───────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.terrain_rounded, color: Color(0xFF00E5FF), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.initialTitle ?? '3D Google Earth Terrain',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '3D ELEVATION',
                              style: TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const Earth3dScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Tooltip(
                        message: 'Planetary Space Globe',
                        child: Icon(Icons.public_rounded, color: Color(0xFF00E5FF), size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 4. Right Control Bar (Exactly matching Google Earth UI) ─────
          Positioned(
            right: 16,
            bottom: 160,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reset North / Compass
                _ControlButton(
                  icon: Icons.explore_rounded,
                  color: Colors.white,
                  tooltip: 'Reset North',
                  onTap: _resetNorth,
                ),
                const SizedBox(height: 12),

                // Fly to GPS / selected place
                _ControlButton(
                  icon: Icons.my_location_rounded,
                  color: Colors.white,
                  tooltip: 'Target Selected Location',
                  onTap: () {
                    if (_selectedPlace != null) {
                      _onPlaceSelected(_selectedPlace!);
                    } else if (_allPlaces.isNotEmpty) {
                      _onPlaceSelected(_allPlaces.first);
                    }
                  },
                ),
                const SizedBox(height: 12),

                // 2D / 3D Toggle Circle Button (Google Earth Style)
                GestureDetector(
                  onTap: _toggle2d3d,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _is3dPitch ? const Color(0xFF00E5FF) : Colors.white24,
                        width: _is3dPitch ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _is3dPitch ? '2D' : '3D',
                      style: TextStyle(
                        color: _is3dPitch ? const Color(0xFF00E5FF) : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 5. Selected Place Card overlay ──────────────────────────────
          if (_selectedPlace != null)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedPlace!.type == 'village' ? Icons.location_on : Icons.pentagon,
                      color: _selectedPlace!.type == 'village' ? AppTheme.greenAccent : const Color(0xFF00E5FF),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedPlace!.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedPlace!.subtitle,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.map_rounded, size: 14, color: Colors.black),
                      label: const Text(
                        '2D MAP',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        Navigator.pop(
                          context,
                          LatLng(_selectedPlace!.lat, _selectedPlace!.lng),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _selectedPlace = null),
                    ),
                  ],
                ),
              ),
            ),

          // ── 6. Bottom Drawer: Saved Villages & Polygons ─────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: const Border(
                  top: BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Row(
                      children: [
                        const Text(
                          'FLY TO SAVED TERRAIN:',
                          style: TextStyle(
                            color: Colors.white70,
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
                                const SizedBox(width: 6),
                                _FilterChip(
                                  label: 'Villages (${_allPlaces.where((p) => p.type == 'village').length})',
                                  isSelected: _selectedFilter == 'village',
                                  onTap: () => setState(() => _selectedFilter = 'village'),
                                ),
                                const SizedBox(width: 6),
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
                  const Divider(height: 1, color: Colors.white12),
                  Expanded(
                    child: _filteredPlaces.isEmpty
                        ? const Center(
                            child: Text(
                              'No saved field polygons or villages yet.',
                              style: TextStyle(color: Colors.white38, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _filteredPlaces.length,
                            itemBuilder: (context, idx) {
                              final place = _filteredPlaces[idx];
                              final isSelected = _selectedPlace?.id == place.id;
                              return GestureDetector(
                                onTap: () => _onPlaceSelected(place),
                                child: Container(
                                  width: 160,
                                  margin: const EdgeInsets.only(right: 10),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                                        : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF00E5FF) : Colors.white12,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            place.type == 'village' ? Icons.location_on : Icons.pentagon,
                                            color: place.type == 'village'
                                                ? AppTheme.greenAccent
                                                : const Color(0xFF00E5FF),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              place.title,
                                              style: TextStyle(
                                                color: isSelected ? const Color(0xFF00E5FF) : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        place.subtitle,
                                        style: const TextStyle(color: Colors.white60, fontSize: 10),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 6,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF) : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFF00E5FF) : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TerrainItem {
  final String id;
  final String title;
  final String subtitle;
  final double lat;
  final double lng;
  final String type; // 'village', 'polygon', 'kml'
  final double areaHectares;
  final String coordsJson;
  final String color;

  const _TerrainItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lng,
    required this.type,
    required this.areaHectares,
    required this.coordsJson,
    required this.color,
  });
}
