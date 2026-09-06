import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uri_to_file/uri_to_file.dart';
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

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  int _previousIndex = 0;
  final GlobalKey<MapScreenState> _mapKey = GlobalKey<MapScreenState>();
  
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  // Screens are created ONCE in initState — not recreated on every build().
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // Initialize screens once; IndexedStack keeps them alive between tab switches.
    _screens = [
      MapScreen(key: _mapKey),
      const VillagesScreen(),
      const KmlScreen(),
      const OfflineMapsScreen(),
      const SettingsScreen(),
    ];
    _initAppLinks();
    _checkAndRestoreOnStartup();
  }

  Future<void> _checkAndRestoreOnStartup() async {
    try {
      final db = DbHelper();
      final dbObj = await db.database;
      await db.checkAndRestoreBackup(dbObj);
    } catch (_) {}
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initAppLinks() async {
    _appLinks = AppLinks();
    
    // Check initial link if app was closed
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }
    } catch (e) {
      debugPrint("Failed to get initial link: $e");
    }

    // Handle link when app is in background/foreground
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingUri(uri);
    }, onError: (err) {
      debugPrint("AppLinks error: $err");
    });
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    try {
      // Convert content:// or file:// URI to standard File
      File file = await toFile(uri.toString());
      
      final ext = p.extension(file.path).toLowerCase();
      
      if (ext == '.kgfp' || ext == '.db' || ext == '.json' || ext == '.bin') {
        // Handle backup restore
        if (mounted) {
          final result = await BackupHelper.importData(context, externalFile: file);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.message),
                backgroundColor: result.success ? AppTheme.greenPrimary : AppTheme.warningColor,
              ),
            );
          }
        }
      } else if (ext == '.kml' || ext == '.kmz' || ext == '.geojson') {
        // Handle Map Data Import
        final appDocDir = await getApplicationDocumentsDirectory();
        final importsDir = Directory('${appDocDir.path}/kml_imports');
        if (!await importsDir.exists()) {
          await importsDir.create(recursive: true);
        }
        
        final fileName = p.basename(file.path);
        final newFile = await file.copy('${importsDir.path}/$fileName');
        
        final db = DbHelper();
        final kmlModel = KmlFileModel(
          filepath: newFile.path,
          filename: fileName,
          layerColor: '#2EA043',
          createdAt: DateTime.now().toIso8601String(),
        );
        await db.insertKmlFile(kmlModel);
        
        // Switch to Map Screen
        if (_currentIndex != 0 && mounted) {
          setState(() {
            _previousIndex = _currentIndex;
            _currentIndex = 0;
          });
        }
        
        // Parse and center Map
        final shapes = await KmlEngine.parseFile(newFile.path, smartOpacity: kmlModel.smartOpacity);
        if (mounted && shapes.isNotEmpty) {
          final coloredShapes = shapes
              .map((s) => s.copyWith(color: kmlModel.layerColor, opacity: kmlModel.opacity))
              .toList();
          
          await _mapKey.currentState?.reloadKmlLayers();
          _mapKey.currentState?.centerMapOnShapes(coloredShapes);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported and opened $fileName'),
                backgroundColor: AppTheme.greenPrimary,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error handling incoming file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: $e'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
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
            // Mark KML dirty when leaving the KML tab so the map only re-parses
            // when something actually changed, not on every tab switch.
            if (_currentIndex == 2 && index != 2) {
              _mapKey.currentState?.markKmlDirty();
            }
            // If switching back to map from KML tab, reload only if dirty
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
    );
  }
}
