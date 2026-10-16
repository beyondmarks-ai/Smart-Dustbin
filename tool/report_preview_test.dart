// ignore_for_file: invalid_use_of_visible_for_testing_member
// Run on Windows: flutter test tool/ui_preview_test.dart --update-goldens
// Uses local fixture data only; no records are sent to Azure.
import 'dart:io';
import '../test/test_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/app_flow.dart';
import 'package:smart_dustbin/app_preferences.dart';
import 'package:smart_dustbin/aws_waste_repository.dart';
import 'package:smart_dustbin/dashboard_data.dart';
import 'package:smart_dustbin/detection_location.dart';
import 'package:smart_dustbin/feature_pages.dart';
import 'package:smart_dustbin/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Report Symbols')..addFont(
          File(
            'C:/Windows/Fonts/arial.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        ))
        .load();
    await (FontLoader('Ahem')..addFont(
          File(
            'C:/Windows/Fonts/segoeui.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        ))
        .load();
    await (FontLoader('Noto Color Emoji')..addFont(
          File(
            'C:/Users/rkmai/scoop/apps/flutter/current/engine/src/flutter/txt/third_party/fonts/NotoColorEmoji.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final file = File(
      'C:/Users/rkmai/scoop/apps/flutter/current/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
    );
    if (await file.exists()) {
      await (FontLoader('Roboto')
            ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b))))
          .load();
    }
  });
  const sample = WasteEntry(
    name: 'Plastic Bottle',
    classification: 'Recyclable',
    count: 1,
    accent: Color(0xFF2C9851),
    asset: 'assets/images/plastic_bottle.png',
    confidence: '94',
    recyclable: true,
    category: 'plastic',
    material: 'PET',
    latitude: 17.9104,
    longitude: 77.5199,
    locationLabel: 'Guru Nanak Dev Engineering College',
    locationAddress: 'Nehru Nagar, Bidar, Karnataka 585403',
    deviceId: 'camera-preview',
    capturedAt: '2026-10-05T03:02:00Z',
  );
  testWidgets('render feature previews', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    tester.view.physicalSize = const Size(390, 1040);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    await appPreferences.load();
    Future<void> capture(String name, Widget page) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ecoTheme(Brightness.light),
          home: page,
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/images/plastic_bottle.png'),
          tester.element(find.byType(Scaffold).first),
        );
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/report-previews/$name.png'),
      );
      await tester.pumpWidget(const SizedBox());
    }

    await capture('welcome', WelcomeScreen(onGetStarted: () {}));
    await capture('details', const DetectionDetailsPage(entry: sample));
    appPreferences.reviews.addAll([
      LocalReview(
        'Really happy with how easy it is to use.',
        DateTime(2026, 10, 5, 8),
        Sentiment.positive,
      ),
      LocalReview(
        'The connection was slow today.',
        DateTime(2026, 10, 4, 12),
        Sentiment.negative,
      ),
      LocalReview(
        'I used the app this morning.',
        DateTime(2026, 10, 4, 8),
        Sentiment.neutral,
      ),
    ]);
    await capture(
      'feedback',
      const Scaffold(body: SafeArea(child: FeedbackPage())),
    );
    await capture(
      'settings',
      Scaffold(
        body: SafeArea(
          child: SettingsPage(
            cloudOnline: true,
            checking: false,
            onRefresh: () {},
            onEmpty: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      const SmartDustbinApp(
        repository: FakeWasteRepository([sample, ...testWasteEntries]),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/report-previews/dashboard.png'),
    );
    await tester.tap(find.byKey(const Key('navigation_insights')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/report-previews/analytics.png'),
    );
    await tester.tap(find.byKey(const Key('navigation_history')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/report-previews/history.png'),
    );
    await appPreferences.setTheme(ThemeMode.dark);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/report-previews/history-dark.png'),
    );
    await tester.pumpWidget(const SizedBox());
    await appPreferences.setTheme(ThemeMode.light);
  });
}
