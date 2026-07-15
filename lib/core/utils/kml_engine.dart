import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'geo_calculator.dart';

/// A parsed KML shape (polygon, path, or marker)
class KmlShape {
  final String name;
  final String type; // 'polygon', 'path', 'marker'
  final List<Map<String, double>> coordinates;
  final String? description;
  final String color;
  final String? layerName;
  final double opacity; // 0.0 to 1.0

  // Ground Overlay (Image map)
  final String? imageUrl;
  final double? north;
  final double? south;
  final double? east;
  final double? west;

  const KmlShape({
    required this.name,
    required this.type,
    required this.coordinates,
    this.description,
    this.color = '#2EA043',
    this.layerName,
    this.opacity = 1.0,
    this.imageUrl,
    this.north,
    this.south,
    this.east,
    this.west,
  });

  KmlShape copyWith({
    String? name,
    String? type,
    List<Map<String, double>>? coordinates,
    String? description,
    String? color,
    String? layerName,
    double? opacity,
    String? imageUrl,
    double? north,
    double? south,
    double? east,
    double? west,
  }) {
    return KmlShape(
      name: name ?? this.name,
      type: type ?? this.type,
      coordinates: coordinates ?? this.coordinates,
      description: description ?? this.description,
      color: color ?? this.color,
      layerName: layerName ?? this.layerName,
      opacity: opacity ?? this.opacity,
      imageUrl: imageUrl ?? this.imageUrl,
      north: north ?? this.north,
      south: south ?? this.south,
      east: east ?? this.east,
      west: west ?? this.west,
    );
  }
}

/// Parses and generates KML/KMZ files
class KmlEngine {
  // ─────────────────── GENERATION ────────────────────────────────────────────

  /// Generate KML string from polygon points
  static String generatePolygonKml({
    required String name,
    required List<Map<String, double>> points,
    String description = '',
    String color = 'ff2EA043',
  }) {
    final coordString = GeoCalculator.toKmlCoordinates([...points, points.first]);
    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$name</name>
    <Style id="polyStyle">
      <LineStyle>
        <color>$color</color>
        <width>3</width>
      </LineStyle>
      <PolyStyle>
        <color>50${color.substring(2)}</color>
      </PolyStyle>
    </Style>
    <Placemark>
      <name>$name</name>
      <description>$description</description>
      <styleUrl>#polyStyle</styleUrl>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>$coordString</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
  </Document>
</kml>''';
  }

  /// Generate KML string from path/line points
  static String generatePathKml({
    required String name,
    required List<Map<String, double>> points,
    String description = '',
    String color = 'ff388BFD',
  }) {
    final coordString = GeoCalculator.toKmlCoordinates(points);
    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$name</name>
    <Style id="lineStyle">
      <LineStyle>
        <color>$color</color>
        <width>3</width>
      </LineStyle>
    </Style>
    <Placemark>
      <name>$name</name>
      <description>$description</description>
      <styleUrl>#lineStyle</styleUrl>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>$coordString</coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';
  }

  /// Generate KML string for a marker/point
  static String generateMarkerKml({
    required String name,
    required double lat,
    required double lng,
    String description = '',
  }) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$name</name>
    <Placemark>
      <name>$name</name>
      <description>$description</description>
      <Point>
        <coordinates>$lng,$lat,0</coordinates>
      </Point>
    </Placemark>
  </Document>
</kml>''';
  }

