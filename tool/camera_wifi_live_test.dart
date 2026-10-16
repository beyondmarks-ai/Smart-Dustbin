// Read-only live hardware check: flutter test tool/camera_wifi_live_test.dart
// Optional: --dart-define=CAMERA_IP=192.168.4.1 for the recovery network.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/camera_wifi_setup.dart';
import 'package:smart_dustbin/camera_location_setup.dart';

void main() {
  test('Flutter can read real camera Wi-Fi and preserved location', () async {
    const address = String.fromEnvironment(
      'CAMERA_IP',
      defaultValue: '10.111.71.234',
    );
    final wifi = CameraWifiClient();
    final location = CameraLocationClient();
    addTearDown(wifi.close);
    addTearDown(location.close);
    final state = await wifi.read(address);
    expect(state['connected'], isTrue);
    expect(state['state'], 'connected');
    expect(state['ssid'], state['saved_ssid']);
    expect(state.containsKey('password'), isFalse);
    expect(state.containsKey('setup_code'), isFalse);
    expect(state['recovery_ssid'], startsWith('EcoSort-Setup-'));
    final saved = await location.read(address);
    expect(saved, isNotNull);
    expect(saved!['latitude'], isA<num>());
    expect(saved['longitude'], isA<num>());
    // ignore: avoid_print
    print(
      'Live camera Wi-Fi and saved location verified; credentials not exposed.',
    );
  });
}
