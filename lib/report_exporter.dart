import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'dashboard_data.dart';

/// Creates a portable workbook from the detections currently visible in the app.
class WasteReportExporter {
  static Future<void> createAndShare({
    required List<WasteEntry> entries,
    required String periodLabel,
  }) async {
    final workbook = Excel.createExcel();
    final summary = workbook['Summary'];
    final detections = workbook['Detections'];
    workbook.delete('Sheet1');

    final generatedAt = DateTime.now();
    _writeSummary(summary, entries, periodLabel, generatedAt);
    _writeDetections(detections, entries);

    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Could not create the Excel report.');

    final directory = await getTemporaryDirectory();
    final stamp = generatedAt
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final report = File('${directory.path}/waste_report_$stamp.xlsx');
    await report.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(report.path)],
      subject: 'EcoSort AI waste report',
      text: 'EcoSort AI waste detections — $periodLabel.',
    );
  }

  static void _writeSummary(
    Sheet sheet,
    List<WasteEntry> entries,
    String period,
    DateTime generatedAt,
  ) {
    final recyclable = entries
        .where((entry) => entry.recyclable)
        .fold<int>(0, (sum, entry) => sum + entry.count);
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.count);
    final organic = entries
        .where((entry) => entry.category.toLowerCase().contains('organic'))
        .fold<int>(0, (sum, entry) => sum + entry.count);

    sheet.appendRow([TextCellValue('EcoSort AI — Waste report')]);
    sheet.appendRow([TextCellValue('Period'), TextCellValue(period)]);
    sheet.appendRow([
      TextCellValue('Generated'),
      TextCellValue(generatedAt.toLocal().toString().split('.').first),
    ]);
    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
    sheet.appendRow([
      TextCellValue('Total items detected'),
      IntCellValue(total),
    ]);
    sheet.appendRow([
      TextCellValue('Recyclable items'),
      IntCellValue(recyclable),
    ]);
    sheet.appendRow([TextCellValue('Organic items'), IntCellValue(organic)]);
    sheet.appendRow([
      TextCellValue('Recycling rate'),
      TextCellValue(
        total == 0 ? '0%' : '${(recyclable / total * 100).round()}%',
      ),
    ]);
    _styleHeader(sheet, 'A1:B1');
    _styleHeader(sheet, 'A5:B5');
    sheet.setColumnWidth(0, 26);
    sheet.setColumnWidth(1, 28);
  }

  static void _writeDetections(Sheet sheet, List<WasteEntry> entries) {
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Time'),
      TextCellValue('Camera ID'),
      TextCellValue('Item'),
      TextCellValue('Category'),
      TextCellValue('Confidence (%)'),
      TextCellValue('Recyclable'),
      TextCellValue('Count'),
      TextCellValue('Latitude'),
      TextCellValue('Longitude'),
      TextCellValue('Location'),
      TextCellValue('Address'),
    ]);
    for (final entry in entries) {
      final capturedAt = DateTime.tryParse(entry.capturedAt ?? '')?.toLocal();
      sheet.appendRow([
        TextCellValue(capturedAt == null ? '—' : _date(capturedAt)),
        TextCellValue(capturedAt == null ? '—' : _time(capturedAt)),
        TextCellValue(entry.deviceId.isEmpty ? 'Smart Bin' : entry.deviceId),
        TextCellValue(entry.name),
        TextCellValue(
          entry.category.isEmpty ? entry.classification : entry.category,
        ),
        DoubleCellValue(double.tryParse(entry.confidence) ?? 0),
        TextCellValue(entry.recyclable ? 'Yes' : 'No'),
        IntCellValue(entry.count),
        entry.latitude == null
            ? TextCellValue('')
            : DoubleCellValue(entry.latitude!),
        entry.longitude == null
            ? TextCellValue('')
            : DoubleCellValue(entry.longitude!),
        TextCellValue(entry.locationLabel),
        TextCellValue(entry.locationAddress),
      ]);
    }
    _styleHeader(sheet, 'A1:L1');
    for (var index = 0; index < 12; index++) {
      sheet.setColumnWidth(index, index == 3 ? 24 : 16);
    }
  }

  static void _styleHeader(Sheet sheet, String range) {
    final style = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#207A43'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );
    final bounds = range.split(':');
    final start = CellIndex.indexByString(bounds.first);
    final end = CellIndex.indexByString(bounds.last);
    for (var row = start.rowIndex; row <= end.rowIndex; row++) {
      for (var col = start.columnIndex; col <= end.columnIndex; col++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
                )
                .cellStyle =
            style;
      }
    }
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
