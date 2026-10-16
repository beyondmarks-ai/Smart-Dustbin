// Run explicitly: flutter test tool/azure_live_test.dart
// Optional: --dart-define=LIVE_EVENT_ID=<new camera event id>
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_dustbin/aws_waste_repository.dart';

void main() {
  test(
    'live Azure detections map to Flutter entries with downloadable JPEGs',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      final entries = await AwsWasteRepository(client: client).fetchWaste();
      expect(entries, isNotEmpty);
      const eventId = String.fromEnvironment('LIVE_EVENT_ID');
      final candidates = eventId.isEmpty
          ? entries
          : entries.where((entry) => entry.eventId == eventId).toList();
      expect(
        candidates,
        isNotEmpty,
        reason: 'Expected camera event is missing from Azure',
      );
      final entry = candidates.first;
      if (const bool.fromEnvironment('LIVE_REQUIRE_LOCATION')) {
        expect(entry.latitude, isNotNull);
        expect(entry.longitude, isNotNull);
        expect(entry.latitude!.isFinite && entry.latitude!.abs() <= 90, isTrue);
        expect(
          entry.longitude!.isFinite && entry.longitude!.abs() <= 180,
          isTrue,
        );
        expect(entry.locationAccuracy, isNotNull);
        expect(entry.locationAccuracy!, greaterThanOrEqualTo(0));
      }
      expect(entry.imageUrl, isNotNull);
      final photo = await client
          .get(Uri.parse(entry.imageUrl!))
          .timeout(const Duration(seconds: 30));
      expect(photo.statusCode, 200);
      expect(photo.headers['content-type'], contains('image/jpeg'));
      expect(photo.bodyBytes.length, greaterThan(100));
      expect(photo.bodyBytes.take(3).toList(), [0xff, 0xd8, 0xff]);
      // Visible in the test output; no credentials or image bytes are logged.
      // ignore: avoid_print
      print(
        'Azure -> Flutter OK: ${entry.eventId}, ${entry.name}, '
        '${entry.confidence}%, ${entry.verificationStatus}, ${photo.bodyBytes.length} JPEG bytes',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
