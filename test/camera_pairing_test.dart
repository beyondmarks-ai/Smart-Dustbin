import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_dustbin/camera_location_setup.dart';
import 'package:smart_dustbin/camera_pairing.dart';

const _code = '0123456789abcdef0123456789abcdef';

class _Pairing implements CameraPairingService {
  @override
  Future<CameraPairingResult> findAndPair() async =>
      const CameraPairingResult(address: '10.1.2.3', setupCode: _code);
}

void main() {
  test('validates discovery and exchanges it for a setup credential', () async {
    final discovery = CameraPairingClient.parseDiscovery(
      jsonEncode({
        'service': 'ecosort-camera',
        'version': 1,
        'ip': '10.1.2.3',
        'pairing_available': true,
      }),
    );
    expect(discovery['ip'], '10.1.2.3');

    final client = CameraPairingClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'http://10.1.2.3/pair');
        return http.Response(
          jsonEncode({
            'service': 'ecosort-camera',
            'version': 1,
            'ip': '10.1.2.3',
            'setup_token': _code,
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    final paired = await client.pairAt('10.1.2.3');
    expect(paired.address, '10.1.2.3');
    expect(paired.setupCode, _code);
  });

  test('rejects public addresses and closed pairing windows', () async {
    expect(
      () => CameraPairingClient.parseDiscovery(
        '{"service":"ecosort-camera","version":1,"ip":"8.8.8.8","pairing_available":true}',
      ),
      throwsFormatException,
    );
    final client = CameraPairingClient(
      client: MockClient((_) async => http.Response('', 403)),
    );
    addTearDown(client.close);
    await expectLater(client.pairAt('10.1.2.3'), throwsStateError);
  });

  testWidgets('one tap pairing stores IP and code without showing fields', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CameraLocationSetup(pairing: _Pairing()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('find_camera')));
    await tester.pumpAndSettle();
    expect(find.textContaining('found and paired'), findsOneWidget);
    expect(find.byKey(const Key('camera_ip')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('camera_location_ip'), '10.1.2.3');
    expect(prefs.getString('camera_location_code'), _code);
  });
}
