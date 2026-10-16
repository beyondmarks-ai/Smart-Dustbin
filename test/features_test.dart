import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_dustbin/app_preferences.dart';
import 'package:smart_dustbin/app_flow.dart';
import 'package:smart_dustbin/aws_waste_repository.dart';
import 'package:smart_dustbin/home_dashboard.dart';
import 'package:smart_dustbin/main.dart';
import 'package:smart_dustbin/detection_location.dart';
import 'package:smart_dustbin/feature_pages.dart';
import 'test_data.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await appPreferences.load();
    AppColors.dark = false;
  });
  void phone(WidgetTester tester, [Size size = const Size(390, 844)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> drawer(WidgetTester tester, String label) async {
    final menu = find.byTooltip('Open navigation');
    if (menu.evaluate().isNotEmpty) {
      await tester.tap(menu.first);
    } else {
      await tester.tap(find.byKey(const Key('menu_button')));
    }
    await tester.pumpAndSettle();
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  test('sentiment handles negation and mixed or neutral reviews', () {
    expect(
      classifySentiment('Really happy, fast and helpful'),
      Sentiment.positive,
    );
    expect(classifySentiment('Not good. It crashed.'), Sentiment.negative);
    expect(classifySentiment('Not bad'), Sentiment.positive);
    expect(classifySentiment('Good but slow'), Sentiment.neutral);
    expect(classifySentiment('I used this today'), Sentiment.neutral);
  });

  test('review, theme and capacity survive preference reload', () async {
    await appPreferences.postReview('Great and useful');
    await appPreferences.setTheme(ThemeMode.dark);
    await appPreferences.setCapacity(80);
    await appPreferences.emptyBin();
    await appPreferences.load();
    expect(appPreferences.reviews.length, 1);
    expect(appPreferences.reviews.single.sentiment, Sentiment.positive);
    expect(appPreferences.themeMode, ThemeMode.dark);
    expect(appPreferences.capacity, 80);
    expect(appPreferences.emptiedAt, isNotNull);
  });

  testWidgets(
    'welcome remains on launch with a saved session and logout clears it',
    (tester) async {
      phone(tester);
      await appPreferences.setSession(true);
      await tester.pumpWidget(
        MaterialApp(
          home: EcoSortFlow(repository: FakeWasteRepository(testWasteEntries)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('get_started_button')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeDashboard), findsOneWidget);
      await drawer(tester, 'Logout');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(appPreferences.session, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('welcome fits a small phone and allows scrolling', (
    tester,
  ) async {
    phone(tester, const Size(320, 568));
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(onGetStarted: () {})),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('get_started_button')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer links, posting a review, reset and dark theme work', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      SmartDustbinApp(repository: FakeWasteRepository(testWasteEntries)),
    );
    await tester.pumpAndSettle();
    await drawer(tester, 'Location');
    expect(find.text('Camera location'), findsOneWidget);
    await drawer(tester, 'Sentiment analysis');
    expect(find.byType(FeedbackPage), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('review_input')),
      'Great, easy and useful',
    );
    await tester.ensureVisible(find.text('Post review'));
    await tester.tap(find.text('Post review'));
    await tester.pumpAndSettle();
    expect(appPreferences.reviews.length, 1);
    expect(find.text('100%'), findsOneWidget);
    await drawer(tester, 'Settings');
    expect(find.text('Cloud service online'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('Bin emptied · reset fill level')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bin emptied · reset fill level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset fill level'));
    await tester.pumpAndSettle();
    await appPreferences.setTheme(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );
    await drawer(tester, 'Dashboard');
    expect(
      tester.widget<Text>(find.byKey(const Key('fill_level_percentage'))).data,
      '0%',
    );
    await tester.tap(find.byKey(const Key('navigation_history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history_entry_0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('history_entry_0')));
    await tester.pumpAndSettle();
    expect(find.byType(DetectionDetailsPage), findsOneWidget);
    expect(find.text('Capture location'), findsOneWidget);
    expect(find.textContaining('Location was not recorded'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
