import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'camera_location_setup.dart';

class CameraWifiClient {
  CameraWifiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();

  static void validate(String ssid, String password, String code) {
    if (utf8.encode(ssid).isEmpty ||
        utf8.encode(ssid).length > 32 ||
        ssid.runes.any((c) => c < 32)) {
      throw const FormatException(
        'Hotspot name must be 1–32 UTF-8 bytes, with no control characters.',
      );
    }
    if (!RegExp(r'^[\x20-\x7e]{8,63}$').hasMatch(password) &&
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(password)) {
      throw const FormatException(
        'Use an 8–63 character Wi-Fi password (printable ASCII), or 64 hexadecimal digits.',
      );
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(code.trim())) {
      throw const FormatException(
        'Enter the 32-character camera setup code from Serial Monitor.',
      );
    }
  }

  Uri _uri(String address) =>
      CameraLocationClient.locationUri(address).replace(path: '/wifi');

  Future<Map<String, dynamic>> _request(
    http.Request request,
    int expected,
  ) async {
    request.followRedirects = false;
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != expected) {
      throw StateError(switch (response.statusCode) {
        401 => 'Incorrect camera setup code.',
        404 => 'Update the camera firmware to enable Wi-Fi settings.',
        409 =>
          'Camera is capturing, uploading or testing Wi-Fi. Keep the view still, wait, then retry.',
        429 => 'Too many incorrect setup codes. Wait one minute.',
        400 =>
          'Camera rejected the hotspot name or password. Check their lengths.',
        _ => 'Camera request failed (HTTP ${response.statusCode}).',
      });
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid camera response.');
    }
    return body;
  }

  Future<Map<String, dynamic>> read(String address) async {
    final data = await _request(http.Request('GET', _uri(address)), 200);
    if (data['version'] != 1 ||
        data['connected'] is! bool ||
        data['state'] is! String ||
        data['ssid'] is! String ||
        data['saved_ssid'] is! String ||
        data['ip'] is! String ||
        data['recovery_ssid'] is! String) {
      throw const FormatException('Invalid camera Wi-Fi status.');
    }
    return data;
  }

  Future<void> change({
    required String address,
    required String code,
    required String ssid,
    required String password,
  }) async {
    validate(ssid, password, code);
    final request = http.Request('POST', _uri(address))
      ..headers['x-setup-token'] = code.trim()
      ..bodyFields = {'ssid': ssid, 'password': password};
    final data = await _request(request, 202);
    if (data['accepted'] != true || data['state'] != 'testing') {
      throw const FormatException(
        'Camera did not confirm the Wi-Fi trial. Check connection before retrying.',
      );
    }
  }
}

class CameraWifiSetup extends StatefulWidget {
  const CameraWifiSetup({super.key, this.client});
  final CameraWifiClient? client;
  @override
  State<CameraWifiSetup> createState() => _CameraWifiSetupState();
}

