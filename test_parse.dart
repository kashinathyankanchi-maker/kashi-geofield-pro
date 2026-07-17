import 'dart:io';
import 'lib/core/utils/kml_engine.dart';

void main() async {
  final kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <GroundOverlay>
      <name>Improvement WC</name>
      <Icon>
        <href>image.pdf</href>
      </Icon>
      <LatLonBox>
        <north>15.0</north>
        <south>14.0</south>
        <east>75.0</east>
        <west>74.0</west>
      </LatLonBox>
    </GroundOverlay>
  </Document>
</kml>
''';
  final shapes = KmlEngine.parseKml(kml);
  print('Found shapes: \${shapes.length}');
  if (shapes.isNotEmpty) {
    print('Type: \${shapes[0].type}, North: \${shapes[0].north}, imageUrl: \${shapes[0].imageUrl}');
  }
}
