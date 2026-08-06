import 'dart:typed_data';

/// Parses GeoTIFF binary data to extract geographic bounding coordinates.
/// Returns null for non-GeoTIFF files.
class GeoTiffParser {
  // TIFF tag codes for geo-referencing
  static const int _tagModelPixelScale = 33550;
  static const int _tagModelTiepoint = 33922;

  final Uint8List bytes;
  late bool _isLittleEndian;
  late int _ifdOffset;

  GeoTiffParser(this.bytes);

  /// Main entry point. Returns bounding box or null if not a GeoTIFF.
  GeoBounds? parse() {
    try {
      if (bytes.length < 8) return null;

      // Check TIFF magic bytes
      final byteOrder = _readUint16(0);
      if (byteOrder == 0x4949) {
        _isLittleEndian = true; // 'II' - Intel (little endian)
      } else if (byteOrder == 0x4D4D) {
        _isLittleEndian = false; // 'MM' - Motorola (big endian)
      } else {
        return null; // Not a TIFF
      }

      // TIFF magic number
      final magic = _readUint16(2);
      if (magic != 42) return null;

      // Offset to first IFD
      _ifdOffset = _readUint32(4);

      // Parse IFD entries to find geo tags
      List<double>? pixelScale;
      List<double>? tiepoint;
      int imageWidth = 0;
      int imageHeight = 0;

      final numEntries = _readUint16(_ifdOffset);
      for (int i = 0; i < numEntries; i++) {
        final entryOffset = _ifdOffset + 2 + (i * 12);
        if (entryOffset + 12 > bytes.length) break;

        final tag = _readUint16(entryOffset);
        final type = _readUint16(entryOffset + 2);
        final count = _readUint32(entryOffset + 4);
        final valueOffset = _readUint32(entryOffset + 8);

        if (tag == _tagModelPixelScale) {
          pixelScale = _readDoubles(valueOffset, count);
        } else if (tag == _tagModelTiepoint) {
          tiepoint = _readDoubles(valueOffset, count);
        } else if (tag == 256) {
          // ImageWidth
          imageWidth = _readTagValue(type, entryOffset + 8);
        } else if (tag == 257) {
          // ImageLength (height)
          imageHeight = _readTagValue(type, entryOffset + 8);
        }
      }

      if (pixelScale == null || tiepoint == null || tiepoint.length < 6) {
        return null; // Not a valid GeoTIFF
      }

      // Tiepoint format: [i, j, k, x, y, z] where (x,y) is lon/lat of pixel (i,j)
      final double tiepointX = tiepoint[3]; // longitude of tie point
      final double tiepointY = tiepoint[4]; // latitude of tie point
      final double scaleX = pixelScale[0];  // degrees per pixel in X
      final double scaleY = pixelScale[1];  // degrees per pixel in Y
      final double tiepointPixelI = tiepoint[0];
      final double tiepointPixelJ = tiepoint[1];

      // Compute bounding box
      // The tiepoint tells us a specific pixel -> lat/lon mapping
      // Usually tiepoint pixel is (0,0) = top-left corner
      final double west = tiepointX - (tiepointPixelI * scaleX);
      final double north = tiepointY + (tiepointPixelJ * scaleY);
      final double east = west + (imageWidth * scaleX);
      final double south = north - (imageHeight * scaleY);

      // Sanity check - should be valid lat/lon ranges
      if (north > 90 || south < -90 || east > 180 || west < -180) {
        return null;
      }
      if (north <= south || east <= west) {
        return null;
      }

      return GeoBounds(
        north: north,
        south: south,
        east: east,
        west: west,
      );
    } catch (e) {
      return null;
    }
  }

  int _readTagValue(int type, int offset) {
    // For SHORT (3) or LONG (4) types stored directly in value field
    if (type == 3) return _readUint16(offset);
    if (type == 4) return _readUint32(offset);
    return 0;
  }

  List<double> _readDoubles(int offset, int count) {
    final result = <double>[];
    for (int i = 0; i < count; i++) {
      result.add(_readDouble(offset + (i * 8)));
    }
    return result;
  }

  int _readUint16(int offset) {
    if (offset + 2 > bytes.length) return 0;
    if (_isLittleEndian) {
      return bytes[offset] | (bytes[offset + 1] << 8);
    } else {
      return (bytes[offset] << 8) | bytes[offset + 1];
    }
  }

  int _readUint32(int offset) {
    if (offset + 4 > bytes.length) return 0;
    if (_isLittleEndian) {
      return bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
    } else {
      return (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
    }
  }

  double _readDouble(int offset) {
    if (offset + 8 > bytes.length) return 0.0;
    final data = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      data[i] = _isLittleEndian ? bytes[offset + i] : bytes[offset + 7 - i];
    }
    return ByteData.sublistView(data).getFloat64(0, Endian.little);
  }
}

/// Holds the geographic bounding box of an image
class GeoBounds {
  final double north;
  final double south;
  final double east;
  final double west;

  const GeoBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  double get centerLat => (north + south) / 2;
  double get centerLon => (east + west) / 2;
  double get latSpan => north - south;
  double get lonSpan => east - west;

  @override
  String toString() =>
      'N:${north.toStringAsFixed(6)} S:${south.toStringAsFixed(6)} E:${east.toStringAsFixed(6)} W:${west.toStringAsFixed(6)}';
}
