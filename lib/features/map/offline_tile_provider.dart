import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Custom tile provider that serves offline-cached tiles first,
/// falls back to network when online, and shows a placeholder when offline.
class OfflineTileProvider extends TileProvider {
  final String baseDir;
  final bool isSatellite;

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
      // Serve from local cache
      return FileImage(file);
    } else {
      // Try network — flutter_map will handle the URL template itself
      // We use NetworkTileProvider as fallback but wrap with error handling
      return _SafeNetworkTileImage(
        url: options.urlTemplate!
            .replaceAll('{z}', z.toString())
            .replaceAll('{x}', x.toString())
            .replaceAll('{y}', y.toString()),
        localPath: path,
      );
    }
  }
}

/// Network tile image that caches to disk on success and shows grey placeholder on failure
class _SafeNetworkTileImage extends ImageProvider<_SafeNetworkTileImage> {
  final String url;
  final String localPath;

  _SafeNetworkTileImage({required this.url, required this.localPath});

  @override
  ImageStreamCompleter loadImage(
      _SafeNetworkTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    try {
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 5);
      final request = await httpClient.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'KashiGeoFieldPro/1.0');
      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = await _consolidateHttpResponse(response);

        // Cache tile to disk for offline use
        try {
          final file = File(localPath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
        } catch (_) {}

        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return decode(buffer);
      }
    } catch (_) {}

    // Return a grey placeholder tile when offline/failed
    return _createPlaceholderCodec(decode);
  }

  Future<Uint8List> _consolidateHttpResponse(HttpClientResponse response) async {
    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final result = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  Future<ui.Codec> _createPlaceholderCodec(ImageDecoderCallback decode) async {
    // Create a simple 256x256 grey tile
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xFFE0E0E0);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 256, 256), paint);
    
    // Draw grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFD0D0D0)
      ..strokeWidth = 0.5;
    canvas.drawLine(const Offset(0, 128), const Offset(256, 128), gridPaint);
    canvas.drawLine(const Offset(128, 0), const Offset(128, 256), gridPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(256, 256);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final buffer = await ui.ImmutableBuffer.fromUint8List(
        byteData!.buffer.asUint8List());
    return decode(buffer);
  }

  @override
  Future<_SafeNetworkTileImage> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }

  @override
  bool operator ==(Object other) {
    if (other is _SafeNetworkTileImage) {
      return url == other.url;
    }
    return false;
  }

  @override
  int get hashCode => url.hashCode;
}
