import 'package:flutter_test/flutter_test.dart';
import 'package:desk_telepathy/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DeskTelepathyApp());
    expect(find.text('桌面心灵感应'), findsOneWidget);
  });
}
