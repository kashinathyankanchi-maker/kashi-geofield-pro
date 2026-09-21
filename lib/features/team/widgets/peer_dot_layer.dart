import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/peer_session.dart';

/// Colors assigned to peer dots (cycles through this list).
const _kPeerColors = [
  Color(0xFFE53935), // red
  Color(0xFF8E24AA), // purple
  Color(0xFF1E88E5), // blue
  Color(0xFFFFB300), // amber
  Color(0xFF00ACC1), // cyan
  Color(0xFF43A047), // green
  Color(0xFFF4511E), // deep orange
];

Color _colorFor(String name) =>
    _kPeerColors[name.hashCode.abs() % _kPeerColors.length];

/// A flutter_map layer that renders live peer GPS dots on the map.
class PeerDotLayer extends StatelessWidget {
  const PeerDotLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PeerSession.instance,
      builder: (context, _) {
        final session = PeerSession.instance;
        if (!session.isActive || session.peerLocations.isEmpty) {
          return const SizedBox.shrink();
        }

        final markers = session.peerLocations.entries.map((entry) {
          final name = entry.key;
          final pos = entry.value;
          final heading = session.peerHeadings[name] ?? 0.0;
          final color = _colorFor(name);

          return Marker(
            point: pos,
            width: 60,
            height: 70,
            child: GestureDetector(
              onTap: () => _showPeerInfo(context, name, pos, session),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    angle: heading * pi / 180,
                    child: Icon(Icons.navigation, color: color, size: 28),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withAlpha(220),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList();

        return MarkerLayer(markers: markers);
      },
    );
  }

  void _showPeerInfo(BuildContext context, String name, LatLng pos, PeerSession session) {
    final lastSeen = session.peerLastSeen[name];
    final ago = lastSeen != null
        ? '${((DateTime.now().millisecondsSinceEpoch - lastSeen) / 1000).round()}s ago'
        : 'unknown';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.person_pin, color: _colorFor(name)),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lat: ${pos.latitude.toStringAsFixed(6)}', style: const TextStyle(color: Colors.white70)),
            Text('Lng: ${pos.longitude.toStringAsFixed(6)}', style: const TextStyle(color: Colors.white70)),
            Text('Last seen: $ago', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
