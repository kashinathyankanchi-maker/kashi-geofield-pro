import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/database/db_helper.dart';
import '../../core/utils/kml_engine.dart';
import '../../features/map/map_controller.dart';
import '../../features/offline_maps/offline_maps_screen.dart';
import '../../shared/theme.dart';
import 'earth_3d_screen.dart';

class Terrain3dScreen extends StatefulWidget {
  final LatLng? initialCenter;
  final String? initialTitle;
  final List<DrawnShape>? drawnShapes;
  final List<KmlShape>? kmlShapes;

  const Terrain3dScreen({
    super.key,
    this.initialCenter,
    this.initialTitle,
    this.drawnShapes,
    this.kmlShapes,
  });

  @override
  State<Terrain3dScreen> createState() => _Terrain3dScreenState();
}

class _Terrain3dScreenState extends State<Terrain3dScreen> {
  late final WebViewController _webController;
  bool _isLoading = true;
  bool _is3dPitch = true;
  String _selectedFilter = 'all';

  List<_TerrainItem> _allPlaces = [];
  _TerrainItem? _selectedPlace;

  // Local tile server for offline support
  HttpServer? _tileServer;
  int _tileServerPort = 0;
  bool _isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _startTileServer().then((_) {
      _loadDatabasePlaces();
      _initWebView();
    });
  }

  @override
  void dispose() {
    _tileServer?.close(force: true);
    super.dispose();
  }

  // ── Local Tile Server for Offline Support ─────────────────────────────────

  Future<void> _startTileServer() async {
    try {
      _tileServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _tileServerPort = _tileServer!.port;

      final docsDir = await getApplicationDocumentsDirectory();
      final offlineBase = '${docsDir.path}/offline_tiles';

      _tileServer!.listen((request) async {
        try {
          final segments = request.uri.pathSegments;
          // URL pattern: /{type}/{z}/{x}/{y}.png
          if (segments.length >= 4) {
            final type = segments[0]; // 'sat', 'dem'
            final z = segments[1];
            final x = segments[2];
            final yFile = segments[3]; // 'y.png'
            final y = yFile.replaceAll('.png', '');

            // Try local cache first
            final localPath = '$offlineBase/$type/$z/$x/$y.png';
            final localFile = File(localPath);
            if (await localFile.exists()) {
              final bytes = await localFile.readAsBytes();
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType('image', 'png')
                ..headers.set('Access-Control-Allow-Origin', '*')
                ..add(bytes);
              await request.response.close();
              return;
            }

            // Fallback to network
            String networkUrl;
            if (type == 'sat') {
              networkUrl = 'https://mt${int.parse(x) % 4}.google.com/vt/lyrs=s&x=$x&y=$y&z=$z';
            } else if (type == 'dem') {
              networkUrl = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$z/$x/$y.png';
            } else {
              networkUrl = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x';
            }

            // Proxy the network request
            try {
              final client = HttpClient();
              client.connectionTimeout = const Duration(seconds: 10);
              final netReq = await client.getUrl(Uri.parse(networkUrl));
              netReq.headers.set('User-Agent', 'KashiGeoFieldPro/1.0');
              final netResp = await netReq.close();

              if (netResp.statusCode == 200) {
                final bytes = <int>[];
                await for (final chunk in netResp) {
                  bytes.addAll(chunk);
                }

                // Cache the tile for future offline use
                try {
                  final cacheFile = File(localPath);
                  await cacheFile.parent.create(recursive: true);
                  await cacheFile.writeAsBytes(bytes);
                } catch (_) {}

                request.response
                  ..statusCode = HttpStatus.ok
                  ..headers.contentType = ContentType('image', 'png')
                  ..headers.set('Access-Control-Allow-Origin', '*')
                  ..add(bytes);
                await request.response.close();
                return;
              }
            } catch (_) {
              // Network failed — offline mode
              if (mounted && !_isOfflineMode) {
                setState(() => _isOfflineMode = true);
              }
            }
          }

          request.response
            ..statusCode = HttpStatus.notFound
            ..headers.set('Access-Control-Allow-Origin', '*');
          await request.response.close();
        } catch (_) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('Tile server failed: $e');
      // Fallback: use direct URLs
      _tileServerPort = 0;
    }
  }

  // ── Load Database Places ──────────────────────────────────────────────────

  Future<void> _loadDatabasePlaces() async {
    try {
      final db = DbHelper();
      final vList = await db.getAllVillages();
      final pList = await db.getAllPolygons();

      final List<_TerrainItem> items = [];

      // Villages
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

      // User polygons
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

      // Markers from DrawnShapes
      if (widget.drawnShapes != null) {
        for (final shape in widget.drawnShapes!) {
          if (shape.type == DrawMode.marker && shape.points.isNotEmpty) {
            final pt = shape.points.first;
            items.add(_TerrainItem(
              id: 'm_${shape.id}',
              title: shape.name,
              subtitle: '${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)}',
              lat: pt.latitude,
              lng: pt.longitude,
              type: 'marker',
              areaHectares: 0,
              coordsJson: jsonEncode([{'lat': pt.latitude, 'lng': pt.longitude}]),
              color: '#${shape.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
            ));
          } else if (shape.type == DrawMode.path && shape.points.length >= 2) {
            double lat = 0, lng = 0;
            for (final pt in shape.points) {
              lat += pt.latitude;
              lng += pt.longitude;
            }
            lat /= shape.points.length;
            lng /= shape.points.length;
            items.add(_TerrainItem(
              id: 'path_${shape.id}',
              title: shape.name,
              subtitle: 'Path: ${shape.perimeterMeters.toStringAsFixed(0)} m',
              lat: lat,
              lng: lng,
              type: 'path',
              areaHectares: 0,
              coordsJson: jsonEncode(shape.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList()),
              color: '#${shape.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
            ));
          }
        }
      }

      // KML parsed shapes (with real coordinates)
      if (widget.kmlShapes != null) {
        for (int i = 0; i < widget.kmlShapes!.length; i++) {
          final shape = widget.kmlShapes![i];
          if (shape.coordinates.isNotEmpty) {
            double lat = 0, lng = 0;
            for (final c in shape.coordinates) {
              lat += (c['lat'] ?? 0.0);
              lng += (c['lng'] ?? 0.0);
            }
            lat /= shape.coordinates.length;
            lng /= shape.coordinates.length;
            items.add(_TerrainItem(
              id: 'kml_$i',
              title: shape.name,
              subtitle: 'KML ${shape.type}: ${shape.coordinates.length} points',
              lat: lat,
              lng: lng,
              type: 'kml',
              areaHectares: 0,
              coordsJson: jsonEncode(shape.coordinates),
              color: shape.color,
            ));
          }
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

  // ── WebView Init ──────────────────────────────────────────────────────────

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

  // ── MapLibre GL JS HTML ───────────────────────────────────────────────────

  String _buildMapLibreHtml(double centerLat, double centerLng) {
    final satTileUrl = _tileServerPort > 0
        ? 'http://127.0.0.1:$_tileServerPort/sat/{z}/{x}/{y}.png'
        : 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
    final demTileUrl = _tileServerPort > 0
        ? 'http://127.0.0.1:$_tileServerPort/dem/{z}/{x}/{y}.png'
        : 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';

    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <title>3D Terrain Map</title>
    <script src="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"></script>
    <link href="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css" rel="stylesheet" />
    <style>
        * { box-sizing: border-box; }
        body { margin: 0; padding: 0; background: #0a0a0a; overflow: hidden; font-family: -apple-system, sans-serif; }
        #map { position: absolute; top: 0; bottom: 0; width: 100%; height: 100%; }
        .maplibregl-ctrl-attribution { display: none !important; }
        .maplibregl-ctrl-logo { display: none !important; }
        .maplibregl-popup-content {
            background: rgba(5, 15, 30, 0.92);
            color: #00E5FF;
            border: 1.5px solid rgba(0, 229, 255, 0.6);
            border-radius: 10px;
            padding: 8px 14px;
            font-size: 13px;
            font-weight: 600;
            backdrop-filter: blur(8px);
            box-shadow: 0 4px 20px rgba(0,229,255,0.2);
        }
        .maplibregl-popup-tip { border-top-color: rgba(5, 15, 30, 0.92) !important; }
        .maplibregl-popup-close-button { color: #00E5FF; font-size: 16px; }
    </style>
</head>
<body>
    <div id="map"></div>
    <script>
        // ── Pending data queue: store GeoJSON before map is ready ──────────
        var _ready = false;
        var _pendingPolygons = null;
        var _pendingPaths = null;
        var _pendingMarkers = null;
        var _pendingKml = null;
        var _pendingOverlays = [];

        const map = new maplibregl.Map({
            container: 'map',
            style: {
                version: 8,
                glyphs: 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
                sources: {
                    'satellite-tiles': {
                        type: 'raster',
                        tiles: ['$satTileUrl'],
                        tileSize: 256,
                        maxzoom: 20,
                        attribution: ''
                    },
                    'terrain-dem': {
                        type: 'raster-dem',
                        tiles: ['$demTileUrl'],
                        encoding: 'terrarium',
                        tileSize: 256,
                        maxzoom: 15
                    },
                    'hillshade-dem': {
                        type: 'raster-dem',
                        tiles: ['$demTileUrl'],
                        encoding: 'terrarium',
                        tileSize: 256,
                        maxzoom: 15
                    }
                },
                layers: [
                    {
                        id: 'satellite-layer',
                        type: 'raster',
                        source: 'satellite-tiles',
                        minzoom: 0,
                        maxzoom: 22,
                        paint: { 'raster-resampling': 'linear' }
                    },
                    {
                        id: 'hillshade-layer',
                        type: 'hillshade',
                        source: 'hillshade-dem',
                        paint: {
                            'hillshade-exaggeration': 0.35,
                            'hillshade-shadow-color': '#000000',
                            'hillshade-highlight-color': '#ffffff',
                            'hillshade-illumination-direction': 315,
                            'hillshade-illumination-anchor': 'viewport'
                        }
                    }
                ],
                terrain: {
                    source: 'terrain-dem',
                    exaggeration: 2.2
                },
                sky: {
                    'sky-type': 'atmosphere',
                    'sky-atmosphere-sun': [0.0, 90.0],
                    'sky-atmosphere-sun-intensity': 15,
                    'sky-atmosphere-halo-color': 'rgba(255, 255, 255, 0.5)',
                    'sky-atmosphere-color': 'rgba(135, 206, 235, 1.0)'
                }
            },
            center: [$centerLng, $centerLat],
            zoom: 13.5,
            pitch: 62,
            bearing: -15,
            maxPitch: 85,
            minZoom: 2,
            attributionControl: false,
            antialias: true
        });

        map.addControl(new maplibregl.NavigationControl({
            showCompass: true,
            showZoom: true,
            visualizePitch: true
        }), 'top-right');

        map.on('load', function() {
            // Atmospheric fog
            try {
                map.setFog({
                    range: [1.5, 10],
                    color: 'rgba(200, 220, 255, 0.12)',
                    'horizon-blend': 0.08,
                    'high-color': '#add8e6',
                    'space-color': '#0a0a2e',
                    'star-intensity': 0.3
                });
            } catch(e) {}

            // ── User polygons ───────────────────────────────────────────────
            map.addSource('user-polygons', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
            map.addLayer({ id: 'user-polygons-fill', type: 'fill', source: 'user-polygons',
                paint: { 'fill-color': ['get', 'color'], 'fill-opacity': 0.35 }
            });
            map.addLayer({ id: 'user-polygons-line', type: 'line', source: 'user-polygons',
                paint: { 'line-color': ['get', 'color'], 'line-width': 3.5, 'line-opacity': 1.0 }
            });
            map.addLayer({ id: 'user-polygons-label', type: 'symbol', source: 'user-polygons',
                layout: { 'text-field': ['get', 'title'], 'text-size': 13, 'text-anchor': 'center', 'text-allow-overlap': false },
                paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 2 }
            });

            // ── Paths ───────────────────────────────────────────────────────
            map.addSource('user-paths', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
            map.addLayer({ id: 'user-paths-line', type: 'line', source: 'user-paths',
                paint: { 'line-color': ['get', 'color'], 'line-width': 4, 'line-opacity': 0.9 }
            });
            map.addLayer({ id: 'user-paths-label', type: 'symbol', source: 'user-paths',
                layout: { 'symbol-placement': 'line-center', 'text-field': ['get', 'title'], 'text-size': 11 },
                paint: { 'text-color': '#FFD740', 'text-halo-color': '#000000', 'text-halo-width': 1.5 }
            });

            // ── Markers ─────────────────────────────────────────────────────
            map.addSource('user-markers', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
            map.addLayer({ id: 'user-markers-glow', type: 'circle', source: 'user-markers',
                paint: { 'circle-radius': 16, 'circle-color': ['get', 'color'], 'circle-opacity': 0.18, 'circle-blur': 1 }
            });
            map.addLayer({ id: 'user-markers-circle', type: 'circle', source: 'user-markers',
                paint: { 'circle-radius': 8, 'circle-color': ['get', 'color'], 'circle-stroke-width': 3, 'circle-stroke-color': '#ffffff', 'circle-opacity': 1.0 }
            });
            map.addLayer({ id: 'user-markers-label', type: 'symbol', source: 'user-markers',
                layout: { 'text-field': ['get', 'title'], 'text-size': 13, 'text-offset': [0, 1.8], 'text-anchor': 'top', 'text-allow-overlap': false },
                paint: { 'text-color': '#00E5FF', 'text-halo-color': '#000000', 'text-halo-width': 2 }
            });

            // ── KML shapes ──────────────────────────────────────────────────
            map.addSource('kml-shapes', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
            map.addLayer({ id: 'kml-shapes-fill', type: 'fill', source: 'kml-shapes',
                filter: ['==', ['geometry-type'], 'Polygon'],
                paint: { 'fill-color': ['get', 'color'], 'fill-opacity': 0.3 }
            });
            map.addLayer({ id: 'kml-shapes-line', type: 'line', source: 'kml-shapes',
                paint: { 'line-color': ['get', 'color'], 'line-width': 3, 'line-opacity': 0.95 }
            });
            map.addLayer({ id: 'kml-shapes-label', type: 'symbol', source: 'kml-shapes',
                layout: { 'text-field': ['get', 'title'], 'text-size': 12, 'text-anchor': 'center', 'text-allow-overlap': false },
                paint: { 'text-color': '#FF8A65', 'text-halo-color': '#000000', 'text-halo-width': 2 }
            });

            // ── Click popups for all overlay layers ─────────────────────────
            ['user-polygons-fill','kml-shapes-fill','user-markers-circle'].forEach(function(layerId) {
                map.on('click', layerId, function(e) {
                    var props = e.features[0].properties;
                    var name = props.title || props.name || 'Area';
                    new maplibregl.Popup({ offset: 10, closeButton: true, maxWidth: '220px' })
                        .setLngLat(e.lngLat)
                        .setHTML('<b>' + name + '</b>')
                        .addTo(map);
                });
                map.on('mouseenter', layerId, function() { map.getCanvas().style.cursor = 'pointer'; });
                map.on('mouseleave', layerId, function() { map.getCanvas().style.cursor = ''; });
            });

            // Mark ready and flush any pending data
            _ready = true;
            if (_pendingPolygons) { _applyPolygons(_pendingPolygons); _pendingPolygons = null; }
            if (_pendingPaths)    { _applyPaths(_pendingPaths);       _pendingPaths = null; }
            if (_pendingMarkers)  { _applyMarkers(_pendingMarkers);   _pendingMarkers = null; }
            if (_pendingKml)      { _applyKml(_pendingKml);           _pendingKml = null; }
            _pendingOverlays.forEach(function(o) { _applyOverlay(o); });
            _pendingOverlays = [];
        });

        // ── Internal apply functions (only called when map is ready) ────────
        function _applyPolygons(data) {
            try { map.getSource('user-polygons').setData(JSON.parse(data)); } catch(e) {}
        }
        function _applyPaths(data) {
            try { map.getSource('user-paths').setData(JSON.parse(data)); } catch(e) {}
        }
        function _applyMarkers(data) {
            try { map.getSource('user-markers').setData(JSON.parse(data)); } catch(e) {}
        }
        function _applyKml(data) {
            try { map.getSource('kml-shapes').setData(JSON.parse(data)); } catch(e) {}
        }
        function _applyOverlay(o) {
            try {
                var srcId = 'img-overlay-' + o.id;
                var layId = 'img-overlay-layer-' + o.id;
                if (map.getSource(srcId)) return;
                map.addSource(srcId, {
                    type: 'image',
                    url: o.url,
                    coordinates: [
                        [o.west, o.north],
                        [o.east, o.north],
                        [o.east, o.south],
                        [o.west, o.south]
                    ]
                });
                map.addLayer({ id: layId, type: 'raster', source: srcId, paint: { 'raster-opacity': 0.75 } }, 'user-polygons-fill');
            } catch(e) {}
        }

        // ── Public API (called from Flutter via runJavaScript) ──────────────
        function updateGeoJson(geojsonStr) {
            if (_ready) { _applyPolygons(geojsonStr); } else { _pendingPolygons = geojsonStr; }
        }
        function updatePaths(geojsonStr) {
            if (_ready) { _applyPaths(geojsonStr); } else { _pendingPaths = geojsonStr; }
        }
        function updateMarkers(geojsonStr) {
            if (_ready) { _applyMarkers(geojsonStr); } else { _pendingMarkers = geojsonStr; }
        }
        function updateKmlShapes(geojsonStr) {
            if (_ready) { _applyKml(geojsonStr); } else { _pendingKml = geojsonStr; }
        }
        function addImageOverlay(id, url, north, south, east, west) {
            var o = { id: id, url: url, north: north, south: south, east: east, west: west };
            if (_ready) { _applyOverlay(o); } else { _pendingOverlays.push(o); }
        }
        function flyToPlace(lat, lng, zoom, pitch, bearing) {
            map.flyTo({ center: [lng, lat], zoom: zoom || 14, pitch: pitch !== undefined ? pitch : 62,
                bearing: bearing || 0, duration: 2200, essential: true,
                easing: function(t) { return t < 0.5 ? 2*t*t : -1+(4-2*t)*t; }
            });
        }
        function toggle3dMode(is3d) {
            map.easeTo({ pitch: is3d ? 62 : 0, bearing: is3d ? -15 : 0, duration: 1200 });
            map.setTerrain(is3d ? { source: 'terrain-dem', exaggeration: 2.2 } : null);
        }
        function resetNorth() { map.resetNorthPitch({ duration: 1000 }); }
        function setTerrainExaggeration(val) {
            try { map.setTerrain({ source: 'terrain-dem', exaggeration: val }); } catch(e) {}
        }
    </script>
</body>
</html>
''';
  }

  // ── GeoJSON Injection ─────────────────────────────────────────────────────

  void _injectGeoJsonToMap() {
    if (_allPlaces.isEmpty && (widget.kmlShapes == null || widget.kmlShapes!.isEmpty)) return;
    try {
      // ── Polygons (villages + user polygons) ───────────────────────────
      final List<Map<String, dynamic>> polygonFeatures = [];
      for (final place in _allPlaces) {
        if (place.type == 'village' || place.type == 'polygon') {
          try {
            final List<dynamic> coords = jsonDecode(place.coordsJson);
            if (coords.length >= 3) {
              final List<List<double>> ring = coords
                  .map((c) => [(c['lng'] as num).toDouble(), (c['lat'] as num).toDouble()])
                  .toList();
              ring.add(ring.first); // close polygon
              polygonFeatures.add({
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
      final polyJson = jsonEncode({
        'type': 'FeatureCollection',
        'features': polygonFeatures,
      }).replaceAll("'", "\\'");
      _webController.runJavaScript("updateGeoJson('$polyJson');");

      // ── Paths (user paths + GPS tracks) ───────────────────────────────
      final List<Map<String, dynamic>> pathFeatures = [];
      for (final place in _allPlaces) {
        if (place.type == 'path') {
          try {
            final List<dynamic> coords = jsonDecode(place.coordsJson);
            if (coords.length >= 2) {
              final List<List<double>> line = coords
                  .map((c) => [(c['lng'] as num).toDouble(), (c['lat'] as num).toDouble()])
                  .toList();
              pathFeatures.add({
                'type': 'Feature',
                'properties': {
                  'id': place.id,
                  'title': place.title,
                  'color': place.color,
                },
                'geometry': {
                  'type': 'LineString',
                  'coordinates': line,
                }
              });
            }
          } catch (_) {}
        }
      }
      final pathJson = jsonEncode({
        'type': 'FeatureCollection',
        'features': pathFeatures,
      }).replaceAll("'", "\\'");
      _webController.runJavaScript("updatePaths('$pathJson');");

      // ── Markers ───────────────────────────────────────────────────────
      final List<Map<String, dynamic>> markerFeatures = [];
      for (final place in _allPlaces) {
        if (place.type == 'marker') {
          markerFeatures.add({
            'type': 'Feature',
            'properties': {
              'id': place.id,
              'title': place.title,
              'color': place.color,
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [place.lng, place.lat],
            }
          });
        }
      }
      final markerJson = jsonEncode({
        'type': 'FeatureCollection',
        'features': markerFeatures,
      }).replaceAll("'", "\\'");
      _webController.runJavaScript("updateMarkers('$markerJson');");

      // ── KML Shapes ────────────────────────────────────────────────────
      final List<Map<String, dynamic>> kmlFeatures = [];

      // From widget.kmlShapes (parsed KML data passed from 2D map)
      if (widget.kmlShapes != null && widget.kmlShapes!.isNotEmpty) {
        for (final shape in widget.kmlShapes!) {
          if (shape.coordinates.length >= 2) {
            final coords = shape.coordinates
                .map((c) => [c['lng'] ?? 0.0, c['lat'] ?? 0.0])
                .toList();

            if (shape.type == 'polygon' && coords.length >= 3) {
              final ring = List<List<double>>.from(coords.map((c) => [c[0], c[1]]));
              ring.add(ring.first);
              kmlFeatures.add({
                'type': 'Feature',
                'properties': {'title': shape.name, 'color': shape.color},
                'geometry': {'type': 'Polygon', 'coordinates': [ring]},
              });
            } else if (shape.type == 'path' || shape.type == 'line') {
              kmlFeatures.add({
                'type': 'Feature',
                'properties': {'title': shape.name, 'color': shape.color},
                'geometry': {'type': 'LineString', 'coordinates': coords},
              });
            }
          } else if (shape.coordinates.length == 1 && shape.type == 'marker') {
            final c = shape.coordinates.first;
            kmlFeatures.add({
              'type': 'Feature',
              'properties': {'title': shape.name, 'color': shape.color},
              'geometry': {'type': 'Point', 'coordinates': [c['lng'] ?? 0.0, c['lat'] ?? 0.0]},
            });
          }
        }
      }

      // Also add KML items from _allPlaces (parsed with real coords)
      for (final place in _allPlaces) {
        if (place.type == 'kml' && place.coordsJson != '[]') {
          try {
            final List<dynamic> coords = jsonDecode(place.coordsJson);
            if (coords.length >= 3) {
              final List<List<double>> ring = coords
                  .map((c) => [(c['lng'] as num).toDouble(), (c['lat'] as num).toDouble()])
                  .toList();
              ring.add(ring.first);
              kmlFeatures.add({
                'type': 'Feature',
                'properties': {'id': place.id, 'title': place.title, 'color': place.color},
                'geometry': {'type': 'Polygon', 'coordinates': [ring]},
              });
            } else if (coords.length >= 2) {
              final List<List<double>> line = coords
                  .map((c) => [(c['lng'] as num).toDouble(), (c['lat'] as num).toDouble()])
                  .toList();
              kmlFeatures.add({
                'type': 'Feature',
                'properties': {'id': place.id, 'title': place.title, 'color': place.color},
                'geometry': {'type': 'LineString', 'coordinates': line},
              });
            }
          } catch (_) {}
        }
      }

      if (kmlFeatures.isNotEmpty) {
        final kmlJson = jsonEncode({
          'type': 'FeatureCollection',
          'features': kmlFeatures,
        }).replaceAll("'", "\\'");
        _webController.runJavaScript("updateKmlShapes('$kmlJson');");
      }
    } catch (_) {}
  }

  // ── Actions ───────────────────────────────────────────────────────────────

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

  void _onDownload3dArea() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OfflineMapsScreen(),
      ),
    );
  }

  List<_TerrainItem> get _filteredPlaces {
    if (_selectedFilter == 'all') return _allPlaces;
    return _allPlaces.where((p) => p.type == _selectedFilter).toList();
  }

  // ── UI Build ──────────────────────────────────────────────────────────────

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
                          // Online/Offline status indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isOfflineMode
                                  ? Colors.orange.withValues(alpha: 0.2)
                                  : const Color(0xFF00E5FF).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isOfflineMode ? Icons.cloud_off : Icons.cloud_done,
                                  size: 10,
                                  color: _isOfflineMode ? Colors.orange : const Color(0xFF00E5FF),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isOfflineMode ? 'OFFLINE' : '3D LIVE',
                                  style: TextStyle(
                                    color: _isOfflineMode ? Colors.orange : const Color(0xFF00E5FF),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
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

          // ── 4. Right Control Bar ────────────────────────────────────────
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

                // Download 3D Area for offline
                _ControlButton(
                  icon: Icons.download_rounded,
                  color: const Color(0xFF29B6F6),
                  tooltip: 'Download 3D Area Offline',
                  onTap: _onDownload3dArea,
                ),
                const SizedBox(height: 12),

                // 2D / 3D Toggle Circle Button
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
                      _selectedPlace!.type == 'village'
                          ? Icons.location_on
                          : _selectedPlace!.type == 'marker'
                              ? Icons.place_rounded
                              : _selectedPlace!.type == 'path'
                                  ? Icons.timeline_rounded
                                  : Icons.pentagon,
                      color: _selectedPlace!.type == 'village'
                          ? AppTheme.greenAccent
                          : _selectedPlace!.type == 'marker'
                              ? Colors.red
                              : _selectedPlace!.type == 'path'
                                  ? Colors.amber
                                  : const Color(0xFF00E5FF),
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

          // ── 6. Bottom Drawer: Saved Data ────────────────────────────────
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
                          'FLY TO:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                                const SizedBox(width: 6),
                                _FilterChip(
                                  label: 'Markers (${_allPlaces.where((p) => p.type == 'marker').length})',
                                  isSelected: _selectedFilter == 'marker',
                                  onTap: () => setState(() => _selectedFilter = 'marker'),
                                ),
                                const SizedBox(width: 6),
                                _FilterChip(
                                  label: 'Paths (${_allPlaces.where((p) => p.type == 'path').length})',
                                  isSelected: _selectedFilter == 'path',
                                  onTap: () => setState(() => _selectedFilter = 'path'),
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
                              'No saved data in this category yet.',
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
                                            place.type == 'village'
                                                ? Icons.location_on
                                                : place.type == 'marker'
                                                    ? Icons.place_rounded
                                                    : place.type == 'path'
                                                        ? Icons.timeline_rounded
                                                        : place.type == 'kml'
                                                            ? Icons.layers
                                                            : Icons.pentagon,
                                            color: place.type == 'village'
                                                ? AppTheme.greenAccent
                                                : place.type == 'marker'
                                                    ? Colors.red
                                                    : place.type == 'path'
                                                        ? Colors.amber
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
  final String type; // 'village', 'polygon', 'kml', 'marker', 'path'
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
