import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xprinter_sdk_example/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('flutter_xprinter_sdk demo'), findsOneWidget);
  });
}
