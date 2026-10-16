import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/aws_waste_repository.dart';
import 'package:smart_dustbin/dashboard_data.dart';
import 'package:smart_dustbin/home_dashboard.dart';
import 'test_data.dart';

class _PendingRepository implements WasteRepository {
  final response = Completer<List<WasteEntry>>();
  int requests = 0;
  @override
  Future<List<WasteEntry>> fetchWaste() {
    requests++;
    return response.future;
  }
}

void main() {
  testWidgets('slow Azure requests do not overlap on refresh ticks', (
    tester,
  ) async {
    final repository = _PendingRepository();
    await tester.pumpWidget(
      MaterialApp(home: HomeDashboard(repository: repository)),
    );
    expect(repository.requests, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(repository.requests, 1);
    repository.response.complete([]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(repository.requests, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'late response from a replaced repository cannot overwrite new data',
    (tester) async {
      final oldRepository = _PendingRepository();
      await tester.pumpWidget(
        MaterialApp(home: HomeDashboard(repository: oldRepository)),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeDashboard(repository: FakeWasteRepository([])),
        ),
      );
      await tester.pump();
      oldRepository.response.complete(testWasteEntries);
      await tester.pump();
      final fill = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('fill_level_progress')),
      );
      expect(fill.value, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
