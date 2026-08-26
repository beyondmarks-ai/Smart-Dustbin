import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/aws_waste_repository.dart';
import 'test_data.dart';
import 'package:smart_dustbin/main.dart';

void main() {
  testWidgets('home dashboard visual regression', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SmartDustbinApp(repository: FakeWasteRepository(testWasteEntries)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SmartDustbinApp),
      matchesGoldenFile('goldens/home_dashboard.png'),
    );
  });

  testWidgets('waste trend chart visual regression', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SmartDustbinApp(repository: FakeWasteRepository(testWasteEntries)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('navigation_insights')));
    await tester.pumpAndSettle();

    final chartCard = find.byKey(const Key('date_wise_waste_chart_card'));
    await tester.ensureVisible(chartCard);
    await tester.pumpAndSettle();

    await expectLater(
      chartCard,
      matchesGoldenFile('goldens/waste_trend_chart.png'),
    );
  });
}