  /// Generate KML from multiple shapes
  static String generateMultiShapeKml(
      String docName, List<Map<String, dynamic>> shapes) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buffer.writeln('  <Document>');
    buffer.writeln('    <name>$docName</name>');
    for (final shape in shapes) {
      buffer.writeln('    <Placemark>');
      buffer.writeln('      <name>${shape['name']}</name>');
      if (shape['type'] == 'polygon') {
        final coords = GeoCalculator.toKmlCoordinates(
            [for (final p in shape['points'] as List) {'lat': p['lat'], 'lng': p['lng']}]);
        buffer.writeln('      <Polygon>');
        buffer.writeln('        <outerBoundaryIs>');
        buffer.writeln('          <LinearRing>');
        buffer.writeln('            <coordinates>$coords</coordinates>');
        buffer.writeln('          </LinearRing>');
        buffer.writeln('        </outerBoundaryIs>');
        buffer.writeln('      </Polygon>');
      }
      buffer.writeln('    </Placemark>');
    }
    buffer.writeln('  </Document>');
    buffer.writeln('</kml>');
    return buffer.toString();
  }

  // ─────────────────── PARSING ────────────────────────────────────────────────

  /// Parse KML content string into a list of KmlShape objects
  static List<KmlShape> parseKml(String kmlContent) {
    final List<KmlShape> shapes = [];
    try {
      final doc = XmlDocument.parse(kmlContent);
      final placemarks = doc.findAllElements('Placemark');

      for (final pm in placemarks) {
        final name = pm.findElements('name').firstOrNull?.innerText.trim() ?? 'Unnamed';
        final desc = pm.findElements('description').firstOrNull?.innerText.trim();

        // Polygons
        final polygons = pm.findAllElements('Polygon');
        for (final polygonEl in polygons) {
          final coordStr = polygonEl
              .findAllElements('coordinates')
              .firstOrNull
              ?.innerText
              .trim();
          if (coordStr != null) {
            final coords = GeoCalculator.parseKmlCoordinates(coordStr);
            if (coords.isNotEmpty) {
              shapes.add(KmlShape(
                name: polygons.length > 1 ? '$name (Part)' : name,
                type: 'polygon',
                coordinates: coords,
                description: desc,
              ));
            }
          }
        }

        // LineStrings (Paths)
        final lineStrings = pm.findAllElements('LineString');
        for (final lineEl in lineStrings) {
          final coordStr = lineEl
              .findAllElements('coordinates')
              .firstOrNull
              ?.innerText
              .trim();
          if (coordStr != null) {
            final coords = GeoCalculator.parseKmlCoordinates(coordStr);
            if (coords.isNotEmpty) {
              shapes.add(KmlShape(
                name: lineStrings.length > 1 ? '$name (Part)' : name,
                type: 'path',
                coordinates: coords,
                description: desc,
              ));
            }
          }
        }

        // Points (Markers)
        final points = pm.findAllElements('Point');
        for (final pointEl in points) {
          final coordStr = pointEl
              .findAllElements('coordinates')
              .firstOrNull
              ?.innerText
              .trim();
          if (coordStr != null) {
            final coords = GeoCalculator.parseKmlCoordinates(coordStr);
            if (coords.isNotEmpty) {
              shapes.add(KmlShape(
                name: points.length > 1 ? '$name (Part)' : name,
                type: 'marker',
                coordinates: coords,
                description: desc,
              ));
            }
          }
        }
      }

      // GroundOverlays (Image Maps)
      final groundOverlays = doc.findAllElements('GroundOverlay');
      for (final go in groundOverlays) {
        final name = go.findElements('name').firstOrNull?.innerText.trim() ?? 'Image Overlay';
        final desc = go.findElements('description').firstOrNull?.innerText.trim();
        final href = go.findAllElements('Icon').firstOrNull?.findElements('href').firstOrNull?.innerText.trim();
        final latLonBox = go.findAllElements('LatLonBox').firstOrNull;

        if (href != null && latLonBox != null) {
          final north = double.tryParse(latLonBox.findElements('north').firstOrNull?.innerText.trim() ?? '');
          final south = double.tryParse(latLonBox.findElements('south').firstOrNull?.innerText.trim() ?? '');
          final east = double.tryParse(latLonBox.findElements('east').firstOrNull?.innerText.trim() ?? '');
          final west = double.tryParse(latLonBox.findElements('west').firstOrNull?.innerText.trim() ?? '');

          if (north != null && south != null && east != null && west != null) {
            shapes.add(KmlShape(
              name: name,
              type: 'overlay',
              coordinates: [], // Not needed for overlay, bounds used instead
              description: desc,
              imageUrl: href,
              north: north,
              south: south,
              east: east,
              west: west,
            ));
          }
        }
      }
    } catch (e) {
      // Return empty list on parse error
    }
    return shapes;
  }

  /// Parse KMZ file (zipped KML) - returns list of KmlShape
  /// KMZ is a ZIP archive. The main KML is typically doc.kml or any *.kml file.
  static List<KmlShape> parseKmz(List<int> kmzBytes, {String? extractDir}) {
    try {
      final archive = ZipDecoder().decodeBytes(kmzBytes);

      /// Helper: get raw bytes from an ArchiveFile (archive 3.x compatible)
      List<int>? getEntryBytes(ArchiveFile entry) {
        if (!entry.isFile) return null;
        try {
          final raw = entry.content; // dynamic in archive 3.x
          if (raw is List<int>) return raw;
          // Try decompressing via readBytes if content is an InputStream
          // Fallback: get content bytes another way
          if (raw != null) {
            return raw.toString().codeUnits; // last resort (should not reach here)
          }
        } catch (_) {}
        return null;
      }

      /// Find an archive entry by href (handles paths like "files/image.jpg")
      ArchiveFile? findImageEntry(String href) {
        // Normalize separators
        final normalizedHref = href.replaceAll('\\', '/');
        // 1) Exact match
        for (final f in archive.files) {
          if (f.name.replaceAll('\\', '/') == normalizedHref) return f;
        }
        // 2) Match by filename only (last segment)
        final hrefFilename = normalizedHref.split('/').last.toLowerCase();
        for (final f in archive.files) {
          if (!f.isFile) continue;
          final fName = f.name.split('/').last.toLowerCase();
          if (fName == hrefFilename) return f;
        }
        // 3) endsWith match
        for (final f in archive.files) {
          if (f.name.replaceAll('\\', '/').endsWith(normalizedHref)) return f;
        }
        return null;
      }

      List<KmlShape> parseAndExtractImages(ArchiveFile entry) {
        final bytes = getEntryBytes(entry);
        if (bytes == null) return [];
        final content = utf8.decode(bytes, allowMalformed: true);
        var shapes = parseKml(content);

        // Extract any images referenced by GroundOverlays
        if (extractDir != null) {
          shapes = shapes.map((shape) {
            if (shape.type == 'overlay' && shape.imageUrl != null) {
              final targetImg = shape.imageUrl!;
              // Find image in archive using multiple strategies
              final imgEntry = findImageEntry(targetImg);
              if (imgEntry != null) {
                final rawContent = imgEntry.content;
                List<int>? imgBytes;
                if (rawContent is List<int>) {
                  imgBytes = rawContent;
                } else {
                  imgBytes = getEntryBytes(imgEntry);
                }
                if (imgBytes != null && imgBytes.isNotEmpty) {
                  final imgFileName = imgEntry.name.split('/').last;
                  final imgFile = File('$extractDir/$imgFileName');
                  if (!imgFile.existsSync()) {
                    imgFile.writeAsBytesSync(imgBytes);
                  }
                  return shape.copyWith(imageUrl: imgFile.path);
                }
              }
            }
            return shape;
          }).toList();
        }
        return shapes;
      }

      // 1) Try doc.kml first (Google Maps / QGIS default export name)
      for (final entry in archive.files) {
        final entryName = entry.name.toLowerCase();
        if (entryName == 'doc.kml' || entryName.endsWith('/doc.kml')) {
          final shapes = parseAndExtractImages(entry);
          if (shapes.isNotEmpty) return shapes;
        }
      }

      // 2) Fall back to any *.kml file in the archive
      for (final entry in archive.files) {
        if (!entry.name.toLowerCase().endsWith('.kml')) continue;
        final shapes = parseAndExtractImages(entry);
        if (shapes.isNotEmpty) return shapes;
      }
    } catch (_) {
      // Return empty on error
    }
    return [];
  }

  /// Parse GeoJSON string into KmlShape list
  static List<KmlShape> parseGeoJson(String geoJsonContent) {
    final List<KmlShape> shapes = [];
    try {
      final data = jsonDecode(geoJsonContent) as Map<String, dynamic>;
      final features = data['features'] as List? ?? [];

      for (final feature in features) {
        final props = feature['properties'] as Map<String, dynamic>? ?? {};
        final name = props['name']?.toString() ??
            props['NAME']?.toString() ??
            props['village_name']?.toString() ??
            props['VILLAGE']?.toString() ??
            'Unnamed';
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;

        final gType = geometry['type'] as String?;
        final gCoords = geometry['coordinates'];

        if (gType == 'Polygon' && gCoords is List) {
          final outerRing = gCoords.first as List;
          final pts = <Map<String, double>>[];
          for (final c in outerRing) {
            if (c is List && c.length >= 2) {
              pts.add({
                'lat': (c[1] as num).toDouble(),
                'lng': (c[0] as num).toDouble(),
              });
            }
          }
          if (pts.isNotEmpty) {
            shapes.add(KmlShape(
              name: name,
              type: 'polygon',
              coordinates: pts,
            ));
          }
        } else if (gType == 'MultiPolygon' && gCoords is List) {
          for (int pi = 0; pi < gCoords.length; pi++) {
            final poly = gCoords[pi];
            if (poly is List && poly.isNotEmpty) {
              final outerRing = poly.first as List;
              final pts = <Map<String, double>>[];
              for (final c in outerRing) {
                if (c is List && c.length >= 2) {
                  pts.add({
                    'lat': (c[1] as num).toDouble(),
                    'lng': (c[0] as num).toDouble(),
                  });
                }
              }
              if (pts.isNotEmpty) {
                shapes.add(KmlShape(
                  name: pi == 0 ? name : '$name (${pi + 1})',
                  type: 'polygon',
                  coordinates: pts,
                ));
              }
            }
          }
        } else if (gType == 'LineString' && gCoords is List) {
          final pts = <Map<String, double>>[];
          for (final c in gCoords) {
            if (c is List && c.length >= 2) {
              pts.add({
                'lat': (c[1] as num).toDouble(),
                'lng': (c[0] as num).toDouble(),
              });
            }
          }
          if (pts.isNotEmpty) {
            shapes.add(KmlShape(name: name, type: 'path', coordinates: pts));
          }
        } else if (gType == 'Point' && gCoords is List && gCoords.length >= 2) {
          shapes.add(KmlShape(
            name: name,
            type: 'marker',
            coordinates: [
              {'lat': (gCoords[1] as num).toDouble(), 'lng': (gCoords[0] as num).toDouble()}
            ],
          ));
        }
      }
    } catch (e) {
      // Return empty on error
    }
    return shapes;
  }

  /// Write KMZ file (zip the KML) and return bytes
  static List<int> generateKmz(String kmlContent, String kmlFilename) {
    final archive = Archive();
    final kmlBytes = utf8.encode(kmlContent);
    archive.addFile(ArchiveFile(kmlFilename, kmlBytes.length, kmlBytes));
    return ZipEncoder().encode(archive)!;
  }

  /// Parse KML or KMZ from file path
  static Future<List<KmlShape>> parseFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      // Determine type by extension (also handle uppercase extensions)
      final lowerPath = filePath.toLowerCase();

      if (lowerPath.endsWith('.kmz')) {
        final bytes = await file.readAsBytes();
        return parseKmz(bytes.toList(), extractDir: file.parent.path);
      } else if (lowerPath.endsWith('.kml')) {
        final content = await file.readAsString();
        return parseKml(content);
      } else if (lowerPath.endsWith('.geojson') || lowerPath.endsWith('.json')) {
        final content = await file.readAsString();
        return parseGeoJson(content);
      }
    } catch (_) {
      // Silent fail — file may be inaccessible
    }
    return [];
  }
}
