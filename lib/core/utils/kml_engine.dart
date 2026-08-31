import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart'; // compute() for background isolates
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart';
import 'package:xml/xml.dart';
import 'geo_calculator.dart';
import 'storage_helper.dart';


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
  final String? bgImageUrl;
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
    this.bgImageUrl,
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
    String? bgImageUrl,
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
      bgImageUrl: bgImageUrl ?? this.bgImageUrl,
      north: north ?? this.north,
      south: south ?? this.south,
      east: east ?? this.east,
      west: west ?? this.west,
    );
  }
}

/// Parses and generates KML/KMZ files
class KmlEngine {
  // ─────────────────── PDF → PNG CONVERSION ─────────────────────────────────

  /// Renders the first page of a PDF file to a PNG and saves it next to the PDF.
  /// Returns the path to the generated PNG, or null on failure.
  static Future<String?> convertPdfToPng(String pdfPath) async {
    PdfDocument? document;
    PdfPage? page;
    try {
      final pngPath = pdfPath.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '_overlay.png');
      final pngFile = File(pngPath);
      // Return cached version if it exists and is valid (>1KB)
      if (pngFile.existsSync() && pngFile.lengthSync() > 1024) return pngPath;

      document = await PdfDocument.openFile(pdfPath);
      page = await document.getPage(1);

      // Try rendering at 1.5x scale first (balance quality vs memory)
      PdfPageImage? pageImage;
      try {
        pageImage = await page.render(
          width: page.width * 1.5,
          height: page.height * 1.5,
          format: PdfPageImageFormat.png,
          backgroundColor: '#ffffff',
        );
      } catch (_) {
        // If OOM, try at 1x scale
        try {
          pageImage = await page.render(
            width: page.width,
            height: page.height,
            format: PdfPageImageFormat.png,
            backgroundColor: '#ffffff',
          );
        } catch (_) {
          // Last resort: 0.5x scale
          pageImage = await page.render(
            width: page.width * 0.5,
            height: page.height * 0.5,
            format: PdfPageImageFormat.png,
            backgroundColor: '#ffffff',
          );
        }
      }

      if (pageImage != null && pageImage.bytes.isNotEmpty) {
        await pngFile.writeAsBytes(pageImage.bytes);
        if (pngFile.existsSync() && pngFile.lengthSync() > 1024) {
          return pngPath;
        }
      }
    } catch (e) {
      // PDF conversion failed — will use fallback rectangle on map
    } finally {
      try { await page?.close(); } catch (_) {}
      try { await document?.close(); } catch (_) {}
    }
    return null;
  }

  /// Splits an image into a foreground and background image for Smart Opacity.
  /// Processes the overlay image for smart opacity using luminance-based detection:
  /// - Dark pixels (black lines, text, borders) → fully opaque
  /// - Red pixels (roads, boundaries) → fully opaque
  /// - Anti-aliasing edge pixels → partial opacity (smooth edges)
  /// - Everything else (white, grey, cyan background) → fully transparent
  ///
  /// This is more reliable than color-range detection because JPEG compression
  /// creates many intermediate grey/cyan shades that cause a blurry haze.
  static Future<String?> _processSmartOpacityImage(String originalPath) async {
    try {
      // Run heavy pixel processing in background isolate — keeps UI smooth
      return await compute(_smartOpacityIsolate, originalPath);
    } catch (_) {
      return null;
    }
  }

  /// Static isolate entry point (sync I/O only, no async allowed in isolates).
  static String? _smartOpacityIsolate(String originalPath) {
    try {
      final ext = originalPath.contains('.') ? originalPath.split('.').last : 'png';
      final pathWithoutExt = originalPath.substring(0, originalPath.length - ext.length - 1);
      final outPath = '${pathWithoutExt}_smart.png';

      // Return cached version if already processed
      final outFile = File(outPath);
      if (outFile.existsSync() && outFile.lengthSync() > 1024) return outPath;

      final bytes = File(originalPath).readAsBytesSync();
      final srcImage = img.decodeImage(bytes);
      if (srcImage == null) return null;

      final w = srcImage.width;
      final h = srcImage.height;
      // RGBA output
      final outImage = img.Image(width: w, height: h, numChannels: 4);

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final sp = srcImage.getPixel(x, y);
          final r = sp.r.toInt();
          final g = sp.g.toInt();
          final b = sp.b.toInt();
          final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
          final isRed = r > 140 && g < 110 && b < 110 && (r - g) > 50;
          if (isRed) {
            outImage.setPixelRgba(x, y, r, g, b, 255);
          } else if (luminance < 60) {
            outImage.setPixelRgba(x, y, r, g, b, 255);
          } else if (luminance < 100) {
            final alpha = ((100 - luminance) / 40 * 255).clamp(0, 255).toInt();
            outImage.setPixelRgba(x, y, r, g, b, alpha);
          } else {
            outImage.setPixelRgba(x, y, 0, 0, 0, 0);
          }
        }
      }

      File(outPath).writeAsBytesSync(img.encodePng(outImage));
      return outPath;
    } catch (_) {
      return null;
    }
  }

  /// Wrapper kept for call-site compatibility
  static Future<Map<String, String>?> _splitSmartOpacityImage(String originalPath) async {
    final outPath = await _processSmartOpacityImage(originalPath);
    if (outPath == null) return null;
    return {'fg': outPath, 'bg': outPath};
  }


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
      final placemarks = doc.findAllElements('Placemark', namespace: '*');

      for (final pm in placemarks) {
        final name = pm.findElements('name', namespace: '*').firstOrNull?.innerText.trim() ?? 'Unnamed';
        final desc = pm.findElements('description', namespace: '*').firstOrNull?.innerText.trim();

        // Polygons
        final polygons = pm.findAllElements('Polygon', namespace: '*');
        for (final polygonEl in polygons) {
          final coordStr = polygonEl
              .findAllElements('coordinates', namespace: '*')
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
        final lineStrings = pm.findAllElements('LineString', namespace: '*');
        for (final lineEl in lineStrings) {
          final coordStr = lineEl
              .findAllElements('coordinates', namespace: '*')
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
        final points = pm.findAllElements('Point', namespace: '*');
        for (final pointEl in points) {
          final coordStr = pointEl
              .findAllElements('coordinates', namespace: '*')
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
      final groundOverlays = doc.findAllElements('GroundOverlay', namespace: '*');
      for (final go in groundOverlays) {
        final name = go.findElements('name', namespace: '*').firstOrNull?.innerText.trim() ?? 'Image Overlay';
        final desc = go.findElements('description', namespace: '*').firstOrNull?.innerText.trim();

        // href can be under <Icon> or <Link>
        String? href =
            go.findAllElements('Icon', namespace: '*').firstOrNull?.findElements('href', namespace: '*').firstOrNull?.innerText.trim();
        href ??= go.findAllElements('Link', namespace: '*').firstOrNull?.findElements('href', namespace: '*').firstOrNull?.innerText.trim();
        // Strip any query strings or fragments
        if (href != null && href.contains('?')) href = href.split('?').first;

        double? north, south, east, west;

        // Try LatLonBox first (axis-aligned)
        final latLonBox = go.findAllElements('LatLonBox', namespace: '*').firstOrNull;
        if (latLonBox != null) {
          north = double.tryParse(latLonBox.findElements('north', namespace: '*').firstOrNull?.innerText.trim() ?? '');
          south = double.tryParse(latLonBox.findElements('south', namespace: '*').firstOrNull?.innerText.trim() ?? '');
          east  = double.tryParse(latLonBox.findElements('east', namespace: '*').firstOrNull?.innerText.trim() ?? '');
          west  = double.tryParse(latLonBox.findElements('west', namespace: '*').firstOrNull?.innerText.trim() ?? '');
        }

        // Fallback: LatLonQuad (rotated / non-rectangular overlay)
        if (north == null) {
          final latLonQuad = go.findAllElements('LatLonQuad', namespace: '*').firstOrNull ??
                             go.findAllElements('gx:LatLonQuad', namespace: '*').firstOrNull;
          if (latLonQuad != null) {
            final coords = latLonQuad.findElements('coordinates', namespace: '*').firstOrNull?.innerText.trim() ?? '';
            final points = GeoCalculator.parseKmlCoordinates(coords);
            if (points.isNotEmpty) {
              north = points.map((p) => p['lat']!).reduce((a, b) => a > b ? a : b);
              south = points.map((p) => p['lat']!).reduce((a, b) => a < b ? a : b);
              east  = points.map((p) => p['lng']!).reduce((a, b) => a > b ? a : b);
              west  = points.map((p) => p['lng']!).reduce((a, b) => a < b ? a : b);
            }
          }
        }

        // Only add if we have valid bounds
        if (north != null && south != null && east != null && west != null) {
          shapes.add(KmlShape(
            name: name,
            type: 'overlay',
            coordinates: [],
            description: desc,
            imageUrl: href, // may be null — image found from archive later
            north: north,
            south: south,
            east: east,
            west: west,
          ));
        }
      }
    } catch (e) {
      // Return empty list on parse error
    }
    return shapes;
  }

  /// Parse KMZ file (zipped KML) - returns list of KmlShape
  /// KMZ is a ZIP archive. The main KML is typically doc.kml or any *.kml file.
  static Future<List<KmlShape>> parseKmz(List<int> kmzBytes, {String? extractDir, bool smartOpacity = false}) async {
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

      Future<List<KmlShape>> parseAndExtractImages(ArchiveFile entry) async {
        final bytes = getEntryBytes(entry);
        if (bytes == null) return [];
        final content = utf8.decode(bytes, allowMalformed: true);
        var shapes = parseKml(content);

        // Extract any images referenced by GroundOverlays
        if (extractDir != null) {
          // Collect all image/pdf entries in the archive for fallback use
          final imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.pdf'};
          final allImageEntries = archive.files.where((f) {
            if (!f.isFile) return false;
            final ext = '.${f.name.split('.').last.toLowerCase()}';
            return imageExtensions.contains(ext);
          }).toList();

          final updatedShapes = <KmlShape>[];
          for (final shape in shapes) {
            if (shape.type == 'overlay') {
              // Find image: prefer href match, fallback to first image in archive
              ArchiveFile? imgEntry;
              if (shape.imageUrl != null) {
                imgEntry = findImageEntry(shape.imageUrl!);
              }
              // Fallback: use first non-KML file that looks like an image
              imgEntry ??= allImageEntries.firstOrNull;

              if (imgEntry != null) {
                final rawContent = imgEntry.content;
                List<int>? imgBytes;
                if (rawContent is List<int>) {
                  imgBytes = rawContent;
                } else {
                  imgBytes = getEntryBytes(imgEntry);
                }
                if (imgBytes != null && imgBytes.isNotEmpty) {
                  // For tiled maps (SuperOverlays), images may be in folders like 0/0/0.jpg
                  // Flatten the path by replacing '/' with '_' to ensure unique filenames
                  final imgFileName = imgEntry.name.replaceAll('/', '_');
                  final imgFile = File('$extractDir/$imgFileName');
                  if (!imgFile.existsSync()) {
                    imgFile.writeAsBytesSync(imgBytes);
                  }
                  // If the extracted file is a PDF, convert it to PNG
                  final lowerName = imgFileName.toLowerCase();
                  if (lowerName.endsWith('.pdf')) {
                    final pngPath = await convertPdfToPng(imgFile.path);
                    if (pngPath != null) {
                      if (smartOpacity) {
                        final smartPath = await _processSmartOpacityImage(pngPath);
                        if (smartPath != null) {
                          updatedShapes.add(shape.copyWith(imageUrl: smartPath));
                          continue;
                        }
                      }
                      updatedShapes.add(shape.copyWith(imageUrl: pngPath));
                    } else {
                      // PDF conversion failed — keep imageUrl null so fallback rect shows
                      updatedShapes.add(shape); // bounds still valid, image will be missing
                    }
                    continue;
                  }
                  
                  // Normal image (JPG/PNG etc.)
                  if (smartOpacity) {
                    final smartPath = await _processSmartOpacityImage(imgFile.path);
                    if (smartPath != null) {
                      updatedShapes.add(shape.copyWith(imageUrl: smartPath));
                      continue;
                    }
                  }
                  updatedShapes.add(shape.copyWith(imageUrl: imgFile.path));
                  continue;
                }
              }
            }
            updatedShapes.add(shape);
          }
          shapes = updatedShapes;
        }
        return shapes;
      }

      final allShapes = <KmlShape>[];
      
      // Parse all *.kml files in the archive (to support SuperOverlays/tiled maps)
      for (final entry in archive.files) {
        if (!entry.name.toLowerCase().endsWith('.kml')) continue;
        final shapes = await parseAndExtractImages(entry);
        allShapes.addAll(shapes);
      }
      // Sort shapes by area descending (largest first)
      // This ensures SuperOverlay root tiles (low-res, large area) are drawn FIRST
      // and high-res tiles (small area) are drawn ON TOP of them, fixing blurry maps.
      allShapes.sort((a, b) {
        if (a.type != 'overlay' || b.type != 'overlay') return 0;
        if (a.north == null || a.south == null || a.east == null || a.west == null) return 0;
        if (b.north == null || b.south == null || b.east == null || b.west == null) return 0;
        final areaA = (a.north! - a.south!).abs() * (a.east! - a.west!).abs();
        final areaB = (b.north! - b.south!).abs() * (b.east! - b.west!).abs();
        return areaB.compareTo(areaA);
      });
      
      return allShapes;
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

  /// Generate a geo-referenced KMZ from an image + bounding box.
  /// Strictly formatted for Google Earth (Mobile/Desktop/Web) & GIS software compatibility.
  static List<int> generateGeoReferencedKmz({
    required List<int> imageBytes,
    required String imageFileName,
    required String name,
    required double north,
    required double south,
    required double east,
    required double west,
  }) {
    final n = math.max(north, south);
    final s = math.min(north, south);
    final e = math.max(east, west);
    final w = math.min(east, west);
    const safeImgName = 'overlay.png';

    final kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>$name</name>
  <GroundOverlay>
    <name>$name</name>
    <color>ffffffff</color>
    <drawOrder>1</drawOrder>
    <altitude>0</altitude>
    <altitudeMode>clampToGround</altitudeMode>
    <Icon>
      <href>$safeImgName</href>
    </Icon>
    <LatLonBox>
      <north>$n</north>
      <south>$s</south>
      <east>$e</east>
      <west>$w</west>
      <rotation>0</rotation>
    </LatLonBox>
  </GroundOverlay>
</Document>
</kml>''';

    final archive = Archive();
    final kmlBytes = utf8.encode(kml);
    archive.addFile(ArchiveFile('doc.kml', kmlBytes.length, kmlBytes));
    archive.addFile(ArchiveFile(safeImgName, imageBytes.length, imageBytes));
    return ZipEncoder().encode(archive)!;
  }

  /// Parse KML or KMZ from file path
  static Future<List<KmlShape>> parseFile(String filePath, {bool smartOpacity = false}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      // Determine type by extension (also handle uppercase extensions)
      final lowerPath = filePath.toLowerCase();

      if (lowerPath.endsWith('.kmz')) {
        final kmzBaseName = file.uri.pathSegments.last.split('.').first;
        final extractPath = '${file.parent.path}/$kmzBaseName';
        final extractDir = Directory(extractPath);

        // ⚡ Cache check: reuse already-extracted KML files (2nd load is instant)
        if (extractDir.existsSync()) {
          final cachedKmls = extractDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.kml'))
              .toList();
          if (cachedKmls.isNotEmpty) {
            final shapes = <KmlShape>[];
            final allFiles = extractDir.listSync().whereType<File>().toList();
            for (final kmlFile in cachedKmls) {
              final parsedShapes = parseKml(await kmlFile.readAsString());
              for (var i = 0; i < parsedShapes.length; i++) {
                if (parsedShapes[i].type == 'overlay' && parsedShapes[i].imageUrl != null) {
                  final hrefFilename = parsedShapes[i].imageUrl!.replaceAll('\\', '/').split('/').last.toLowerCase();
                  File? matchedFile;
                  for (final f in allFiles) {
                    final lowerF = f.path.toLowerCase();
                    if (lowerF.endsWith(hrefFilename) || (smartOpacity && lowerF.endsWith('${hrefFilename.split('.').first}_smart.png'))) {
                      matchedFile = f;
                      if (lowerF.endsWith('_smart.png')) break;
                    }
                  }
                  if (matchedFile != null) {
                    parsedShapes[i] = parsedShapes[i].copyWith(imageUrl: matchedFile.path);
                  }
                }
              }
              shapes.addAll(parsedShapes);
            }
            if (shapes.isNotEmpty) return shapes;
          }
        }

        final bytes = await file.readAsBytes();
        if (!await extractDir.exists()) {
          await extractDir.create(recursive: true);
        }
        // Hide extracted PNG tiles from Android Gallery / Google Photos
        await StorageHelper.hideDirectoryFromGallery(extractPath);
        final shapes = await parseKmz(bytes.toList(),
            extractDir: extractPath, smartOpacity: smartOpacity);

        // Save extracted KML files to disk cache for future fast loads
        try {
          final archive = ZipDecoder().decodeBytes(bytes);
          for (final entry in archive.files) {
            if (!entry.isFile) continue;
            if (!entry.name.toLowerCase().endsWith('.kml')) continue;
            final raw = entry.content;
            if (raw is List<int>) {
              final kmlFile = File('$extractPath/${entry.name.split('/').last}');
              if (!kmlFile.existsSync()) kmlFile.writeAsBytesSync(raw);
            }
          }
        } catch (_) {}

        return shapes;
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
