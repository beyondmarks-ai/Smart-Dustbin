import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class CameraStatusUpdate {
  const CameraStatusUpdate({
    required this.state,
    required this.eventId,
    required this.completedEvents,
    required this.failedEvents,
  });

  final String state;
  final String eventId;
  final int completedEvents;
  final int failedEvents;

  static CameraStatusUpdate parse(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded['service'] != 'ecosort-camera' ||
        decoded['version'] != 1 ||
        decoded['state'] is! String ||
        decoded['event_id'] is! String ||
        decoded['completed_events'] is! int ||
        decoded['failed_events'] is! int) {
      throw const FormatException('Invalid camera status update.');
    }
    return CameraStatusUpdate(
      state: decoded['state'] as String,
      eventId: decoded['event_id'] as String,
      completedEvents: decoded['completed_events'] as int,
      failedEvents: decoded['failed_events'] as int,
    );
  }
}

abstract interface class CameraStatusService {
  Stream<CameraStatusUpdate> get updates;
  Future<void> start();
  void close();
}

class UdpCameraStatusService implements CameraStatusService {
  static const _cameraPort = 4210;
  static const _subscribeMessage = 'ECOSORT_SUBSCRIBE_V1';

  final _updates = StreamController<CameraStatusUpdate>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _subscribeTimer;
  bool _closed = false;

  @override
  Stream<CameraStatusUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    if (_closed || _socket != null) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    if (_closed) {
      socket.close();
      return;
    }
    _socket = socket;
    _subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        _updates.add(CameraStatusUpdate.parse(utf8.decode(datagram.data)));
      } on FormatException {
        // Discovery acknowledgements and unrelated UDP traffic are ignored.
      }
    });
    await _subscribe();
    _subscribeTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_subscribe()),
    );
  }

  Future<void> _subscribe() async {
    final socket = _socket;
    if (_closed || socket == null) return;
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // Widget tests and unsupported platforms may not register the plugin.
      return;
    }
    final address = prefs.getString('camera_location_ip')?.trim() ?? '';
    final ip = InternetAddress.tryParse(address);
    if (ip == null || ip.type != InternetAddressType.IPv4) return;
    socket.send(utf8.encode(_subscribeMessage), ip, _cameraPort);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _subscribeTimer?.cancel();
    unawaited(_subscription?.cancel());
    _socket?.close();
    unawaited(_updates.close());
  }
}
