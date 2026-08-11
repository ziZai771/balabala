import 'package:flutter_test/flutter_test.dart';

import 'package:balabala/main.dart';

void main() {
  testWidgets('App should launch', (WidgetTester tester) async {
    await tester.pumpWidget(const BalabalaApp());
    expect(find.text('书架'), findsWidgets);
  });
}
