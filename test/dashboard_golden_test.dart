import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/azure_waste_repository.dart';
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
}
