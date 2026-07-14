import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
void main() {
  var overlay = OverlayImage(
    bounds: LatLngBounds.fromPoints([]),
    imageProvider: const AssetImage('test.jpg'),
    opacity: 0.5,
  );
  var layer = OverlayImageLayer(
    overlayImages: [overlay],
  );
}
