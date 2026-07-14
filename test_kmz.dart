import 'dart:io';
import 'package:archive/archive.dart';

void main() {
  final kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
	<name>Test</name>
	<Placemark>
		<name>Test Polygon</name>
		<Polygon>
			<tessellate>1</tessellate>
			<outerBoundaryIs>
				<LinearRing>
					<coordinates>
						-122.0822035425683,37.42228990140251,0 -122.0822035425683,37.42228990140251,0 
					</coordinates>
				</LinearRing>
			</outerBoundaryIs>
		</Polygon>
	</Placemark>
</Document>
</kml>''';
  
  final archive = Archive();
  final kmlBytes = kml.codeUnits;
  archive.addFile(ArchiveFile('doc.kml', kmlBytes.length, kmlBytes));
  final kmzBytes = ZipEncoder().encode(archive)!;
  File('test.kmz').writeAsBytesSync(kmzBytes);
  print('Created test.kmz');
}