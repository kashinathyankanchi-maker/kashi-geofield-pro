import 'package:flutter_test/flutter_test.dart';
import 'package:kashi_geofield_pro/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const KashiGeoFieldApp());
    expect(find.byType(KashiGeoFieldApp), findsOneWidget);
  });
}
