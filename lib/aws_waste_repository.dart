import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'dashboard_data.dart';

abstract interface class WasteRepository {
  Future<List<WasteEntry>> fetchWaste();
}

class AwsWasteRepository implements WasteRepository {
  AwsWasteRepository({
    this.baseUrl = const String.fromEnvironment(
      'AZURE_WASTE_API_BASE',
      defaultValue: 'https://smart-dustbin-ai-617db5.azurewebsites.net',
    ),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<List<WasteEntry>> fetchWaste() async {
    final normalizedBaseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalizedBaseUrl.isEmpty) {
      throw StateError(
        'AZURE_WASTE_API_BASE is not configured. Build the app with '
        '--dart-define=AZURE_WASTE_API_BASE=<function-url>.',
      );
    }

    final uri = Uri.parse('$normalizedBaseUrl/api/waste?limit=100');
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Waste API returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Waste API returned invalid JSON');
    }
    final records = decoded['items'];
    if (records is! List) return const <WasteEntry>[];

    final result = <WasteEntry>[];
    for (final record in records.whereType<Map<String, dynamic>>()) {
      final eventId = record['event_id']?.toString() ?? '';
      final status = record['status']?.toString() ?? 'unknown';
      if (status == 'rejected') continue;
      final needsReview = status == 'review';
      final imagePath = record['image_url']?.toString() ?? '';
      final imageUrl = imagePath.isEmpty
          ? null
          : imagePath.startsWith('http')
          ? imagePath
          : '$normalizedBaseUrl${imagePath.startsWith('/') ? imagePath : '/$imagePath'}';
      final location = record['detection_location'];
      final locationMap = location is Map<String, dynamic>
          ? location
          : const <String, dynamic>{};
      final latitude = _asDouble(locationMap['latitude']);
      final longitude = _asDouble(locationMap['longitude']);
      final items = record['items'];
      if (items is! List || items.isEmpty) continue;

      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item is! Map<String, dynamic>) continue;
        final name = item['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final recyclable = item['recyclable'] == true;
        final category = item['category']?.toString() ?? 'other';
        final material = item['material']?.toString() ?? 'Unknown material';
        final recyclingConfidence = _asPercent(item['recycling_confidence']);
        final tags = <String>{
          _titleCase(category),
          if (material.isNotEmpty) material,
          recyclable ? 'Recyclable' : 'Not recyclable',
        }.toList();
        result.add(
          WasteEntry(
            name: name,
            classification: needsReview
                ? 'Needs review · ${_asPercent(record['waste_confidence'])}% confidence'
                : recyclable
                ? '$recyclingConfidence% Recyclable'
                : 'Not recyclable',
            count: 1,
            imageUrl: imageUrl,
            accent: needsReview
                ? const Color(0xFFB66A00)
                : recyclable
                ? const Color(0xFF2DC65D)
                : const Color(0xFFFF4D4D),
            eventId: eventId,
            verificationStatus: status,
            confidence: _asPercent(record['waste_confidence']),
            material: material,
            category: category,
            recyclable: recyclable,
            recyclingGuidance: item['recycling_guidance']?.toString() ?? '',
            contaminationNotes: item['contamination_notes']?.toString() ?? '',
            reuseSafe: item['reuse_safe'] == true,
            reuseIdeas: _strings(item['best_from_waste_ideas']),
            safetyWarnings: _strings(item['safety_warnings']),
            tags: tags,
            capturedAt: record['captured_at']?.toString(),
            evidenceSummary: record['evidence_summary']?.toString() ?? '',
            latitude: latitude,
            longitude: longitude,
            locationAccuracy: _asDouble(locationMap['accuracy_m']),
            locationLabel: locationMap['label']?.toString() ?? '',
            locationAddress: locationMap['address']?.toString() ?? '',
            deviceId: record['device_id']?.toString() ?? '',
            itemIndex: index,
          ),
        );
      }
    }
    return result;
  }

  static String _asPercent(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return (number <= 1 ? number * 100 : number).round().toString();
  }

  static double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  static List<String> _strings(Object? value) => value is List
      ? value
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList()
      : const <String>[];

  static String _titleCase(String value) => value
      .split(RegExp(r'[_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

@visibleForTesting
class FakeWasteRepository implements WasteRepository {
  const FakeWasteRepository(this.entries);
  final List<WasteEntry> entries;

  @override
  Future<List<WasteEntry>> fetchWaste() async => entries;
}
