import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/dashboard_data.dart';
import 'package:smart_dustbin/report_exporter.dart';

void main() {
  test('generate a workbook for visual verification', () async {
    const entries = [
      WasteEntry(
        name: 'Plastic Bottle',
        classification: 'Recyclable',
        category: 'Plastic',
        material: 'PET',
        confidence: '94',
        count: 2,
        accent: Colors.green,
        recyclable: true,
        reuseSafe: true,
        verificationStatus: 'verified',
        capturedAt: '2026-11-10T10:30:00Z',
        reuseIdeas: [
          'Planter: 1. Wash the bottle. 2. Cut a side opening with adult help. 3. Add soil and seeds.',
          'Bird feeder: 1. Wash it. 2. Make two small openings. 3. Add seed and hang it.',
          'Drip irrigator: 1. Pierce the cap. 2. Fill the bottle. 3. Place it upside down by a plant.',
          'Scoop: 1. Draw the scoop shape. 2. Cut with adult help. 3. Smooth and cover the edge.',
          'Desk organizer: 1. Cut off the top. 2. Cover the edge with tape. 3. Add pens and pencils.',
        ],
        safetyWarnings: [
          'Wash before use.',
          'Adult help is required for cutting.',
        ],
      ),
      WasteEntry(
        name: 'Cardboard Box',
        classification: 'Recyclable',
        category: 'Paper',
        material: 'Cardboard',
        confidence: '91',
        count: 1,
        accent: Colors.green,
        recyclable: true,
        verificationStatus: 'verified',
        capturedAt: '2026-11-10T10:35:00Z',
      ),
    ];
    final bytes = WasteReportExporter.buildWorkbookBytes(
      entries: entries,
      periodLabel: 'All records',
      columns: WasteReportColumn.values.toSet(),
      generatedAt: DateTime(2026, 11, 10, 16),
    );
    final output = File('build/report-preview/waste_report_preview.xlsx');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes, flush: true);
    expect(await output.length(), greaterThan(0));
  });
}
