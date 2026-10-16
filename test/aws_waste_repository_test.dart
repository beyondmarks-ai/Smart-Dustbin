import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_dustbin/aws_waste_repository.dart';

void main() {
  test(
    'keeps review status and resolves photos against the Azure host',
    () async {
      final repository = AwsWasteRepository(
        baseUrl: 'https://example.azurewebsites.net/',
        client: MockClient(
          (_) async => http.Response('''{
        "items": [
          {"event_id":"review-1","status":"review","waste_confidence":0.6,
           "image_url":"/api/waste/review-1/image",
           "items":[{"name":"Bottle","recyclable":true}]},
          {"event_id":"rejected-1","status":"rejected",
           "items":[{"name":"Background object"}]}
        ]
      }''', 200),
        ),
      );
      final entries = await repository.fetchWaste();
      expect(entries, hasLength(1));
      expect(entries.single.needsReview, isTrue);
      expect(entries.single.classification, contains('Needs review'));
      expect(entries.single.classification, contains('60%'));
      expect(
        entries.single.imageUrl,
        'https://example.azurewebsites.net/api/waste/review-1/image',
      );
    },
  );

  test('maps the Azure response and normalizes the base URL', () async {
    late Uri requestedUri;
    final repository = AwsWasteRepository(
      baseUrl: 'https://example.azurewebsites.net/  ',
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response('''{
            "items": [{
              "event_id": "evt-1",
              "captured_at": "2026-08-26T08:00:00Z",
              "waste_confidence": 0.97,
              "device_id": "camera-01",
              "detection_location": {"latitude":17.9104,"longitude":77.5199,"label":"Test college","address":"Test address","accuracy_m":18.5},
              "image_url": "https://images.example/item.jpg",
              "items": [{
                "name": "Plastic Bottle",
                "material": "PET",
                "category": "plastic",
                "recyclable": true,
                "recycling_confidence": 0.91
              }]
            }]
          }''', 200);
      }),
    );

    final entries = await repository.fetchWaste();

    expect(
      requestedUri.toString(),
      'https://example.azurewebsites.net/api/waste?limit=100',
    );
    expect(entries, hasLength(1));
    expect(entries.single.name, 'Plastic Bottle');
    expect(entries.single.classification, '91% Recyclable');
    expect(entries.single.confidence, '97');
    expect(entries.single.eventId, 'evt-1');
    expect(entries.single.latitude, 17.9104);
    expect(entries.single.longitude, 77.5199);
    expect(entries.single.locationLabel, 'Test college');
    expect(entries.single.locationAddress, 'Test address');
    expect(entries.single.locationAccuracy, 18.5);
    expect(entries.single.deviceId, 'camera-01');
  });

  test('fails clearly when the Azure endpoint is not configured', () async {
    final repository = AwsWasteRepository(baseUrl: '');

    expect(
      repository.fetchWaste,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('AZURE_WASTE_API_BASE'),
        ),
      ),
    );
  });
}
