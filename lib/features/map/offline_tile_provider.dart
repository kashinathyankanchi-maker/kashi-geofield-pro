import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

class OfflineTileProvider extends TileProvider {
  final String baseDir;
  final bool isSatellite;
  final TileProvider fallbackProvider = NetworkTileProvider();

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
    } else {
      return fallbackProvider.getImage(coordinates, options);
    }
  }
}
