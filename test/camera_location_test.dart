import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_dustbin/camera_location_setup.dart';

class _Gps extends GeolocatorPlatform {
  bool enabled = true;
  bool fail = false;
  LocationPermission permission = LocationPermission.whileInUse;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (fail) throw TimeoutException('No GPS fix');
    return Position(
      latitude: 12.3456789,
      longitude: 76.1234567,
      timestamp: DateTime.now(),
      accuracy: 18,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  Future<Map<String, dynamic>> save(
    CameraLocationClient client, {
    double latitude = 12.3,
    String source = 'manual',
    DateTime? at,
  }) => client.save(
    address: '10.111.71.234',
    code: '0123456789abcdef0123456789abcdef',
    latitude: latitude,
    longitude: 76.1,
    label: 'Test bin',
    placeAddress: '',
    source: source,
    accuracy: source == 'phone_gps' ? 12 : null,
    measuredAt: at,
  );

  test('allows only private camera addresses', () {
    expect(CameraLocationClient.locationUri('10.111.71.234').path, '/location');
    expect(
      CameraLocationClient.locationUri('http://192.168.1.4/').host,
      '192.168.1.4',
    );
    for (final address in [
      'https://example.com',
      '8.8.8.8',
      '127.0.0.1',
      'http://user@10.1.1.1',
      'http://10.1.1.1/?x=1',
    ]) {
      expect(
        () => CameraLocationClient.locationUri(address),
        throwsFormatException,
      );
    }
  });

  test(
    'saves coordinates with camera code and verifies acknowledgement',
    () async {
      final client = CameraLocationClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.followRedirects, false);
          expect(
            request.headers['x-setup-token'],
            '0123456789abcdef0123456789abcdef',
          );
          expect(request.bodyFields['source'], 'manual');
          expect(request.bodyFields['latitude'], '12.3000000');
          return http.Response(
            jsonEncode({
              'detection_location': {'latitude': 12.3, 'longitude': 76.1},
            }),
            200,
          );
        }),
      );
      expect((await save(client))['latitude'], 12.3);
      client.close();
    },
  );

  test(
    'rejects invalid coordinates and stale phone fixes before sending',
    () async {
      final client = CameraLocationClient(
        client: MockClient((_) async => throw StateError('Must not send')),
      );
      expect(save(client, latitude: double.nan), throwsFormatException);
      expect(save(client, latitude: 91), throwsFormatException);
      expect(
        save(
          client,
          source: 'phone_gps',
          at: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        throwsFormatException,
      );
      client.close();
    },
  );

  test(
    'does not report success for a wrong setup code or mismatched coordinates',
    () async {
      final denied = CameraLocationClient(
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(save(denied), throwsStateError);
      denied.close();
      final mismatch = CameraLocationClient(
        client: MockClient(
          (_) async => http.Response(
            '{"detection_location":{"latitude":0,"longitude":0}}',
            200,
          ),
        ),
      );
      await expectLater(save(mismatch), throwsStateError);
      mismatch.close();
    },
  );

  for (final scenario in ['disabled', 'denied', 'timeout', 'success']) {
    testWidgets('phone location handles $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final original = GeolocatorPlatform.instance;
      final gps = _Gps()
        ..enabled = scenario != 'disabled'
        ..permission = scenario == 'denied'
            ? LocationPermission.deniedForever
            : LocationPermission.whileInUse
        ..fail = scenario == 'timeout';
      GeolocatorPlatform.instance = gps;
      addTearDown(() => GeolocatorPlatform.instance = original);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CameraLocationSetup()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('use_phone_location')));
      await tester.pumpAndSettle();
      final expected = switch (scenario) {
        'disabled' => 'Turn on phone Location',
        'denied' => 'Allow location permission',
        'timeout' => 'Request timed out',
        _ => 'accuracy about 18 m',
      };
      expect(find.textContaining(expected), findsOneWidget);
      if (scenario == 'success') {
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('bin_latitude')))
              .controller!
              .text,
          '12.3456789',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
