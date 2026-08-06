import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'geotiff_parser.dart';

/// Builds a KMZ file from an image + geographic bounding box.
class KmzBuilder {
  /// Creates a KMZ file and returns the path to it.
  /// [imageFile] - source image (TIFF, JPG, PNG)
  /// [bounds] - geographic bounding box
  /// [layerName] - name shown in Google Earth
  /// [outputDir] - directory to save the KMZ
  static Future<String> build({
    required File imageFile,
    required GeoBounds bounds,
    required String layerName,
    required String outputDir,
  }) async {
    // Read image bytes
    final imageBytes = await imageFile.readAsBytes();
    
    // Determine image extension for KMZ internal reference
    final ext = p.extension(imageFile.path).toLowerCase();
    final String internalImageName;
    final Uint8List finalImageBytes;

    // KMZ supports: JPG, PNG, GIF, BMP. TIF needs to be kept as-is or noted.
    if (ext == '.tif' || ext == '.tiff') {
      // GeoTIFF — include as-is (Google Earth supports GeoTIFF overlays in KMZ)
      internalImageName = 'image.tif';
      finalImageBytes = imageBytes;
    } else if (ext == '.png') {
      internalImageName = 'image.png';
      finalImageBytes = imageBytes;
    } else {
      internalImageName = 'image.jpg';
      finalImageBytes = imageBytes;
    }

    // Build the KML content
    final kml = _buildKml(
      layerName: layerName,
      imageName: internalImageName,
      bounds: bounds,
    );

    // Create ZIP archive (KMZ = ZIP)
    final archive = Archive();

    // Add KML file
    archive.addFile(ArchiveFile(
      'doc.kml',
      kml.length,
      kml.codeUnits,
    ));

    // Add image file
    archive.addFile(ArchiveFile(
      internalImageName,
      finalImageBytes.length,
      finalImageBytes,
    ));

    // Encode as ZIP
    final zipData = ZipEncoder().encode(archive)!;

    // Save to output directory
    final safeLayerName = layerName.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = p.join(outputDir, '${safeLayerName}_$timestamp.kmz');

    final outputDir0 = Directory(outputDir);
    if (!await outputDir0.exists()) {
      await outputDir0.create(recursive: true);
      // Create .nomedia to hide from gallery
      await File(p.join(outputDir, '.nomedia')).create();
    }

    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(zipData);

    return outputPath;
  }

  static String _buildKml({
    required String layerName,
    required String imageName,
    required GeoBounds bounds,
  }) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>${_escapeXml(layerName)}</name>
    <description>Created by Kashi GeoField Pro</description>
    <GroundOverlay>
      <name>${_escapeXml(layerName)}</name>
      <Icon>
        <href>$imageName</href>
        <viewBoundScale>0.75</viewBoundScale>
      </Icon>
      <LatLonBox>
        <north>${bounds.north.toStringAsFixed(8)}</north>
        <south>${bounds.south.toStringAsFixed(8)}</south>
        <east>${bounds.east.toStringAsFixed(8)}</east>
        <west>${bounds.west.toStringAsFixed(8)}</west>
      </LatLonBox>
    </GroundOverlay>
  </Document>
</kml>''';
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
