import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Custom tile provider:
/// 1. Checks local disk cache first (for offline tiles downloaded via Offline Maps screen)
/// 2. Delegates to flutter_map's built-in NetworkTileProvider when online
class OfflineTileProvider extends TileProvider {
  final String baseDir;
  final bool isSatellite;
  
  final NetworkTileProvider _networkProvider = NetworkTileProvider();

  OfflineTileProvider({
    required this.baseDir,
    required this.isSatellite,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final sub = isSatellite ? 'sat' : 'osm';
    final z = coordinates.z.round();
    final x = coordinates.x.round();
    final y = coordinates.y.round();

    final path = '$baseDir/offline_tiles/$sub/$z/$x/$y.png';
    final file = File(path);

    if (file.existsSync()) {
      return FileImage(file);
    }

    return _networkProvider.getImage(coordinates, options);
  }
}
