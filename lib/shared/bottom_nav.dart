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
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xFF0D1117),
              Color(0xFF161B22),
            ],
          ),
          border: Border(
            top: BorderSide(color: Colors.transparent, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF4FC3F7),   // professional sky blue
          unselectedItemColor: const Color(0xFF607D8B), // blue-grey muted
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 10),
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.location_city_outlined),
              activeIcon: Icon(Icons.location_city),
              label: 'Villages',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.layers_outlined),
              activeIcon: Icon(Icons.layers),
              label: 'KML Files',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.download_outlined),
              activeIcon: Icon(Icons.download),
              label: 'Offline',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
