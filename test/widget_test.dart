import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/aws_waste_repository.dart';
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
    expect(find.byKey(const Key('dustbin_image')), findsNothing);
    expect(find.byKey(const Key('recycling_banner')), findsNothing);

    await tester.drag(
      find.byKey(const Key('dashboard_scroll_view')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

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
    expect(find.byKey(const Key('waste_inventory_total')), findsOneWidget);
    expect(find.byKey(const Key('clear_all_waste_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation_insights')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insights_scroll_view')), findsOneWidget);
    expect(find.byKey(const Key('waste_total_items_chart')), findsOneWidget);
    expect(find.byKey(const Key('waste_statistics_card')), findsOneWidget);
    expect(find.byKey(const Key('waste_category_chart')), findsOneWidget);
    expect(find.byKey(const Key('waste_composition_chart')), findsOneWidget);
    expect(find.text('Waste Statistics'), findsOneWidget);
    expect(find.text('Recyclable'), findsWidgets);
    expect(find.text('Organic'), findsWidgets);
    expect(find.text('Non-recyclable'), findsWidgets);
    expect(find.byKey(const Key('environmental_impact_card')), findsOneWidget);
    expect(find.text('Environmental Impact'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('1.8 kg'), findsOneWidget);
    expect(find.byKey(const Key('date_wise_waste_chart_card')), findsOneWidget);
    expect(find.byKey(const Key('date_wise_waste_chart')), findsOneWidget);
    expect(find.text('Waste Trend'), findsOneWidget);
    expect(find.text('Recyclable vs non-recyclable by date'), findsOneWidget);
    expect(find.text('Detection date'), findsOneWidget);
  });

  testWidgets('clear-all icon confirms and resets waste and fill level', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.drag(
      find.byKey(const Key('dashboard_scroll_view')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear_all_waste_button')));
    await tester.pumpAndSettle();

    expect(find.text('Clear all waste?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
    await tester.pumpAndSettle();

    expect(find.text('No verified waste detected yet'), findsOneWidget);
    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const Key('dashboard_scroll_view')),
    );
    scrollView.controller!.jumpTo(0);
    await tester.pump();
    expect(find.byKey(const Key('fill_level_percentage')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('fill_level_percentage'))).data,
      '0%',
    );
    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('Waste records cleared'), findsOneWidget);
  });

  testWidgets('keeps Home, Insights and History in the fixed footer', (
    tester,
  ) async {
    await pumpDashboard(tester, size: const Size(360, 800));

    expect(tester.takeException(), isNull);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Analytics'), findsNothing);
    expect(find.text('Profile'), findsNothing);
    expect(find.byKey(const Key('bottom_navigation')), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation_insights')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insights_scroll_view')), findsOneWidget);
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
    scrollView.controller!.jumpTo(0);
    await tester.pump();
    expect(find.text('68%'), findsOneWidget);
  });

  testWidgets('footer switches between Home, Insights and History', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('notification_button')));
    await tester.tap(find.byKey(const Key('navigation_insights')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insights_scroll_view')), findsOneWidget);
    expect(find.text('Waste Statistics'), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation_history')));
    await tester.pumpAndSettle();

    expect(find.text('Waste History'), findsOneWidget);
    expect(find.text('5 records'), findsOneWidget);
    expect(find.text('33 total items detected'), findsOneWidget);
    expect(find.byKey(const Key('history_entry_0')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_scroll_view')), findsNothing);

    await tester.tap(find.byKey(const Key('navigation_home')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('dashboard_scroll_view')), findsOneWidget);
    expect(find.text('Waste History'), findsNothing);
  });
}
