import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/models/kml_file_model.dart';
import '../core/database/db_helper.dart';
import '../core/utils/backup_helper.dart';
import '../core/utils/kml_engine.dart';
import '../features/map/map_screen.dart';
import '../features/villages/villages_screen.dart';
import '../features/kml/kml_screen.dart';
import '../features/offline_maps/offline_maps_screen.dart';
import '../features/settings/settings_screen.dart';
import 'theme.dart';

// MethodChannel to read content:// URI bytes from Android native side
const _fileUtilsChannel = MethodChannel('com.kashi.geofield/file_utils');

class MainScaffold extends StatefulWidget {
  /// URI passed from SplashScreen when app was cold-started by opening a file.
  final Uri? initialUri;

  const MainScaffold({super.key, this.initialUri});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  int _previousIndex = 0;
  final GlobalKey<MapScreenState> _mapKey = GlobalKey<MapScreenState>();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  bool _isImporting = false;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      MapScreen(key: _mapKey),
      const VillagesScreen(),
      const KmlScreen(),
      const OfflineMapsScreen(),
      const SettingsScreen(),
    ];

    // Cold-start: file was tapped when app was closed → SplashScreen passed URI here
    if (widget.initialUri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleIncomingUri(widget.initialUri!);
      });
    }

    _initAppLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initAppLinks() async {
    _appLinks = AppLinks();
    // Only listen for warm-start links (SplashScreen handles cold-start)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingUri,
      onError: (err) => debugPrint('AppLinks stream error: $err'),
    );
  }

  // ── Resolve any URI to a File ────────────────────────────────────────────
  Future<File?> _resolveUri(Uri uri) async {
    // 1. Direct file:// path
    if (uri.scheme == 'file') {
      final f = File(uri.toFilePath());
      if (await f.exists()) return f;
    }

    // 2. content:// — use native MethodChannel to read bytes
    if (uri.scheme == 'content') {
      final tempDir = await getTemporaryDirectory();

      // Get display name from Android ContentResolver
      String fileName = 'imported_file.kmz';
      try {
        final name = await _fileUtilsChannel.invokeMethod<String>(
            'getFileName', {'uri': uri.toString()});
        if (name != null && name.isNotEmpty) fileName = name;
      } catch (_) {
        // Fallback to last path segment
        final seg = uri.pathSegments.lastOrNull;
        if (seg != null && seg.isNotEmpty) {
          fileName = Uri.decodeComponent(seg);
        }
      }

      // Read bytes via native ContentResolver
      try {
        final bytes = await _fileUtilsChannel.invokeMethod<Uint8List>(
            'readUriBytes', {'uri': uri.toString()});
        if (bytes != null && bytes.isNotEmpty) {
          final destFile = File('${tempDir.path}/$fileName');
          await destFile.writeAsBytes(bytes);
          return destFile;
        }
      } catch (e) {
        debugPrint('readUriBytes error: $e');
      }
    }

    return null;
  }

  // ── Main incoming-file handler ───────────────────────────────────────────
  Future<void> _handleIncomingUri(Uri uri) async {
    if (!mounted) return;

    setState(() => _isImporting = true);

    try {
      final file = await _resolveUri(uri);

      if (file == null || !await file.exists()) {
        _showSnack(
          '❌ Could not read file. Try importing via the KML FILES tab.',
          error: true,
        );
        return;
      }

      final ext = p.extension(file.path).toLowerCase();

      if (ext == '.kgfp' || ext == '.db' || ext == '.json') {
        // ── Backup restore ─────────────────────────────────────────────
        final result = await BackupHelper.importData(context, externalFile: file);
        if (mounted) {
          _showSnack(result.message, error: !result.success);
        }
      } else if (ext == '.kml' || ext == '.kmz' || ext == '.geojson') {
        // ── KML / KMZ import ───────────────────────────────────────────
        await _importAndShowKmlFile(file);
      } else {
        _showSnack(
          '❌ Unsupported file type "$ext". Supported: .kml, .kmz, .geojson, .kgfp',
          error: true,
        );
      }
    } catch (e) {
      debugPrint('_handleIncomingUri error: $e');
      _showSnack('❌ Error opening file: $e', error: true);
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _importAndShowKmlFile(File file) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final importsDir = Directory('${appDocDir.path}/kml_imports');
    if (!await importsDir.exists()) await importsDir.create(recursive: true);

    // Avoid collisions — append timestamp if file already exists
    final originalName = p.basename(file.path);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final destName = await File('${importsDir.path}/$originalName').exists()
        ? '${p.basenameWithoutExtension(originalName)}_$ts${p.extension(originalName)}'
        : originalName;

    final newFile = await file.copy('${importsDir.path}/$destName');

    final kmlModel = KmlFileModel(
      filepath: newFile.path,
      filename: destName,
      layerColor: '#2EA043',
      createdAt: DateTime.now().toIso8601String(),
    );
    await DbHelper().insertKmlFile(kmlModel);

    // Switch to Map tab
    if (mounted) {
      setState(() {
        _previousIndex = _currentIndex;
        _currentIndex = 0;
      });
    }

    // Wait for the map widget to be ready, then load
    await _waitForMapThenLoad(kmlModel, newFile.path, destName);
  }

  /// Retries up to 3 seconds (30 × 100 ms) until the map widget is mounted.
  Future<void> _waitForMapThenLoad(
      KmlFileModel model, String filePath, String name) async {
    for (int i = 0; i < 30; i++) {
      if (_mapKey.currentState != null) {
        await _renderKmlOnMap(model, filePath, name);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // Timed out — map never became ready; show fallback message
    _showSnack('✅ "$name" imported! Open the Map tab to view it.', duration: 4);
  }

  Future<void> _renderKmlOnMap(
      KmlFileModel model, String filePath, String name) async {
    try {
      final shapes =
          await KmlEngine.parseFile(filePath, smartOpacity: model.smartOpacity);

      if (!mounted) return;

      await _mapKey.currentState?.reloadKmlLayers();

      if (shapes.isNotEmpty) {
        final colored = shapes
            .map((s) =>
                s.copyWith(color: model.layerColor, opacity: model.opacity))
            .toList();
        _mapKey.currentState?.centerMapOnShapes(colored);
      }

      _showSnack(
        shapes.isNotEmpty
            ? '✅ "$name" opened — ${shapes.length} shapes on map'
            : '✅ "$name" imported (file has no visible shapes)',
        duration: 4,
      );
    } catch (e) {
      debugPrint('KML render error: $e');
      _showSnack('⚠️ File imported but render failed: $e', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false, int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.warningColor : AppTheme.greenPrimary,
      duration: Duration(seconds: duration),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: AppTheme.bgSecondary,
              border: Border(
                top: BorderSide(color: AppTheme.borderBright, width: 1),
              ),
            ),
            child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: AppTheme.greenAccent,
              unselectedItemColor: AppTheme.textMuted,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 9,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 9,
                letterSpacing: 1.0,
                fontFamily: 'monospace',
              ),
              type: BottomNavigationBarType.fixed,
              currentIndex: _currentIndex,
              onTap: (index) {
                if (_currentIndex == 2 && index != 2) {
                  _mapKey.currentState?.markKmlDirty();
                }
                if (index == 0 && _previousIndex == 2) {
                  _mapKey.currentState?.reloadKmlLayers();
                }
                _previousIndex = index;
                setState(() => _currentIndex = index);
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.map_outlined, size: 22),
                  activeIcon: Icon(Icons.map, size: 22),
                  label: 'MAP',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.location_city_outlined, size: 22),
                  activeIcon: Icon(Icons.location_city, size: 22),
                  label: 'VILLAGES',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.layers_outlined, size: 22),
                  activeIcon: Icon(Icons.layers, size: 22),
                  label: 'KML FILES',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.download_outlined, size: 22),
                  activeIcon: Icon(Icons.download, size: 22),
                  label: 'OFFLINE',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined, size: 22),
                  activeIcon: Icon(Icons.settings, size: 22),
                  label: 'SETTINGS',
                ),
              ],
            ),
          ),
        ),

        // ── Importing overlay ─────────────────────────────────────────────
        if (_isImporting)
          Container(
            color: Colors.black54,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppTheme.greenAccent.withAlpha(80), width: 1.5),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.greenAccent),
                    SizedBox(height: 16),
                    Text(
                      'Opening file on map...',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Please wait',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
