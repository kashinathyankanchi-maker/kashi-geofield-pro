import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/models/fire_incident.dart';

class FireDataService {
  /// All satellite sources queried for maximum coverage
  static const List<String> _satellites = [
    'VIIRS_SNPP_NRT',    // Suomi-NPP satellite (~3 hr latency, 375m)
    'VIIRS_NOAA20_NRT',  // NOAA-20 satellite  (~3 hr latency, 375m)
    'MODIS_NRT',         // MODIS Terra+Aqua   (~6 hr latency, 1km)
  ];

  /// Parses a CSV response body into a list of FireIncident objects.
  static List<FireIncident> _parseCsv(String body) {
    final lines = const LineSplitter().convert(body);
    if (lines.isEmpty) return [];
    final headers = lines.first.split(',').map((e) => e.trim()).toList();
    final incidents = <FireIncident>[];
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final row = lines[i].split(',').map((e) => e.trim()).toList();
      if (row.length == headers.length) {
        incidents.add(FireIncident.fromCsvRow(row, headers));
      }
    }
    return incidents;
  }

  /// Fetches active fire data from ALL available satellites and merges results.
  /// Bounding box format: west, south, east, north
  static Future<List<FireIncident>> fetchActiveFires(
      String apiKey, double west, double south, double east, double north) async {
    if (apiKey.isEmpty) return [];

    // Clamp bounds to valid ranges
    if (west < -180) west = -180;
    if (south < -90) south = -90;
    if (east > 180) east = 180;
    if (north > 90) north = 90;

    final allIncidents = <FireIncident>[];
    final seenCoords = <String>{};

    // Query each satellite in parallel
    final futures = _satellites.map((satellite) async {
      final url = Uri.parse(
          'https://firms.modaps.eosdis.nasa.gov/api/area/csv/$apiKey/$satellite/$west,$south,$east,$north/1');
      try {
        final response = await http.get(url).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          return _parseCsv(response.body);
        } else {
          print('NASA FIRMS [$satellite] Error: ${response.statusCode}');
        }
      } catch (e) {
        print('FireDataService [$satellite] Error: $e');
      }
      return <FireIncident>[];
    });

    final results = await Future.wait(futures);

    // Merge, removing near-duplicate detections (same lat/lng within ~0.001 degree)
    for (final incidents in results) {
      for (final fire in incidents) {
        final key =
            '${fire.latitude.toStringAsFixed(3)},${fire.longitude.toStringAsFixed(3)}';
        if (!seenCoords.contains(key)) {
          seenCoords.add(key);
          allIncidents.add(fire);
        }
      }
    }

    print('FireDataService: Found ${allIncidents.length} unique fire points from ${_satellites.length} satellites');
    return allIncidents;
  }
}
