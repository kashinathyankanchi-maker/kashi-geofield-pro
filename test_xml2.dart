import 'package:xml/xml.dart';
void main() {
  final kml = '''<gx:LatLonQuad><coordinates>1,1 2,2</coordinates></gx:LatLonQuad>''';
  final doc = XmlDocument.parse(kml);
  final llq = doc.findAllElements('gx:LatLonQuad').first;
  final coords = llq.findElements('coordinates').firstOrNull;
  print(coords?.innerText);
}
