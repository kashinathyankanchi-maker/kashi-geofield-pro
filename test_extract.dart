import 'dart:io';
import 'package:xml/xml.dart';

void main() {
  final kmlStr = '''
  <kml xmlns="http://www.opengis.net/kml/2.2">
    <Folder>
      <GroundOverlay>
        <name>Test</name>
        <Icon>
          <href>files/image.jpg</href>
        </Icon>
        <LatLonBox>
          <north>37.83</north>
          <south>37.81</south>
          <east>-122.47</east>
          <west>-122.50</west>
        </LatLonBox>
      </GroundOverlay>
    </Folder>
  </kml>
  ''';
  
  final doc = XmlDocument.parse(kmlStr);
  final groundOverlays = doc.findAllElements('GroundOverlay');
  for (final go in groundOverlays) {
    final name = go.findElements('name').firstOrNull?.innerText.trim() ?? 'Image Overlay';
    final icon = go.findAllElements('Icon').firstOrNull;
    final href = icon?.findElements('href').firstOrNull?.innerText.trim();
    final latLonBox = go.findAllElements('LatLonBox').firstOrNull;
    
    print(name);
    print(href);
    print(latLonBox != null);
    
    if (href != null && latLonBox != null) {
      final north = double.tryParse(latLonBox.findElements('north').firstOrNull?.innerText.trim() ?? '');
      print(north);
    }
  }
}
