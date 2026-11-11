import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'dashboard_data.dart';

class BestFromWasteSuggestion {
  const BestFromWasteSuggestion({
    required this.wasteName,
    required this.idea,
    required this.safety,
  });

  final String wasteName;
  final String idea;
  final String safety;
}

enum WasteReportColumn {
  date('Date', 14),
  time('Time', 11),
  cameraId('Camera ID', 18),
  wasteName('Waste item', 24),
  category('Category', 16),
  material('Material', 18),
  confidence('Confidence (%)', 16),
  recyclable('Recyclable', 14),
  count('Count', 10),
  locationName('Location name', 24),
  address('Address', 32),
  latitude('Latitude', 16),
  longitude('Longitude', 16),
  bestFromWaste('Best from Waste', 34);

  const WasteReportColumn(this.label, this.width);
  final String label;
  final double width;
}

/// Creates a portable workbook from the detections currently visible in the app.
class WasteReportExporter {
  static Future<void> createAndShare({
    required List<WasteEntry> entries,
    required String periodLabel,
    required Set<WasteReportColumn> columns,
  }) async {
    final generatedAt = DateTime.now();
    final bytes = buildWorkbookBytes(
      entries: entries,
      periodLabel: periodLabel,
      columns: columns,
      generatedAt: generatedAt,
    );

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
      text: shareMessage(entries: entries, periodLabel: periodLabel),
    );
  }

  static String shareMessage({
    required List<WasteEntry> entries,
    required String periodLabel,
  }) {
    final lines = <String>['EcoSort AI waste report - $periodLabel', ''];
    if (entries.isEmpty) {
      lines.add('No waste detections found for this period.');
      return lines.join('\n');
    }
    lines.add('Waste detected:');
    for (final entry in entries) {
      lines.add('- ${entry.name} (x${entry.count})');
    }
    final suggestions = topSuggestions(entries);
    if (suggestions.isNotEmpty) {
      lines.addAll(['', 'Top ${suggestions.length} things to make:']);
      for (var index = 0; index < suggestions.length; index++) {
        final suggestion = suggestions[index];
        lines.add('${index + 1}. ${suggestion.wasteName}: ${suggestion.idea}');
      }
    }
    return lines.join('\n');
  }

  static List<BestFromWasteSuggestion> topSuggestions(
    List<WasteEntry> entries,
  ) {
    final suggestions = <BestFromWasteSuggestion>[];
    final seen = <String>{};
    for (final entry in entries) {
      for (final idea in entry.bestFromWasteIdeas) {
        final clean = idea.trim();
        if (clean.isEmpty || !seen.add(clean.toLowerCase())) continue;
        suggestions.add(
          BestFromWasteSuggestion(
            wasteName: entry.name,
            idea: clean,
            safety: entry.safetyWarnings.isEmpty
                ? 'Clean the item first. Use adult help for cutting or heat.'
                : entry.safetyWarnings.join(' '),
          ),
        );
        if (suggestions.length == 5) return suggestions;
      }
    }
    return suggestions;
  }

  static List<int> buildWorkbookBytes({
    required List<WasteEntry> entries,
    required String periodLabel,
    required Set<WasteReportColumn> columns,
    DateTime? generatedAt,
  }) {
    if (columns.isEmpty) {
      throw ArgumentError.value(
        columns,
        'columns',
        'Select at least one column.',
      );
    }
    final workbook = Excel.createExcel();
    final summary = workbook['Summary'];
    final detections = workbook['Detections'];
    final wasteList = workbook['Waste List'];
    final ideas = workbook['Top 5 Ideas'];
    workbook.delete('Sheet1');

    final created = generatedAt ?? DateTime.now();
    _writeSummary(summary, entries, periodLabel, created);
    _writeDetections(detections, entries, columns);
    _writeWasteList(wasteList, entries);
    _writeIdeas(ideas, entries);

    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Could not create the Excel report.');
    return bytes;
  }

  static void _writeWasteList(Sheet sheet, List<WasteEntry> entries) {
    const headers = [
      'Waste item',
      'Count',
      'Category',
      'Material',
      'Status',
      'Confidence (%)',
      'Recyclable',
      'Captured at',
    ];
    sheet.appendRow([for (final header in headers) TextCellValue(header)]);
    for (final entry in entries) {
      sheet.appendRow([
        TextCellValue(entry.name),
        IntCellValue(entry.count),
        TextCellValue(
          entry.category.isEmpty ? entry.classification : entry.category,
        ),
        TextCellValue(entry.material),
        TextCellValue(entry.verificationStatus),
        DoubleCellValue(double.tryParse(entry.confidence) ?? 0),
        TextCellValue(entry.recyclable ? 'Yes' : 'No'),
        TextCellValue(entry.capturedAt ?? ''),
      ]);
    }
    _styleHeaderCells(sheet, headers.length);
    const widths = [25.0, 10.0, 18.0, 18.0, 15.0, 17.0, 13.0, 24.0];
    for (var index = 0; index < widths.length; index++) {
      sheet.setColumnWidth(index, widths[index]);
    }
  }

  static void _writeIdeas(Sheet sheet, List<WasteEntry> entries) {
    const headers = ['Rank', 'Waste item', 'What to make and how', 'Safety'];
    sheet.appendRow([for (final header in headers) TextCellValue(header)]);
    final suggestions = topSuggestions(entries);
    if (suggestions.isEmpty) {
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('No safe reuse ideas are available yet.'),
        TextCellValue('Only verified safe waste is suggested for reuse.'),
      ]);
    } else {
      for (var index = 0; index < suggestions.length; index++) {
        final suggestion = suggestions[index];
        sheet.appendRow([
          IntCellValue(index + 1),
          TextCellValue(suggestion.wasteName),
          TextCellValue(suggestion.idea),
          TextCellValue(suggestion.safety),
        ]);
      }
    }
    _styleHeaderCells(sheet, headers.length);
    sheet.setColumnWidth(0, 9);
    sheet.setColumnWidth(1, 24);
    sheet.setColumnWidth(2, 60);
    sheet.setColumnWidth(3, 48);
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

  static void _writeDetections(
    Sheet sheet,
    List<WasteEntry> entries,
    Set<WasteReportColumn> selected,
  ) {
    final columns = WasteReportColumn.values
        .where(selected.contains)
        .toList(growable: false);
    sheet.appendRow([
      for (final column in columns) TextCellValue(column.label),
    ]);
    for (final entry in entries) {
      final capturedAt = DateTime.tryParse(entry.capturedAt ?? '')?.toLocal();
      sheet.appendRow([
        for (final column in columns) _value(column, entry, capturedAt),
      ]);
    }
    _styleHeaderCells(sheet, columns.length);
    for (var index = 0; index < columns.length; index++) {
      sheet.setColumnWidth(index, columns[index].width);
    }
  }

  static CellValue _value(
    WasteReportColumn column,
    WasteEntry entry,
    DateTime? capturedAt,
  ) => switch (column) {
    WasteReportColumn.date => TextCellValue(
      capturedAt == null ? '—' : _date(capturedAt),
    ),
    WasteReportColumn.time => TextCellValue(
      capturedAt == null ? '—' : _time(capturedAt),
    ),
    WasteReportColumn.cameraId => TextCellValue(
      entry.deviceId.isEmpty ? 'Smart Bin' : entry.deviceId,
    ),
    WasteReportColumn.wasteName => TextCellValue(entry.name),
    WasteReportColumn.category => TextCellValue(
      entry.category.isEmpty ? entry.classification : entry.category,
    ),
    WasteReportColumn.material => TextCellValue(entry.material),
    WasteReportColumn.confidence => DoubleCellValue(
      double.tryParse(entry.confidence) ?? 0,
    ),
    WasteReportColumn.recyclable => TextCellValue(
      entry.recyclable ? 'Yes' : 'No',
    ),
    WasteReportColumn.count => IntCellValue(entry.count),
    WasteReportColumn.locationName => TextCellValue(entry.locationLabel),
    WasteReportColumn.address => TextCellValue(entry.locationAddress),
    WasteReportColumn.latitude =>
      entry.latitude == null
          ? TextCellValue('')
          : DoubleCellValue(entry.latitude!),
    WasteReportColumn.longitude =>
      entry.longitude == null
          ? TextCellValue('')
          : DoubleCellValue(entry.longitude!),
    WasteReportColumn.bestFromWaste => TextCellValue(
      entry.bestFromWasteIdeas.join(' | '),
    ),
  };

  static void _styleHeaderCells(Sheet sheet, int count) {
    final style = _headerStyle();
    for (var col = 0; col < count; col++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
              .cellStyle =
          style;
    }
  }

  static void _styleHeader(Sheet sheet, String range) {
    final style = _headerStyle();
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

  static CellStyle _headerStyle() => CellStyle(
    backgroundColorHex: ExcelColor.fromHexString('#207A43'),
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
  );

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
