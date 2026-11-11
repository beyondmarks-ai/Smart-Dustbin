import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/dashboard_data.dart';
import 'package:smart_dustbin/report_exporter.dart';

void main() {
  test('exports only selected waste and location columns', () {
    const entry = WasteEntry(
      name: 'Plastic Bottle',
      classification: 'Recyclable',
      count: 1,
      accent: Colors.green,
      verificationStatus: 'verified',
      reuseSafe: true,
      reuseIdeas: [
        'Planter: 1. Wash it. 2. Cut the side. 3. Add soil and seeds.',
        'Bird feeder: 1. Wash it. 2. Add two openings. 3. Hang with string.',
        'Drip irrigator: 1. Pierce the cap. 2. Fill it. 3. Place by a plant.',
        'Scoop: 1. Mark a scoop shape. 2. Cut with adult help. 3. Sand edges.',
        'Desk organizer: 1. Cut the top. 2. Cover the edge. 3. Add pens.',
      ],
      latitude: 17.9024006,
      longitude: 77.5148815,
      locationLabel: 'College smart bin',
      locationAddress: 'Bidar, Karnataka',
    );
    final bytes = WasteReportExporter.buildWorkbookBytes(
      entries: const [entry],
      periodLabel: 'All records',
      columns: const {
        WasteReportColumn.wasteName,
        WasteReportColumn.locationName,
        WasteReportColumn.latitude,
        WasteReportColumn.longitude,
        WasteReportColumn.bestFromWaste,
      },
      generatedAt: DateTime(2026, 10, 31, 12),
    );

    final workbook = Excel.decodeBytes(bytes);
    final rows = workbook['Detections'].rows;
    expect(rows.first.map((cell) => cell?.value.toString()).toList(), [
      'Waste item',
      'Location name',
      'Latitude',
      'Longitude',
      'Best from Waste',
    ]);
    expect(rows[1][0]?.value.toString(), 'Plastic Bottle');
    expect(rows[1][1]?.value.toString(), 'College smart bin');
    expect(rows[1][2]?.value, const DoubleCellValue(17.9024006));
    expect(rows[1][3]?.value, const DoubleCellValue(77.5148815));
    expect(rows[1][4]?.value.toString(), contains('Planter:'));

    final wasteRows = workbook['Waste List'].rows;
    expect(wasteRows.first.first?.value.toString(), 'Waste item');
    expect(wasteRows[1][0]?.value.toString(), 'Plastic Bottle');

    final ideaRows = workbook['Top 5 Ideas'].rows;
    expect(ideaRows, hasLength(6));
    expect(ideaRows[1][0]?.value, const IntCellValue(1));
    expect(ideaRows[5][0]?.value, const IntCellValue(5));
    expect(ideaRows[1][1]?.value.toString(), 'Plastic Bottle');
  });

  test('share message includes waste list and top five projects', () {
    const entry = WasteEntry(
      name: 'Plastic Bottle',
      classification: 'Recyclable',
      count: 2,
      accent: Colors.green,
      verificationStatus: 'verified',
      reuseSafe: true,
      reuseIdeas: ['Planter', 'Bird feeder', 'Scoop', 'Organizer', 'Irrigator'],
    );
    final message = WasteReportExporter.shareMessage(
      entries: const [entry],
      periodLabel: 'All records',
    );
    expect(message, contains('Plastic Bottle (x2)'));
    expect(message, contains('Top 5 things to make'));
    expect(message, contains('5. Plastic Bottle: Irrigator'));
  });

  test('requires at least one selected column', () {
    expect(
      () => WasteReportExporter.buildWorkbookBytes(
        entries: const [],
        periodLabel: 'Today',
        columns: const {},
      ),
      throwsArgumentError,
    );
  });
}
