import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class OfflineRegion {
  final String id;
  final String name;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final int minZoom;
  final int maxZoom;
  final DateTime createdAt;
  final int downloadedTiles;
  final int totalTiles;

  OfflineRegion({
    required this.id,
    required this.name,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.minZoom,
    required this.maxZoom,
    required this.createdAt,
    this.downloadedTiles = 0,
    this.totalTiles = 0,
  });

  bool get isComplete => downloadedTiles >= totalTiles && totalTiles > 0;
  double get progress => totalTiles == 0 ? 0 : downloadedTiles / totalTiles;

  /// Calculate all tile XYZ coords in bounding box for a zoom level
  static List<List<int>> tilesForBbox(
      double minLat, double maxLat, double minLng, double maxLng, int z) {
    final tiles = <List<int>>[];
    final xMin = _lngToX(minLng, z);
    final xMax = _lngToX(maxLng, z);
    final yMin = _latToY(maxLat, z); // y is inverted
    final yMax = _latToY(minLat, z);
    for (int x = xMin; x <= xMax; x++) {
      for (int y = yMin; y <= yMax; y++) {
        tiles.add([z, x, y]);
      }
    }
    return tiles;
  }

  static int _lngToX(double lng, int z) =>
      ((lng + 180) / 360 * pow(2, z)).floor();

  static int _latToY(double lat, int z) {
    final latRad = lat * pi / 180;
    return ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * pow(2, z))
        .floor();
  }

  List<List<int>> get allTiles {
    final all = <List<int>>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      all.addAll(tilesForBbox(minLat, maxLat, minLng, maxLng, z));
    }
    return all;
  }

  int get estimatedTileCount => allTiles.length;
  double get estimatedMB => estimatedTileCount * 15 / 1024;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'minLat': minLat,
        'maxLat': maxLat,
        'minLng': minLng,
        'maxLng': maxLng,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'createdAt': createdAt.toIso8601String(),
        'downloadedTiles': downloadedTiles,
        'totalTiles': totalTiles,
      };

  factory OfflineRegion.fromJson(Map<String, dynamic> json) => OfflineRegion(
        id: json['id'] as String,
        name: json['name'] as String,
        minLat: (json['minLat'] as num).toDouble(),
        maxLat: (json['maxLat'] as num).toDouble(),
        minLng: (json['minLng'] as num).toDouble(),
        maxLng: (json['maxLng'] as num).toDouble(),
        minZoom: json['minZoom'] as int,
        maxZoom: json['maxZoom'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        downloadedTiles: (json['downloadedTiles'] as num?)?.toInt() ?? 0,
        totalTiles: (json['totalTiles'] as num?)?.toInt() ?? 0,
      );

  OfflineRegion copyWith({int? downloadedTiles, int? totalTiles}) =>
      OfflineRegion(
        id: id,
        name: name,
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
        minZoom: minZoom,
        maxZoom: maxZoom,
        createdAt: createdAt,
        downloadedTiles: downloadedTiles ?? this.downloadedTiles,
        totalTiles: totalTiles ?? this.totalTiles,
      );
}

// ---------------------------------------------------------------------------
// Tile Downloader
// ---------------------------------------------------------------------------

class TileDownloader {
  static const String _tileBaseUrl = 'https://tile.openstreetmap.org';
  static const String _satBaseUrl = 'https://mt0.google.com/vt/lyrs=s';

