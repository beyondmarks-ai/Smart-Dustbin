import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'camera_location_setup.dart';

class CameraPairingResult {
  const CameraPairingResult({required this.address, required this.setupCode});

  final String address;
  final String setupCode;
}

abstract interface class CameraPairingService {
  Future<CameraPairingResult> findAndPair();
}

class CameraPairingClient implements CameraPairingService {
  CameraPairingClient({http.Client? client})
    : _client = client ?? http.Client();

  static const discoveryPort = 4210;
  static const _request = 'ECOSORT_DISCOVER_V1';
  final http.Client _client;

  void close() => _client.close();

  @override
  Future<CameraPairingResult> findAndPair() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final targets = <String>{'255.255.255.255'};
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    )) {
      for (final address in interface.addresses) {
        final octets = address.address.split('.');
        if (octets.length == 4 && _isPrivate(address.address)) {
          targets.add('${octets[0]}.${octets[1]}.${octets[2]}.255');
        }
      }
    }
    final found = Completer<Map<String, dynamic>>();
    late final StreamSubscription<RawSocketEvent> subscription;
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || found.isCompleted) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final data = parseDiscovery(utf8.decode(datagram.data));
        if (!found.isCompleted) found.complete(data);
      } on FormatException {
        // Ignore unrelated UDP traffic on the discovery socket.
      }
    });
    final bytes = utf8.encode(_request);
    void discover() {
      for (final target in targets) {
        socket.send(bytes, InternetAddress(target), discoveryPort);
      }
    }

    discover();
    final timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      discover();
    });
    try {
      final data = await found.future.timeout(const Duration(seconds: 6));
      if (data['pairing_available'] != true) {
        throw StateError(
          'Camera found, but pairing is closed. Press its RST button once, then tap Find camera again.',
        );
      }
      return await pairAt(data['ip'] as String);
    } on TimeoutException {
      throw StateError(
        'Camera not found. Keep this phone and camera on the same hotspot, press camera RST once, then retry.',
      );
    } finally {
      timer.cancel();
      await subscription.cancel();
      socket.close();
    }
  }

  Future<CameraPairingResult> pairAt(String address) async {
    final base = CameraLocationClient.locationUri(address);
    final response = await _client
        .post(base.replace(path: '/pair'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 403) {
      throw StateError(
        'Pairing window closed. Press the camera RST button once, then retry.',
      );
    }
    if (response.statusCode != 200) {
      throw StateError('Camera pairing failed (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['service'] != 'ecosort-camera' ||
        decoded['version'] != 1 ||
        decoded['ip'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch('${decoded['setup_token']}')) {
      throw const FormatException('Camera returned an invalid pairing reply.');
    }
    CameraLocationClient.locationUri(decoded['ip'] as String);
    return CameraPairingResult(
      address: decoded['ip'] as String,
      setupCode: decoded['setup_token'] as String,
    );
  }

  static Map<String, dynamic> parseDiscovery(String response) {
    final decoded = jsonDecode(response);
    if (decoded is! Map<String, dynamic> ||
        decoded['service'] != 'ecosort-camera' ||
        decoded['version'] != 1 ||
        decoded['ip'] is! String ||
        decoded['pairing_available'] is! bool) {
      throw const FormatException('Invalid EcoSort discovery reply.');
    }
    CameraLocationClient.locationUri(decoded['ip'] as String);
    return decoded;
  }

  static bool _isPrivate(String address) {
    final octets = address.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((value) => value == null)) {
      return false;
    }
    return octets[0] == 10 ||
        (octets[0] == 192 && octets[1] == 168) ||
        (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31);
  }
}
