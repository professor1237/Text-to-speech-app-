import 'package:flutter_test/flutter_test.dart';
import 'package:t2s_reader/main.dart';

void main() {
  testWidgets('App boots without crashing', (tester) async {
    await tester.pumpWidget(const T2SApp());
    expect(find.text('T2S Reader'), findsOneWidget);
    // sqflite has no platform channel in widget tests — let it fail
    // quietly rather than abort the test.
    await tester.pump(const Duration(milliseconds: 200));
    tester.takeException();
  });
}
