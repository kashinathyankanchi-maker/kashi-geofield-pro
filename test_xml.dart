import 'package:xml/xml.dart';
void main() {
  final kml = '''<gx:LatLonQuad xmlns:gx="http://www.google.com/kml/ext/2.2"><coordinates>1,1</coordinates></gx:LatLonQuad>''';
  final doc = XmlDocument.parse(kml);
  final e1 = doc.findAllElements('gx:LatLonQuad', namespace: '*').firstOrNull;
  final e2 = doc.findAllElements('LatLonQuad', namespace: '*').firstOrNull;
  print(e1 != null);
  print(e2 != null);
}