class _CameraWifiSetupState extends State<CameraWifiSetup> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  late final _client = widget.client ?? CameraWifiClient();
  bool _busy = false, _showPassword = false;
  String? _message, _target;
  String _recoveryName = 'EcoSort-Setup-xxxx';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _address.text = prefs.getString('camera_location_ip') ?? '';
      _code.text = prefs.getString('camera_location_code') ?? '';
      _target = prefs.getString('camera_wifi_target');
      _ssid.text = _target ?? '';
    });
  }

  @override
  void dispose() {
    for (final c in [_address, _code, _ssid, _password]) {
      c.dispose();
    }
    if (widget.client == null) _client.close();
    super.dispose();
  }

  String _error(Object e) => e is StateError
      ? e.message.toString()
      : e is FormatException
      ? e.message
      : 'Camera unreachable or response timed out. A submitted change may still be running. Check the new hotspot or join the recovery network before retrying.';

  Future<void> _remember() async {
    final prefs = await SharedPreferences.getInstance();
    // Store camera access details, never the user's Wi-Fi password.
    await prefs.setString('camera_location_ip', _address.text.trim());
    await prefs.setString('camera_location_code', _code.text.trim());
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final data = await _client.read(_address.text);
      if (!mounted) return;
      final state = data['state'];
      final connected = data['connected'] == true;
      final confirmed =
          connected &&
          state == 'connected' &&
          (_target == null || data['saved_ssid'] == _target) &&
          data['ssid'] == data['saved_ssid'];
      setState(() {
        _recoveryName = data['recovery_ssid'] as String;
        if (_ssid.text.isEmpty) _ssid.text = data['saved_ssid'] as String;
        _message = state == 'rolled_back' || state == 'save_failed'
            ? 'New Wi-Fi was not saved. Previous credentials were retained. ${connected ? 'Camera is back on ${data['ssid']}.' : 'Use the recovery hotspot to correct the credentials.'}'
            : state == 'testing'
            ? 'Camera is testing the new hotspot. Not saved yet. Enable the target hotspot and check again after 45 seconds.'
            : confirmed
            ? 'Connected to ${data['ssid']} at ${data['ip']}. Saved network confirmed. Wi-Fi connection does not by itself confirm internet/Azure access.'
            : connected
            ? 'Camera is connected to ${data['ssid']}, but the requested network is not confirmed.'
            : 'Camera is offline. Turn on the saved hotspot or configure a new one through recovery.';
      });
      if (confirmed) {
        // Recovery provides the new station address after a successful trial.
        if (_address.text.trim() == '192.168.4.1' && data['ip'] != '') {
          CameraLocationClient.locationUri(data['ip'] as String);
          _address.text = data['ip'] as String;
        }
        await _remember();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('camera_wifi_target');
        _target = null;
      }
    } catch (e) {
      if (mounted) setState(() => _message = _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    try {
      CameraLocationClient.locationUri(_address.text);
      CameraWifiClient.validate(_ssid.text, _password.text, _code.text);
    } catch (e) {
      setState(() => _message = _error(e));
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change camera Wi-Fi?'),
        content: const Text(
          'The camera will disconnect to test the new credentials for up to 45 seconds. Turn on the target 2.4 GHz WPA2 hotspot. If this phone hosts it, you may need to re-enable the hotspot after submitting. Failed trials keep the previous credentials. Keep your camera setup code for recovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Test connection'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _remember();
      _target = _ssid.text;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('camera_wifi_target', _target!);
      if (!mounted) return;
      await _client.change(
        address: _address.text,
        code: _code.text,
        ssid: _ssid.text,
        password: _password.text,
      );
      if (!mounted) return;
      _password.clear();
      setState(
        () => _message =
            'Trial accepted — not yet saved. Enable the new hotspot now, wait up to 45 seconds, then Check connection. If the IP changes, use the hotspot connected-devices list or recovery at 192.168.4.1.',
      );
    } catch (e) {
      if (mounted) setState(() => _message = _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWifiSettings() async {
    try {
      await const MethodChannel(
        'ecosort/settings',
      ).invokeMethod<void>('openWifiSettings');
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Open your phone Settings > Wi-Fi to join the camera recovery hotspot.',
        );
      }
    }
  }

  Future<void> _showRecoveryPassword() async {
    final code = _code.text.trim();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(code)) {
      setState(
        () => _message =
            'Enter your camera setup code first. It is printed in Serial Monitor at startup.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recovery Wi-Fi password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_recoveryName),
            const SizedBox(height: 12),
            SelectableText(code.substring(0, 16)),
            const SizedBox(height: 12),
            const Text(
              'Keep this private. Use it only to join your camera recovery hotspot.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String key, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: Key(key),
      controller: controller,
      enabled: !_busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Camera Wi-Fi')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Change the network the camera joins. This does not change your phone hotspot settings. Use a 2.4 GHz WPA2 hotspot with mobile data for Azure.',
        ),
        const SizedBox(height: 20),
        _field(_address, 'Camera IP', 'wifi_camera_ip'),
        _field(_code, 'Camera setup code', 'wifi_setup_code', secret: true),
        OutlinedButton.icon(
          onPressed: _busy ? null : _check,
          icon: const Icon(Icons.refresh),
          label: const Text('Check connection'),
        ),
        const SizedBox(height: 20),
        _field(_ssid, 'New hotspot name (SSID)', 'wifi_ssid'),
        _field(
          _password,
          'New hotspot password',
          'wifi_password',
          secret: !_showPassword,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show Wi-Fi password'),
          value: _showPassword,
          onChanged: _busy
              ? null
              : (v) => setState(() => _showPassword = v ?? false),
        ),
        FilledButton.icon(
          key: const Key('wifi_save'),
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.wifi),
          label: Text(_busy ? 'Please wait…' : 'Test and save Wi-Fi'),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(_message!, key: const Key('wifi_result')),
          ),
        const Divider(height: 40),
        Text(
          'Cannot reach the old hotspot?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Text(
          'After 30 seconds offline, the camera opens $_recoveryName. Join it in phone Wi-Fi settings. Its password is the first 16 characters of your camera setup code. Choose to stay connected even though this network has no internet. Then use recovery IP below. The browser alternative is http://192.168.4.1/wifi/setup.',
        ),
        const SizedBox(height: 10),
        const Text(
          'If this phone normally hosts the camera hotspot: turn the phone hotspot off to join recovery, submit the credentials, then turn the target hotspot back on within 45 seconds. If you miss the window, reconnect to recovery and retry.',
        ),
        TextButton.icon(
          onPressed: _busy ? null : _openWifiSettings,
          icon: const Icon(Icons.settings),
          label: const Text('Open phone Wi-Fi settings'),
        ),
        TextButton(
          onPressed: _busy ? null : _showRecoveryPassword,
          child: const Text('Show recovery Wi-Fi password'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _address.text = '192.168.4.1';
                  _message =
                      'Join the camera recovery network first, then Check connection.';
                }),
          child: const Text('Use recovery IP: 192.168.4.1'),
        ),
        const Text(
          'The recovery hotspot closes after five minutes of restored connectivity. Wrong credentials do not erase the saved location. Local setup uses HTTP: use only your trusted hotspot.',
        ),
      ],
    ),
  );
}
