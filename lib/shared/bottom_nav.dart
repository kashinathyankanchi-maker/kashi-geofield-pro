import 'package:flutter/material.dart';
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

  final List<Widget> _screens = const [
    MapScreen(),
    VillagesScreen(),
    KmlScreen(),
    OfflineMapsScreen(),
    SettingsScreen(),
  ];

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
          onTap: (index) => setState(() => _currentIndex = index),
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
