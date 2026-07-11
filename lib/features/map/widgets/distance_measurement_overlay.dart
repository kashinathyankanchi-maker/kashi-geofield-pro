import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import '../../../core/utils/geo_calculator.dart';

class DistanceMeasurementOverlay extends StatelessWidget {
  final LatLng? currentPosition;
  final fmap.MapController mapController;
  final VoidCallback onClose;

  const DistanceMeasurementOverlay({
    super.key,
    required this.currentPosition,
    required this.mapController,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (currentPosition == null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: const Text('Waiting for GPS...', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return StreamBuilder<fmap.MapEvent>(
      stream: mapController.mapEventStream,
      builder: (context, snapshot) {
        // Find the center of the screen map camera
        final camera = mapController.camera;
        final targetLatLng = camera.center;

        // Calculate distance
        final distanceMeters = GeoCalculator.calculatePerimeterMeters([
          {'lat': currentPosition!.latitude, 'lng': currentPosition!.longitude},
          {'lat': targetLatLng.latitude, 'lng': targetLatLng.longitude},
        ]);

        return CustomPaint(
          size: Size.infinite,
          painter: _DistancePainter(
            camera: camera,
            startPos: currentPosition!,
            endPos: targetLatLng,
            distanceText: '\${distanceMeters.toStringAsFixed(0)} m',
          ),
        );
      },
    );
  }
}

class _DistancePainter extends CustomPainter {
  final fmap.MapCamera camera;
  final LatLng startPos;
  final LatLng endPos;
  final String distanceText;

  _DistancePainter({
    required this.camera,
    required this.startPos,
    required this.endPos,
    required this.distanceText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // We only paint if the start position is visible or at least reasonably within bounds
    // latLngToScreenPoint throws or returns weird things if camera isn't ready, but it's usually fine
    
    // Let's wrap in try-catch just in case the points are completely off the map projection bounds
    try {
      final startPoint = camera.latLngToScreenPoint(startPos);
      final endPoint = camera.latLngToScreenPoint(endPos); // should be exact center of screen

      final p1 = Offset(startPoint.x, startPoint.y);
      final p2 = Offset(endPoint.x, endPoint.y);

      // 1. Draw the line
      final linePaint = Paint()
        ..color = const Color(0xFF29B6F6) // Tactical Blue
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(p1, p2, shadowPaint);
      canvas.drawLine(p1, p2, linePaint);

      // 2. Draw the target dot at the center
      final dotBgPaint = Paint()..color = Colors.white;
      final dotStrokePaint = Paint()
        ..color = const Color(0xFF29B6F6)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(p2, 6, dotBgPaint);
      canvas.drawCircle(p2, 6, dotStrokePaint);

      // 3. Draw the distance text next to the target dot
      const textStyle = TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        shadows: [
          Shadow(offset: Offset(1, 1), blurRadius: 3.0, color: Colors.black87),
        ],
      );
      final textSpan = TextSpan(text: distanceText, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Position text slightly to the right and bottom of the center
      final textOffset = Offset(p2.dx + 12, p2.dy + 8);
      textPainter.paint(canvas, textOffset);
      
    } catch (e) {
      // Ignore projection errors during edge-case map movements
    }
  }

  @override
  bool shouldRepaint(covariant _DistancePainter oldDelegate) {
    return oldDelegate.camera != camera ||
           oldDelegate.startPos != startPos ||
           oldDelegate.endPos != endPos ||
           oldDelegate.distanceText != distanceText;
  }
}
