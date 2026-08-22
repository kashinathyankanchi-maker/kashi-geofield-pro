import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Data model for one Wayback imagery release
// ---------------------------------------------------------------------------

class WaybackRelease {
  final String title;       // e.g. "World Imagery (Wayback 2024-03-15)"
  final String date;        // e.g. "2024-03-15"
  final int releaseId;      // numeric ID used in tile URL
  final String identifier;  // e.g. "WB_2024_R03"

  const WaybackRelease({
    required this.title,
    required this.date,
    required this.releaseId,
    required this.identifier,
  });
}

// ---------------------------------------------------------------------------
// Service: fetch available Wayback releases from ESRI
// ---------------------------------------------------------------------------

class WaybackService {
  static const _capabilitiesUrl =
      'https://wayback.maptiles.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/WMTS/1.0.0/WMTSCapabilities.xml';

  /// Returns list of available historical imagery releases, newest first.
  static Future<List<WaybackRelease>> fetchReleases() async {
    final resp = await http
        .get(Uri.parse(_capabilitiesUrl))
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw Exception('Failed to load Wayback releases (${resp.statusCode})');
    }

    final body = resp.body;
    final releases = <WaybackRelease>[];

    // Parse tile ID from ResourceURL template attributes
    // Pattern: tile/{releaseId}/{TileMatrix}/{TileRow}/{TileCol}
    final tileIdRegex = RegExp(r'MapServer/tile/(\d+)/\{TileMatrix\}');

    // Parse titles like "World Imagery (Wayback 2024-03-15)"
    final titleRegex = RegExp(r'<ows:Title>World Imagery \(Wayback ([^)]+)\)</ows:Title>');
    final identifierRegex = RegExp(r'<ows:Identifier>(WB_[^<]+)</ows:Identifier>');

    // Split by <Layer> to process each release block
    final layers = body.split('<Layer>');

    for (final layer in layers.skip(1)) {
      final titleMatch = titleRegex.firstMatch(layer);
      final tileIdMatch = tileIdRegex.firstMatch(layer);
      final identifierMatch = identifierRegex.firstMatch(layer);

      if (titleMatch != null && tileIdMatch != null) {
        final dateStr = titleMatch.group(1)!.trim(); // "2024-03-15"
        final releaseId = int.tryParse(tileIdMatch.group(1)!) ?? 0;
        final identifier = identifierMatch?.group(1) ?? '';

        if (releaseId > 0) {
          releases.add(WaybackRelease(
            title: 'World Imagery – $dateStr',
            date: dateStr,
            releaseId: releaseId,
            identifier: identifier,
          ));
        }
      }
    }

    return releases; // already newest-first from ESRI
  }

  /// Build tile URL for a given release
  static String tileUrl(int releaseId) =>
      'https://wayback.maptiles.arcgis.com/arcgis/rest/services/World_Imagery/WMTS/1.0.0/default028mm/MapServer/tile/$releaseId/{z}/{y}/{x}';
}

// ---------------------------------------------------------------------------
// Historical Imagery Screen
// ---------------------------------------------------------------------------

class HistoricalImageryScreen extends StatefulWidget {
  /// Starting center — pass the current map center so we open in the right place
  final LatLng initialCenter;
  final double initialZoom;

  const HistoricalImageryScreen({
    super.key,
    required this.initialCenter,
    this.initialZoom = 14,
  });

  @override
  State<HistoricalImageryScreen> createState() => _HistoricalImageryScreenState();
}

class _HistoricalImageryScreenState extends State<HistoricalImageryScreen> {
  List<WaybackRelease> _releases = [];
  WaybackRelease? _selected;
  bool _loading = true;
  String? _error;
  bool _showSidebar = true;

  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadReleases();
  }

  Future<void> _loadReleases() async {
    try {
      final releases = await WaybackService.fetchReleases();
      if (mounted) {
        setState(() {
          _releases = releases;
          _selected = releases.isNotEmpty ? releases.first : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load imagery list: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Historical Imagery',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_selected != null)
              Text(
                _selected!.date,
                style: const TextStyle(fontSize: 11, color: Color(0xFF58A6FF)),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showSidebar ? Icons.layers_clear : Icons.layers,
                color: const Color(0xFF58A6FF)),
            tooltip: _showSidebar ? 'Hide date list' : 'Show date list',
            onPressed: () => setState(() => _showSidebar = !_showSidebar),
          ),
        ],
      ),
      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF58A6FF)),
          SizedBox(height: 16),
          Text('Loading available imagery dates...',
              style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Colors.redAccent, size: 64),
            const SizedBox(height: 16),
            Text(_error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() { _loading = true; _error = null; });
                _loadReleases();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF58A6FF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      children: [
        // ── Sidebar: date list ────────────────────────────────────────────
        if (_showSidebar)
          Container(
            width: 200,
            color: const Color(0xFF161B22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: const Color(0xFF21262D),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: Color(0xFF58A6FF), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${_releases.length} snapshots',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _releases.length,
                    itemBuilder: (ctx, i) {
                      final r = _releases[i];
                      final isSelected = r.releaseId == _selected?.releaseId;
                      return InkWell(
                        onTap: () => setState(() => _selected = r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF58A6FF).withOpacity(0.15)
                                : Colors.transparent,
                            border: isSelected
                                ? const Border(
                                    left: BorderSide(
                                        color: Color(0xFF58A6FF), width: 3))
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.date,
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF58A6FF)
                                      : Colors.white,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              Text(
                                r.identifier,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 10),
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

        // ── Map ────────────────────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.initialCenter,
                  initialZoom: widget.initialZoom,
                  minZoom: 3,
                  maxZoom: 20,
                ),
                children: [
                  // Wayback historical imagery tile layer
                  if (_selected != null)
                    TileLayer(
                      key: ValueKey(_selected!.releaseId),
                      urlTemplate:
                          WaybackService.tileUrl(_selected!.releaseId),
                      userAgentPackageName: 'com.kashi.geofield',
                      tileProvider: NetworkTileProvider(),
                      maxZoom: 20,
                      errorTileCallback: (tile, error, stackTrace) {},
                    ),
                ],
              ),

              // ── Floating controls ─────────────────────────────────────
              Positioned(
                right: 12,
                bottom: 80,
                child: Column(
                  children: [
                    _mapButton(
                      icon: Icons.add,
                      tooltip: 'Zoom In',
                      onTap: () {
                        final cam = _mapController.camera;
                        _mapController.move(cam.center, cam.zoom + 1);
                      },
                    ),
                    const SizedBox(height: 8),
                    _mapButton(
                      icon: Icons.remove,
                      tooltip: 'Zoom Out',
                      onTap: () {
                        final cam = _mapController.camera;
                        _mapController.move(cam.center, cam.zoom - 1);
                      },
                    ),
                    const SizedBox(height: 8),
                    _mapButton(
                      icon: Icons.my_location,
                      tooltip: 'Back to area',
                      onTap: () => _mapController.move(
                          widget.initialCenter, widget.initialZoom),
                    ),
                  ],
                ),
              ),

              // ── Bottom info bar ───────────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xCC161B22),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.satellite_alt,
                          color: Color(0xFF58A6FF), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selected != null
                              ? 'Showing: ${_selected!.title}'
                              : 'No imagery selected',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '© Esri, Maxar',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF21262D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Icon(icon, color: Colors.white70, size: 20),
        ),
      ),
    );
  }
}
