import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'dashboard_data.dart';

abstract interface class WasteRepository {
  Future<List<WasteEntry>> fetchWaste();
}

class AzureWasteRepository implements WasteRepository {
  AzureWasteRepository({
    this.baseUrl = const String.fromEnvironment(
      'AZURE_WASTE_API_BASE',
      defaultValue: 'https://waste-ai-verifier2-617db57026.azurewebsites.net',
    ),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<List<WasteEntry>> fetchWaste() async {
    final uri = Uri.parse('$baseUrl/api/waste?limit=100');
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Azure waste API returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Azure waste API returned invalid JSON');
    }
    final records = decoded['items'];
    if (records is! List) return const <WasteEntry>[];

    final result = <WasteEntry>[];
    for (final record in records.whereType<Map<String, dynamic>>()) {
      final eventId = record['event_id']?.toString() ?? '';
      final imagePath = record['image_url']?.toString() ?? '';
      final imageUrl = imagePath.startsWith('http')
          ? imagePath
          : '$baseUrl${imagePath.startsWith('/') ? imagePath : '/$imagePath'}';
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
            classification: recyclable
                ? '$recyclingConfidence% Recyclable'
                : 'Not recyclable',
            count: 1,
            asset: null,
            imageUrl: imageUrl,
            accent: recyclable
                ? const Color(0xFF2DC65D)
                : const Color(0xFFFF4D4D),
            eventId: eventId,
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
