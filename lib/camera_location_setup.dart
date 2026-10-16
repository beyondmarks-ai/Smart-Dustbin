import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CameraLocationClient {
  CameraLocationClient({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();

  Future<Map<String, dynamic>?> read(String address) async {
    final response = await _client
        .get(locationUri(address))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError(
        'Cannot read camera location (HTTP ${response.statusCode}).',
      );
    }
    final data = jsonDecode(response.body);
    final location = data is Map ? data['detection_location'] : null;
    if (location == null) return null;
    if (location is! Map<String, dynamic> ||
        location['latitude'] is! num ||
        location['longitude'] is! num) {
      throw const FormatException('Camera returned invalid location data.');
    }
    return location;
  }

  static Uri locationUri(String address) {
    final text = address.trim();
    final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
    final octets = uri?.host.split('.').map(int.tryParse).toList();
    final valid =
        octets != null &&
        octets.length == 4 &&
        octets.every((n) => n != null && n >= 0 && n <= 255);
    final private =
        valid &&
        (octets[0] == 10 ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31));
    if (uri == null ||
        uri.scheme != 'http' ||
        !private ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Enter the camera local IP, for example 10.111.71.234.',
      );
    }
    return uri.replace(path: '/location');
  }

  Future<Map<String, dynamic>> save({
    required String address,
    required String code,
    required double latitude,
    required double longitude,
    required String label,
    required String placeAddress,
    required String source,
    double? accuracy,
    DateTime? measuredAt,
  }) async {
    final uri = locationUri(address);
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      throw const FormatException('Enter valid latitude and longitude.');
    }
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(code.trim())) {
      throw const FormatException(
        'Enter the 32-character camera setup code from Serial Monitor.',
      );
    }
    if (source != 'manual' && source != 'phone_gps') {
      throw const FormatException('Invalid location source.');
    }
    if (source == 'phone_gps' &&
        (accuracy == null ||
            !accuracy.isFinite ||
            accuracy < 0 ||
            measuredAt == null ||
            DateTime.now().difference(measuredAt).abs() >
                const Duration(minutes: 5))) {
      throw const FormatException('Get a fresh phone location before saving.');
    }
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['x-setup-token'] = code.trim()
      ..bodyFields = {
        'latitude': latitude.toStringAsFixed(7),
        'longitude': longitude.toStringAsFixed(7),
        'label': label.trim(),
        'address': placeAddress.trim(),
        'source': source,
        if (accuracy != null) 'accuracy_m': accuracy.toString(),
        'measured_at': measuredAt?.toUtc().toIso8601String() ?? '',
      };
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) {
      throw StateError('Incorrect camera setup code. Check Serial Monitor.');
    }
    if (response.statusCode == 404) {
      throw StateError('This camera needs the location-enabled firmware.');
    }
    if (response.statusCode != 200) {
      throw StateError(
        'Camera could not save location (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    final location = decoded is Map ? decoded['detection_location'] : null;
    if (location is! Map<String, dynamic> ||
        location['latitude'] is! num ||
        location['longitude'] is! num ||
        ((location['latitude'] as num).toDouble() - latitude).abs() >
            0.000001 ||
        ((location['longitude'] as num).toDouble() - longitude).abs() >
            0.000001) {
      throw StateError('Camera did not confirm the saved coordinates.');
    }
    return location;
  }
}

class CameraLocationSetup extends StatefulWidget {
  const CameraLocationSetup({super.key});
  @override
  State<CameraLocationSetup> createState() => _CameraLocationSetupState();
}

