import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/azure_waste_repository.dart';
import 'package:smart_dustbin/dashboard_data.dart';
import 'package:smart_dustbin/main.dart';

import 'test_data.dart';

class _SequenceWasteRepository implements WasteRepository {
  _SequenceWasteRepository(this.responses);

  final List<List<WasteEntry>> responses;
  var _requestIndex = 0;

  @override
  Future<List<WasteEntry>> fetchWaste() async {
    final index = _requestIndex.clamp(0, responses.length - 1);
    _requestIndex++;
    return responses[index];
  }
}

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    WasteRepository? repository,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SmartDustbinApp(
        repository: repository ?? FakeWasteRepository(testWasteEntries),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders waste data and calculates the fill level', (
    tester,
  ) async {
    await pumpDashboard(tester);

    expect(find.text('Hello, User 👋'), findsOneWidget);
    expect(find.text('Hello, Rakesh 👋'), findsNothing);
    expect(find.byKey(const Key('menu_button')), findsNothing);
    expect(find.text('66%'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('fill_level_progress')),
          )
          .value,
      closeTo(.66, .001),
    );
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
    expect(find.byKey(const Key('clear_all_waste_button')), findsOneWidget);
  });

  testWidgets('clear-all icon confirms and resets waste and fill level', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('clear_all_waste_button')));
    await tester.pumpAndSettle();

    expect(find.text('Clear all waste?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
    await tester.pumpAndSettle();

    expect(find.text('No verified waste detected yet'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('Waste records cleared'), findsOneWidget);
  });

  testWidgets('keeps only Home and History in the fixed footer', (
    tester,
  ) async {
    await pumpDashboard(tester, size: const Size(360, 800));

    expect(tester.takeException(), isNull);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Analytics'), findsNothing);
    expect(find.text('Profile'), findsNothing);
    expect(find.byKey(const Key('bottom_navigation')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('dashboard_scroll_view')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tap verified waste for details.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolls to the latest waste after an automatic refresh', (
    tester,
  ) async {
    const latestEntry = WasteEntry(
      name: 'New Glass Jar',
      classification: 'Recyclable',
      count: 1,
      asset: 'assets/images/aluminium_foil.png',
      accent: Color(0xFF2DC65D),
      eventId: 'new-event',
    );
    final repository = _SequenceWasteRepository([
      testWasteEntries.take(1).toList(),
      [...testWasteEntries, latestEntry],
    ]);
    await pumpDashboard(tester, repository: repository);

    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const Key('dashboard_scroll_view')),
    );
    expect(scrollView.controller!.offset, 0);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('New Glass Jar'), findsOneWidget);
    expect(scrollView.controller!.offset, greaterThan(0));
    expect(find.text('68%'), findsOneWidget);
  });

  testWidgets('notification and footer controls provide tap targets', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('notification_button')));
    await tester.tap(find.text('History'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Home'), findsOneWidget);
  });
}
