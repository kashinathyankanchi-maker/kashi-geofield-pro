import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/models/fire_incident.dart';

class FireDataService {
  /// Fetches active fire data for the last 24 hours within the specified bounding box.
  /// Bounding box format: west, south, east, north
  static Future<List<FireIncident>> fetchActiveFires(
      String apiKey, double west, double south, double east, double north) async {
    if (apiKey.isEmpty) return [];

    // Ensure bounds are within valid ranges
    if (west < -180) west = -180;
    if (south < -90) south = -90;
    if (east > 180) east = 180;
    if (north > 90) north = 90;

    // FIRMS API URL for VIIRS NRT (Near Real-Time) data
    final url = Uri.parse(
        'https://firms.modaps.eosdis.nasa.gov/api/area/csv/$apiKey/VIIRS_SNPP_NRT/$west,$south,$east,$north/1');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final lines = const LineSplitter().convert(response.body);
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
      } else {
        print('NASA FIRMS API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('FireDataService Error: $e');
    }
    return [];
  }
}