class _CameraLocationSetupState extends State<CameraLocationSetup> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _label = TextEditingController(text: 'Smart bin');
  final _placeAddress = TextEditingController();
  final _client = CameraLocationClient();
  Position? _fix;
  bool _busy = false;
  String? _message;
  bool _success = false;
  bool _loadedLocation = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _address.text = prefs.getString('camera_location_ip') ?? '';
    _code.text = prefs.getString('camera_location_code') ?? '';
    _label.text = prefs.getString('camera_location_label') ?? 'Smart bin';
    _placeAddress.text = prefs.getString('camera_location_address') ?? '';
    if (_address.text.isNotEmpty) {
      try {
        final location = await _client.read(_address.text);
        if (!mounted ||
            _fix != null ||
            _latitude.text.isNotEmpty ||
            _longitude.text.isNotEmpty) {
          return;
        }
        if (location != null) {
          setState(() {
            _latitude.text = location['latitude'].toString();
            _longitude.text = location['longitude'].toString();
            _label.text = location['label']?.toString() ?? 'Smart bin';
            _placeAddress.text = location['address']?.toString() ?? '';
            _loadedLocation = true;
            _success = true;
            _message =
                'Camera confirms these saved coordinates. Use phone location to recalibrate after moving the bin.';
          });
        }
      } catch (_) {
        if (mounted && _fix == null) {
          setState(
            () => _message =
                'Camera is unavailable. Check its IP and hotspot before saving.',
          );
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _address,
      _code,
      _latitude,
      _longitude,
      _label,
      _placeAddress,
    ]) {
      controller.dispose();
    }
    _client.close();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _busy = true;
      _success = false;
      _message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(
          'Turn on phone Location using Location settings below.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError('Allow location permission in App settings below.');
      }
      if (permission == LocationPermission.denied) {
        throw StateError(
          'Location permission was denied. Tap Use phone location to try again.',
        );
      }
      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 40),
        ),
      );
      if (!mounted) return;
      if (fix.isMocked) {
        throw StateError(
          'Mock location detected. Use a real location fix for the bin.',
        );
      }
      setState(() {
        _fix = fix;
        _loadedLocation = false;
        _latitude.text = fix.latitude.toStringAsFixed(7);
        _longitude.text = fix.longitude.toStringAsFixed(7);
        _message =
            'Phone location found (accuracy about ${fix.accuracy.round()} m). Save it while standing beside the bin.';
      });
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _success = false;
      _message = null;
    });
    try {
      if (_loadedLocation) {
        throw StateError(
          'These coordinates are already saved. Use phone location to recalibrate.',
        );
      }
      final lat = double.tryParse(_latitude.text.trim());
      final lon = double.tryParse(_longitude.text.trim());
      if (lat == null || lon == null) {
        throw const FormatException(
          'Use phone location or enter measured coordinates first.',
        );
      }
      await _client.save(
        address: _address.text,
        code: _code.text,
        latitude: lat,
        longitude: lon,
        label: _label.text,
        placeAddress: _placeAddress.text,
        source: _fix == null ? 'manual' : 'phone_gps',
        accuracy: _fix?.accuracy,
        measuredAt: _fix?.timestamp,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('camera_location_ip', _address.text.trim());
      await prefs.setString('camera_location_code', _code.text.trim());
      await prefs.setString('camera_location_label', _label.text.trim());
      await prefs.setString(
        'camera_location_address',
        _placeAddress.text.trim(),
      );
      if (mounted) {
        setState(() {
          _success = true;
          _loadedLocation = true;
          _message =
              'Saved on camera. Future detections will include this location, even after a restart. Earlier detections are unchanged.';
        });
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(Object error) {
    if (!mounted) return;
    setState(() {
      _success = false;
      _message = error is StateError
          ? error.message.toString()
          : error is FormatException
          ? error.message
          : error is TimeoutException
          ? 'Request timed out. For GPS, try near a window. For saving, check the camera IP and hotspot connection.'
          : 'Could not connect. Keep the phone and camera on the same hotspot and try again.';
    });
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String key, {
    bool secret = false,
    bool coordinate = false,
    int? maxLength,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      key: Key(key),
      enabled: !_busy,
      obscureText: secret,
      autocorrect: false,
      maxLength: maxLength,
      keyboardType: coordinate
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      onChanged: coordinate
          ? (_) => setState(() {
              _fix = null;
              _loadedLocation = false;
              _success = false;
            })
          : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Stand beside the bin. Read your phone location, then save it to the camera. Recalibrate after moving the bin.',
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('use_phone_location'),
        onPressed: _busy ? null : _locate,
        icon: const Icon(Icons.my_location),
        label: Text(_busy ? 'Please wait…' : 'Use phone location'),
      ),
      Wrap(
        children: [
          TextButton(
            onPressed: () => Geolocator.openLocationSettings(),
            child: const Text('Location settings'),
          ),
          TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            child: const Text('App settings'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _field(_latitude, 'Latitude', 'bin_latitude', coordinate: true),
      _field(_longitude, 'Longitude', 'bin_longitude', coordinate: true),
      _field(_label, 'Bin / place name', 'bin_label', maxLength: 80),
      _field(
        _placeAddress,
        'Address (optional)',
        'bin_address',
        maxLength: 150,
      ),
      _field(_address, 'Camera IP (shown in Serial Monitor)', 'camera_ip'),
      _field(
        _code,
        'Camera setup code (shown in Serial Monitor)',
        'camera_setup_code',
        secret: true,
      ),
      FilledButton.icon(
        key: const Key('save_camera_location'),
        onPressed: _busy ? null : _save,
        icon: const Icon(Icons.save),
        label: const Text('Save location to camera'),
      ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            _message!,
            key: const Key('location_result'),
            style: TextStyle(
              color: _success ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
    ],
  );
}
