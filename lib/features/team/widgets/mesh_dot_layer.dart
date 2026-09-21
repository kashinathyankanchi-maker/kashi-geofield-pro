import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/mesh_session.dart';

/// Colors assigned to mesh peer dots.
const _kMeshColors = [
  Color(0xFFFF9800), // orange
  Color(0xFFFFC107), // amber
  Color(0xFFFF5722), // deep orange
  Color(0xFF795548), // brown
  Color(0xFF8D6E63),
];

Color _colorFor(String name) =>
    _kMeshColors[name.hashCode.abs() % _kMeshColors.length];

/// A flutter_map layer that renders live mesh peer GPS dots on the map.
class MeshDotLayer extends StatelessWidget {
  const MeshDotLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MeshSession.instance,
      builder: (context, _) {
        final session = MeshSession.instance;
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
                    angle: heading * 3.14159265 / 180,
                    child: Icon(Icons.hub_rounded, color: color, size: 28),
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
                      style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
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

  void _showPeerInfo(BuildContext context, String name, LatLng pos, MeshSession session) {
    final lastSeen = session.peerLastSeen[name];
    final ago = lastSeen != null
        ? '${((DateTime.now().millisecondsSinceEpoch - lastSeen) / 1000).round()}s ago'
        : 'unknown';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D1A11), // dark brown
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.hub_rounded, color: _colorFor(name)),
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
            Text('Last seen in Mesh: $ago', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.orangeAccent))),
        ],
      ),
    );
  }
}
