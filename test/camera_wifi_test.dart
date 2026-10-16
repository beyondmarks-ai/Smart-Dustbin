import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_dustbin/camera_wifi_setup.dart';

const code = '0123456789abcdef0123456789abcdef';
Map<String, dynamic> status([String state = 'connected']) => {
  'version': 1,
  'connected': state != 'testing',
  'state': state,
  'ssid': 'Test hotspot',
  'saved_ssid': 'Test hotspot',
  'ip': '10.1.2.3',
  'recovery_ssid': 'EcoSort-Setup-1234',
};

void main() {
  test('validates SSID byte count, password format and setup code', () {
    CameraWifiClient.validate(' My hotspot ', ' pass123 ', code);
    CameraWifiClient.validate('test', 'a' * 64, code);
    for (final ssid in ['', 'x' * 33, '界' * 11, 'bad\nname']) {
      expect(
        () => CameraWifiClient.validate(ssid, 'password1', code),
        throwsFormatException,
      );
    }
    for (final password in ['', 'short', 'g' * 64, 'abc\n12345', 'passwordé']) {
      expect(
        () => CameraWifiClient.validate('Test', password, code),
        throwsFormatException,
      );
    }
    expect(
      () => CameraWifiClient.validate('Test', 'password1', 'bad'),
      throwsFormatException,
    );
  });

  test(
    'sends private, authenticated POST without redirects or trimming password',
    () async {
      final client = CameraWifiClient(
        client: MockClient((r) async {
          expect(r.url.toString(), 'http://10.1.2.3/wifi');
          expect(r.method, 'POST');
          expect(r.followRedirects, false);
          expect(r.headers['x-setup-token'], code);
          expect(r.bodyFields, {'ssid': ' Test ', 'password': ' password '});
          expect(r.url.query, isEmpty);
          return http.Response('{"accepted":true,"state":"testing"}', 202);
        }),
      );
      addTearDown(client.close);
      await client.change(
        address: '10.1.2.3',
        code: code,
        ssid: ' Test ',
        password: ' password ',
      );
      await expectLater(
        client.change(
          address: 'example.com',
          code: code,
          ssid: 'Test',
          password: 'password',
        ),
        throwsFormatException,
      );
    },
  );

  for (final statusCode in [401, 404, 409, 429, 500]) {
    test('reports HTTP $statusCode without claiming success', () async {
      final client = CameraWifiClient(
        client: MockClient((_) async => http.Response('', statusCode)),
      );
      addTearDown(client.close);
      await expectLater(
        client.change(
          address: '10.1.2.3',
          code: code,
          ssid: 'Test',
          password: 'password',
        ),
        throwsStateError,
      );
    });
  }

  test('rejects malformed acknowledgements and status', () async {
    final client = CameraWifiClient(
      client: MockClient(
        (r) async => http.Response('{}', r.method == 'POST' ? 202 : 200),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.change(
        address: '10.1.2.3',
        code: code,
        ssid: 'Test',
        password: 'password',
      ),
      throwsFormatException,
    );
    await expectLater(client.read('10.1.2.3'), throwsFormatException);
  });

  testWidgets(
    'accepted trial is pending, password cleared and never persisted',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'camera_location_ip': '10.1.2.3',
        'camera_location_code': code,
      });
      var postCount = 0;
      final client = CameraWifiClient(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            postCount++;
            return http.Response('{"accepted":true,"state":"testing"}', 202);
          }
          return http.Response(jsonEncode(status()), 200);
        }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(home: CameraWifiSetup(client: client)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('wifi_ssid')),
        'Test hotspot',
      );
      await tester.enterText(
        find.byKey(const Key('wifi_password')),
        'password1',
      );
      await tester.ensureVisible(find.byKey(const Key('wifi_save')));
      await tester.tap(find.byKey(const Key('wifi_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(postCount, 0);
      await tester.tap(find.byKey(const Key('wifi_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(postCount, 1);
      expect(
        find.textContaining('Trial accepted — not yet saved'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('wifi_password')))
            .controller!
            .text,
        isEmpty,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((key) => key.contains('password')), isEmpty);
      expect(prefs.getString('camera_wifi_target'), 'Test hotspot');
      await tester.scrollUntilVisible(
        find.text('Check connection'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check connection'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('wifi_result')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Saved network confirmed'), findsOneWidget);
      expect(prefs.getString('camera_wifi_target'), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in ['testing', 'rolled_back', 'save_failed']) {
    testWidgets('status $state never claims credentials saved', (tester) async {
      SharedPreferences.setMockInitialValues({
        'camera_location_ip': '10.1.2.3',
        'camera_location_code': code,
      });
      final client = CameraWifiClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode(status(state)), 200),
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(home: CameraWifiSetup(client: client)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check connection'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('wifi_result')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Saved network confirmed'), findsNothing);
      expect(
        find.textContaining(state == 'testing' ? 'Not saved yet' : 'not saved'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a different connected SSID is not confirmation of the requested change',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'camera_location_ip': '10.1.2.3',
        'camera_wifi_target': 'New hotspot',
      });
      final client = CameraWifiClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode(status()), 200),
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(home: CameraWifiSetup(client: client)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check connection'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('wifi_result')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('requested network is not confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('Saved network confirmed'), findsNothing);
    },
  );

  testWidgets('recovery password is hidden until requested', (tester) async {
    SharedPreferences.setMockInitialValues({'camera_location_code': code});
    await tester.pumpWidget(const MaterialApp(home: CameraWifiSetup()));
    await tester.pumpAndSettle();
    expect(find.text(code.substring(0, 16)), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Show recovery Wi-Fi password'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Show recovery Wi-Fi password'));
    await tester.pumpAndSettle();
    expect(find.text(code.substring(0, 16)), findsOneWidget);
  });
}