  static Future<String> _tileDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/offline_tiles';
  }

  static String tilePath(int z, int x, int y) => ''; // resolved asynchronously

  static Future<String> _tilePath(int z, int x, int y,
      {bool satellite = false}) async {
    final base = await _tileDir();
    final sub = satellite ? 'sat' : 'osm';
    return '$base/$sub/$z/$x/$y.png';
  }

  static Future<bool> tileExists(int z, int x, int y,
      {bool satellite = false}) async {
    final path = await _tilePath(z, x, y, satellite: satellite);
    return File(path).exists();
  }

  /// Download a single tile and cache it. Returns true on success.
  static Future<bool> downloadTile(int z, int x, int y,
      {bool satellite = false}) async {
    try {
      final path = await _tilePath(z, x, y, satellite: satellite);
      final file = File(path);
      if (await file.exists()) return true; // already cached

      await file.parent.create(recursive: true);

      // Ensure .nomedia exists in the root offline_tiles dir to hide all PNGs from gallery
      final base = await _tileDir();
      final nomedia = File('$base/.nomedia');
      if (!await nomedia.exists()) await nomedia.create();


      final url = satellite
          ? '$_satBaseUrl&x=$x&y=$y&z=$z'
          : '$_tileBaseUrl/$z/$x/$y.png';

      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'KashiGeoFieldPro/1.0'});

      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(resp.bodyBytes);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get cached tile bytes, or null if not cached.
  static Future<Uint8List?> getCachedTile(int z, int x, int y,
      {bool satellite = false}) async {
    try {
      final path = await _tilePath(z, x, y, satellite: satellite);
      final f = File(path);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }

  /// Delete all cached tiles for a region (by removing all tiles in bbox)
  static Future<void> deleteTiles(OfflineRegion region,
      {bool satellite = false}) async {
    final base = await _tileDir();
    final sub = satellite ? 'sat' : 'osm';
    for (final tile in region.allTiles) {
      final path = '$base/$sub/${tile[0]}/${tile[1]}/${tile[2]}.png';
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }

  /// Get total size of all cached tiles in MB
  static Future<double> getCacheSizeMB() async {
    try {
      final dir = Directory(await _tileDir());
      if (!await dir.exists()) return 0.0;
      int bytes = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          bytes += await entity.length();
        }
      }
      return bytes / 1024 / 1024;
    } catch (_) {
      return 0.0;
    }
  }

  static Future<void> clearAllCache() async {
    try {
      final dir = Directory(await _tileDir());
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // DEM (Digital Elevation Model) tile support for 3D terrain
  static const String _demBaseUrl = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium';

  static Future<String> _demTilePath(int z, int x, int y) async {
    final base = await _tileDir();
    return '$base/dem/$z/$x/$y.png';
  }

  static Future<bool> demTileExists(int z, int x, int y) async {
    final path = await _demTilePath(z, x, y);
    return File(path).exists();
  }

  static Future<bool> downloadDemTile(int z, int x, int y) async {
    try {
      final path = await _demTilePath(z, x, y);
      final file = File(path);
      if (await file.exists()) return true;

      await file.parent.create(recursive: true);

      final url = '$_demBaseUrl/$z/$x/$y.png';
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'KashiGeoFieldPro/1.0'});

      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(resp.bodyBytes);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List?> getCachedDemTile(int z, int x, int y) async {
    try {
      final path = await _demTilePath(z, x, y);
      final f = File(path);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }
}

// ---------------------------------------------------------------------------
// Offline Maps Screen
// ---------------------------------------------------------------------------

class OfflineMapsScreen extends StatefulWidget {
  final Map<String, double>? initialBounds;

  const OfflineMapsScreen({super.key, this.initialBounds});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  List<OfflineRegion> _regions = [];
  bool _isDownloading = false;
  String? _downloadingId;
  int _downloadProgress = 0;
  int _downloadTotal = 0;
  bool _cancelDownload = false;
  double _cacheSizeMB = 0;
  bool _satellite = true;

  // Form controllers
  final _nameCtrl = TextEditingController(text: 'My Region');
  final _minLatCtrl = TextEditingController();
  final _maxLatCtrl = TextEditingController();
  final _minLngCtrl = TextEditingController();
  final _maxLngCtrl = TextEditingController();
  int _minZoom = 10;
  int _maxZoom = 18;

  @override
  void initState() {
    super.initState();
    if (widget.initialBounds != null) {
      _minLatCtrl.text = widget.initialBounds!['minLat']!.toStringAsFixed(6);
      _maxLatCtrl.text = widget.initialBounds!['maxLat']!.toStringAsFixed(6);
      _minLngCtrl.text = widget.initialBounds!['minLng']!.toStringAsFixed(6);
      _maxLngCtrl.text = widget.initialBounds!['maxLng']!.toStringAsFixed(6);
    }
    _loadRegions();
    _refreshCacheSize();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _minLatCtrl.dispose();
    _maxLatCtrl.dispose();
    _minLngCtrl.dispose();
    _maxLngCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('offline_regions') ?? [];
    if (mounted) {
      setState(() {
        _regions =
            raw.map((s) => OfflineRegion.fromJson(jsonDecode(s))).toList();
      });
    }
  }

  Future<void> _saveRegions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('offline_regions',
        _regions.map((r) => jsonEncode(r.toJson())).toList());
  }

  Future<void> _refreshCacheSize() async {
    final mb = await TileDownloader.getCacheSizeMB();
    if (mounted) setState(() => _cacheSizeMB = mb);
  }

  // ── Download region ─────────────────────────────────────────────────────────

  Future<void> _downloadRegion(OfflineRegion region) async {
    final tiles = region.allTiles;
    if (tiles.isEmpty) {
      _showSnack('No tiles in this range');
      return;
    }

    // Warn if > 500 tiles
    if (tiles.length > 500) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Large Download',
              style: TextStyle(color: AppTheme.textPrimary)),
          content: Text(
            '${tiles.length} tiles (~${region.estimatedMB.toStringAsFixed(1)} MB).\n'
            'This may take several minutes and uses mobile data.\nContinue?',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Download')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _isDownloading = true;
      _downloadingId = region.id;
      _downloadProgress = 0;
      _downloadTotal = tiles.length;
      _cancelDownload = false;
    });

    int done = 0;
    int failed = 0;

    for (final tile in tiles) {
      if (_cancelDownload) break;
      final success = await TileDownloader.downloadTile(
          tile[0], tile[1], tile[2],
          satellite: _satellite);
      if (success) {
        done++;
      } else {
        failed++;
      }
      if (mounted) {
        setState(() => _downloadProgress = done);
        // Update region progress
        final idx = _regions.indexWhere((r) => r.id == region.id);
        if (idx >= 0) {
          _regions[idx] = _regions[idx]
              .copyWith(downloadedTiles: done, totalTiles: tiles.length);
        }
      }
      // Small delay to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 20));
    }

      // Also download DEM terrain tiles for 3D map (zoom 5-14)
      final demMinZoom = 5;
      final demMaxZoom = region.maxZoom > 14 ? 14 : region.maxZoom;
      for (int z = demMinZoom; z <= demMaxZoom; z++) {
        final demTiles = OfflineRegion.tilesForBbox(
            region.minLat, region.maxLat, region.minLng, region.maxLng, z);
        for (final tile in demTiles) {
          if (_cancelDownload) break;
          await TileDownloader.downloadDemTile(tile[0], tile[1], tile[2]);
        }
        if (_cancelDownload) break;
      }

    // Save final state
    final idx = _regions.indexWhere((r) => r.id == region.id);
    if (idx >= 0) {
      _regions[idx] = _regions[idx]
          .copyWith(downloadedTiles: done, totalTiles: tiles.length);
    }
    await _saveRegions();
    await _refreshCacheSize();

    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadingId = null;
      });
      _showSnack(_cancelDownload
          ? 'Download cancelled ($done tiles saved)'
          : 'Download complete! $done tiles (${failed > 0 ? "$failed failed" : "all ok"})');
    }
  }

  Future<void> _addRegion() async {
    final minLat = double.tryParse(_minLatCtrl.text.trim());
    final maxLat = double.tryParse(_maxLatCtrl.text.trim());
    final minLng = double.tryParse(_minLngCtrl.text.trim());
    final maxLng = double.tryParse(_maxLngCtrl.text.trim());
    final name = _nameCtrl.text.trim();

    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      _showSnack('Please fill all coordinate fields', isError: true);
      return;
    }
    if (minLat >= maxLat || minLng >= maxLng) {
      _showSnack('Min must be less than Max', isError: true);
      return;
    }

    final region = OfflineRegion(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isEmpty ? 'Region ${_regions.length + 1}' : name,
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      createdAt: DateTime.now(),
    );

    setState(() => _regions.add(region));
    await _saveRegions();
    _showSnack(
        'Region added: ${region.estimatedTileCount} tiles (~${region.estimatedMB.toStringAsFixed(1)} MB)');

    // Start download immediately
    await _downloadRegion(region);
  }

  Future<void> _deleteRegion(OfflineRegion region) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete Region',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Delete "${region.name}" and its cached tiles?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TileDownloader.deleteTiles(region, satellite: _satellite);
    setState(() => _regions.removeWhere((r) => r.id == region.id));
    await _saveRegions();
    await _refreshCacheSize();
    _showSnack('Region deleted');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : AppTheme.greenPrimary,
      behavior: SnackBarBehavior.floating,
    ));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Offline Maps',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
            tooltip: 'Clear All Cache',
            onPressed: _isDownloading
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppTheme.bgCard,
                        title: const Text('Clear Cache',
                            style: TextStyle(color: AppTheme.textPrimary)),
                        content: const Text('Delete all downloaded tiles?',
                            style: TextStyle(color: AppTheme.textSecondary)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await TileDownloader.clearAllCache();
                      await _refreshCacheSize();
                      _showSnack('Cache cleared');
                    }
                  },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── Cache info card ─────────────────────────────────────────────────
          _SectionCard(
            icon: Icons.storage_rounded,
            title: 'Cache Storage',
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_cacheSizeMB.toStringAsFixed(1)} MB used',
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const Text('Downloaded map tiles',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                // Tile type toggle
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      _TileToggle(
                          label: 'Street',
                          active: !_satellite,
                          onTap: () => setState(() => _satellite = false)),
                      _TileToggle(
                          label: 'Satellite',
                          active: _satellite,
                          onTap: () => setState(() => _satellite = true)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Download Region form ────────────────────────────────────────────
          _SectionCard(
            icon: Icons.download_rounded,
            title: 'Download New Region',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: _inputDeco('Region Name', Icons.label_rounded),
                ),
                const SizedBox(height: 8),
                const Text('Bounding Box (decimal degrees)',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minLatCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13),
                        decoration:
                            _inputDeco('Min Lat ↓', Icons.south_rounded),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _maxLatCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13),
                        decoration:
                            _inputDeco('Max Lat ↑', Icons.north_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minLngCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13),
                        decoration: _inputDeco('Min Lng ←', Icons.west_rounded),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _maxLngCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13),
                        decoration: _inputDeco('Max Lng →', Icons.east_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Zoom range
                Row(
                  children: [
                    const Text('Zoom:',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(width: 8),
                    _ZoomChip(
                        zoom: _minZoom,
                        label: 'Min',
                        onDec: _minZoom > 5
                            ? () => setState(() => _minZoom--)
                            : null,
                        onInc: _minZoom < _maxZoom
                            ? () => setState(() => _minZoom++)
                            : null),
                    const SizedBox(width: 8),
                    const Text('→',
                        style: TextStyle(color: AppTheme.textMuted)),
                    const SizedBox(width: 8),
                    _ZoomChip(
                        zoom: _maxZoom,
                        label: 'Max',
                        onDec: _maxZoom > _minZoom
                            ? () => setState(() => _maxZoom--)
                            : null,
                        onInc: _maxZoom < 20
                            ? () => setState(() => _maxZoom++)
                            : null),
                    const Spacer(),
                    Text(
                      '~${_estimateTiles()} tiles',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Download button
                if (_isDownloading && _downloadingId == null)
                  const LinearProgressIndicator()
                else
                  ElevatedButton.icon(
                    onPressed: _isDownloading ? null : _addRegion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.greenPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text('Download Region',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Downloaded regions ─────────────────────────────────────────────
          if (_regions.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Downloaded Regions',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ),
            ..._regions.map((region) => _RegionCard(
                  region: region,
                  isDownloading: _isDownloading && _downloadingId == region.id,
                  downloadProgress: _downloadProgress,
                  downloadTotal: _downloadTotal,
                  onDownload: () => _downloadRegion(region),
                  onDelete: () => _deleteRegion(region),
                  onCancel: () => setState(() => _cancelDownload = true),
                )),
          ] else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.map_outlined,
                        color: AppTheme.textMuted, size: 52),
                    const SizedBox(height: 12),
                    const Text('No offline regions yet',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text('Add a bounding box above to download tiles',
                        style:
                            TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _estimateTiles() {
    final minLat = double.tryParse(_minLatCtrl.text) ?? 0;
    final maxLat = double.tryParse(_maxLatCtrl.text) ?? 0;
    final minLng = double.tryParse(_minLngCtrl.text) ?? 0;
    final maxLng = double.tryParse(_maxLngCtrl.text) ?? 0;
    if (minLat >= maxLat || minLng >= maxLng) return 0;
    final r = OfflineRegion(
      id: '',
      name: '',
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      createdAt: DateTime.now(),
    );
    return r.estimatedTileCount;
  }
}

// ---------------------------------------------------------------------------
// Helper Widgets
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _SectionCard(
      {required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.greenAccent, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TileToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TileToggle(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.greenPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.white : AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  final int zoom;
  final String label;
  final VoidCallback? onDec;
  final VoidCallback? onInc;
  const _ZoomChip(
      {required this.zoom,
      required this.label,
      required this.onDec,
      required this.onInc});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              icon: const Icon(Icons.remove, size: 14),
              onPressed: onDec,
              color: AppTheme.textSecondary,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints()),
          Text('$label z$zoom',
              style:
                  const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
          IconButton(
              icon: const Icon(Icons.add, size: 14),
              onPressed: onInc,
              color: AppTheme.textSecondary,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints()),
        ],
      ),
    );
  }
}

class _RegionCard extends StatelessWidget {
  final OfflineRegion region;
  final bool isDownloading;
  final int downloadProgress;
  final int downloadTotal;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _RegionCard({
    required this.region,
    required this.isDownloading,
    required this.downloadProgress,
    required this.downloadTotal,
    required this.onDownload,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final prog = isDownloading && downloadTotal > 0
        ? downloadProgress / downloadTotal
        : region.progress;
    final progressPct = (prog * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDownloading
              ? AppTheme.greenPrimary
              : (region.isComplete
                  ? AppTheme.greenAccent.withValues(alpha: 0.4)
                  : AppTheme.borderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                region.isComplete
                    ? Icons.check_circle_rounded
                    : Icons.download_rounded,
                color: region.isComplete
                    ? AppTheme.greenAccent
                    : AppTheme.textMuted,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(region.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold)),
              ),
              if (!isDownloading) ...[
                if (!region.isComplete)
                  IconButton(
                    icon: const Icon(Icons.download_rounded,
                        color: AppTheme.greenAccent, size: 18),
                    onPressed: onDownload,
                    tooltip: 'Download',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.red, size: 18),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ] else
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Zoom z${region.minZoom}–z${region.maxZoom}  ·  '
            '${region.estimatedTileCount} tiles  ·  '
            '~${region.estimatedMB.toStringAsFixed(1)} MB',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: prog,
              backgroundColor: AppTheme.bgSurface,
              valueColor: AlwaysStoppedAnimation<Color>(
                region.isComplete
                    ? AppTheme.greenAccent
                    : AppTheme.greenPrimary,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isDownloading
                ? 'Downloading… $downloadProgress / $downloadTotal tiles'
                : region.isComplete
                    ? '✓ Complete — ${region.downloadedTiles} tiles cached'
                    : '$progressPct% — tap ↓ to resume',
            style: TextStyle(
              color: isDownloading
                  ? AppTheme.greenPrimary
                  : (region.isComplete
                      ? AppTheme.greenAccent
                      : AppTheme.textMuted),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
