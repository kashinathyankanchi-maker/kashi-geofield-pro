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

  const KmlShape({
    required this.name,
    required this.type,
    required this.coordinates,
    this.description,
    this.color = '#2EA043',
    this.layerName,
  });

  KmlShape copyWith({
    String? name,
    String? type,
    List<Map<String, double>>? coordinates,
    String? description,
    String? color,
    String? layerName,
  }) {
    return KmlShape(
      name: name ?? this.name,
      type: type ?? this.type,
      coordinates: coordinates ?? this.coordinates,
      description: description ?? this.description,
      color: color ?? this.color,
      layerName: layerName ?? this.layerName,
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

        // Polygon
        final polygonEl = pm.findElements('Polygon').firstOrNull;
        if (polygonEl != null) {
          final coordStr = polygonEl
              .findAllElements('coordinates')
              .firstOrNull
              ?.innerText
              .trim();
          if (coordStr != null) {
            final coords = GeoCalculator.parseKmlCoordinates(coordStr);
            if (coords.isNotEmpty) {
              shapes.add(KmlShape(
                name: name,
                type: 'polygon',
                coordinates: coords,
                description: desc,
              ));
            }
          }
          continue;
        }

        // LineString
        final lineEl = pm.findElements('LineString').firstOrNull;
        if (lineEl != null) {
          final coordStr = lineEl
              .findAllElements('coordinates')
              .firstOrNull
              ?.innerText
              .trim();
          if (coordStr != null) {
            final coords = GeoCalculator.parseKmlCoordinates(coordStr);
            if (coords.isNotEmpty) {
              shapes.add(KmlShape(
                name: name,
                type: 'path',
                coordinates: coords,
                description: desc,
              ));
            }
          }
          continue;
        }

        // Point/Marker
        final pointEl = pm.findElements('Point').firstOrNull;
        if (pointEl != null) {
          final coordStr = pointEl
              .findAllElements('coordinates')
              .firstOrNull
              ?.innerText
              .trim();
          if (coordStr != null) {
            final coords = GeoCalculator.parseKmlCoordinates(coordStr);
            if (coords.isNotEmpty) {
              shapes.add(KmlShape(
                name: name,
                type: 'marker',
                coordinates: coords,
                description: desc,
              ));
            }
          }
        }
      }
    } catch (e) {
      // Return empty list on parse error
    }
    return shapes;
  }

  /// Parse KMZ file (zipped KML) - returns list of KmlShape
  static List<KmlShape> parseKmz(List<int> kmzBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(kmzBytes);
      for (final file in archive) {
        if (file.name.endsWith('.kml') && file.isFile) {
          final content = utf8.decode(file.content as List<int>);
          return parseKml(content);
        }
      }
    } catch (e) {
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
    final file = File(filePath);
    if (!await file.exists()) return [];

    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.kmz')) {
      final bytes = await file.readAsBytes();
      return parseKmz(bytes);
    } else if (lowerPath.endsWith('.kml')) {
      final content = await file.readAsString();
      return parseKml(content);
    } else if (lowerPath.endsWith('.geojson') || lowerPath.endsWith('.json')) {
      final content = await file.readAsString();
      return parseGeoJson(content);
    }
    return [];
  }
}
