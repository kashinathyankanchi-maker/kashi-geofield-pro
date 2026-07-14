import 'lib/core/utils/kml_engine.dart';
void main() async {
  final shapes = await KmlEngine.parseFile('test.kmz');
  print('Parsed shapes: ' + shapes.length.toString());
  for (var s in shapes) {
    print(s.name + ' - ' + s.type + ' - ' + s.coordinates.length.toString() + ' points');
  }
}
