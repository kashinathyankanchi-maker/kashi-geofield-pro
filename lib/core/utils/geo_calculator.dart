import 'dart:math' as math;

/// Geographic calculation utilities for area and perimeter computations.
class GeoCalculator {
  static const double _earthRadiusMeters = 6371000.0;

  /// Convert degrees to radians
  static double _toRad(double deg) => deg * math.pi / 180.0;

  /// Haversine distance between two lat/lng points in meters
  static double haversineDistance(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  /// Calculate polygon perimeter in meters from list of {lat, lng} maps
  static double calculatePerimeterMeters(List<Map<String, double>> points) {
    if (points.length < 2) return 0.0;
    double perimeter = 0.0;
    for (int i = 0; i < points.length; i++) {
      final next = points[(i + 1) % points.length];
      perimeter += haversineDistance(
        points[i]['lat']!, points[i]['lng']!,
        next['lat']!, next['lng']!,
      );
    }
    return perimeter;
  }

  /// Calculate polygon area in square meters using spherical excess formula.
  /// Returns area in square meters.
  static double calculateAreaSqMeters(List<Map<String, double>> points) {
    if (points.length < 3) return 0.0;

    // Use the spherical polygon area formula
    double area = 0.0;
    final n = points.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final p1 = points[i];
      final p2 = points[j];

      final lat1 = _toRad(p1['lat']!);
      final lng1 = _toRad(p1['lng']!);
      final lat2 = _toRad(p2['lat']!);
      final lng2 = _toRad(p2['lng']!);

      area += (lng2 - lng1) * (2 + math.sin(lat1) + math.sin(lat2));
    }

    area = (area * _earthRadiusMeters * _earthRadiusMeters / 2).abs();
    return area;
  }

  /// Convert square meters to hectares
  static double sqMetersToHectares(double sqMeters) => sqMeters / 10000.0;

  /// Convert square meters to acres
  static double sqMetersToAcres(double sqMeters) => sqMeters / 4046.856;

  /// Convert hectares to acres
  static double hectaresToAcres(double hectares) => hectares * 2.47105;

  /// Calculate area in hectares from polygon points
  static double calculateAreaHectares(List<Map<String, double>> points) {
    return sqMetersToHectares(calculateAreaSqMeters(points));
  }

  /// Format area for display
  static String formatArea(double hectares) {
    if (hectares < 0.01) {
      return '${(hectares * 10000).toStringAsFixed(1)} m²';
    } else if (hectares < 1) {
      return '${(hectares * 10000).toStringAsFixed(0)} m² (${hectares.toStringAsFixed(4)} ha)';
    } else {
      final acres = hectaresToAcres(hectares);
      return '${hectares.toStringAsFixed(4)} ha (${acres.toStringAsFixed(4)} ac)';
    }
  }

  /// Format perimeter for display
  static String formatPerimeter(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(1)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(3)} km (${meters.toStringAsFixed(0)} m)';
    }
  }

  /// Calculate centroid of a polygon
  static Map<String, double> calculateCentroid(List<Map<String, double>> points) {
    if (points.isEmpty) return {'lat': 0.0, 'lng': 0.0};
    double latSum = 0, lngSum = 0;
    for (final p in points) {
      latSum += p['lat']!;
      lngSum += p['lng']!;
    }
    return {'lat': latSum / points.length, 'lng': lngSum / points.length};
  }

  /// Parse a coordinate string like "lng,lat,0 lng,lat,0" (KML format)
  static List<Map<String, double>> parseKmlCoordinates(String coordStr) {
    final parts = coordStr.trim().split(RegExp(r'\s+'));
    final List<Map<String, double>> points = [];
    for (final part in parts) {
      if (part.trim().isEmpty) continue;
      final coords = part.split(',');
      if (coords.length >= 2) {
        final lng = double.tryParse(coords[0].trim());
        final lat = double.tryParse(coords[1].trim());
        if (lat != null && lng != null) {
          points.add({'lat': lat, 'lng': lng});
        }
      }
    }
    return points;
  }

  /// Convert points list to KML coordinate string
  static String toKmlCoordinates(List<Map<String, double>> points) {
    return points.map((p) => '${p['lng']},${p['lat']},0').join(' ');
  }
}
