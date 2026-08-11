import 'package:flutter_test/flutter_test.dart';
import 'package:hash_code/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
  });
}
