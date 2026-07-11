import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

class CompassWidget extends StatelessWidget {
  final double size;
  const CompassWidget({super.key, this.size = 50.0});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        double? direction = snapshot.data?.heading;

        // if direction is null, device doesn't support compass
        if (direction == null) {
          return const SizedBox.shrink();
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Transform.rotate(
            angle: (direction * (math.pi / 180) * -1),
            child: Icon(
              Icons.navigation,
              color: Colors.redAccent,
              size: size * 0.6,
            ),
          ),
        );
      },
    );
  }
}
