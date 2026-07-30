import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/azure_waste_repository.dart';
import 'test_data.dart';
import 'package:smart_dustbin/main.dart';

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SmartDustbinApp(repository: FakeWasteRepository(testWasteEntries)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders all smart dustbin dashboard data', (tester) async {
    await pumpDashboard(tester);

    expect(find.text('Hello, Rakesh 👋'), findsOneWidget);
    expect(find.text('Smart Dustbin 01'), findsNothing);
    expect(find.text('Connected'), findsNothing);
    expect(find.text('87%'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Waste Inside Dustbin'), findsOneWidget);

    for (final label in const [
      'Plastic Bottle',
      'Paper',
      'Food Waste',
      'Chip Packet',
      'Aluminium Foil',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(find.text('33'), findsOneWidget);
    expect(find.text('AI-verified waste\ninsights only.'), findsOneWidget);
    expect(find.byKey(const Key('dustbin_image')), findsOneWidget);
    expect(find.byKey(const Key('bottom_navigation')), findsOneWidget);
  });

  testWidgets('keeps navigation fixed and scrolls on compact phones', (
    tester,
  ) async {
    await pumpDashboard(tester, size: const Size(360, 800));

    expect(tester.takeException(), isNull);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('dashboard_scroll_view')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tap verified waste for details.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header and navigation controls provide tap targets', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('menu_button')));
    await tester.tap(find.byKey(const Key('notification_button')));
    await tester.tap(find.text('History'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Home'), findsOneWidget);
  });
}
