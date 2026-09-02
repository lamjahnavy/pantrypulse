import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pantry_ai/main.dart';

void main() {
  testWidgets('Pantry Pulse loads', (tester) async {
    // Provide an empty list of cameras for testing
    await tester.pumpWidget(const PantryPulseApp(cameras: []));

    // Check if the title is present
    expect(find.text('Pantry Pulse'), findsOneWidget);

    // Check if the welcome message is present
    expect(find.text('Welcome to your pantry 👋'), findsOneWidget);
  });
}
