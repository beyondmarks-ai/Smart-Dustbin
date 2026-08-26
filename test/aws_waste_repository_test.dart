import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_dustbin/aws_waste_repository.dart';

void main() {
  test('maps the AWS response and normalizes the base URL', () async {
    late Uri requestedUri;
    final repository = AwsWasteRepository(
      baseUrl: 'https://example.lambda-url.aws/  ',
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response('''{
            "items": [{
              "event_id": "evt-1",
              "captured_at": "2026-08-26T08:00:00Z",
              "waste_confidence": 0.97,
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
      'https://example.lambda-url.aws/api/waste?limit=100',
    );
    expect(entries, hasLength(1));
    expect(entries.single.name, 'Plastic Bottle');
    expect(entries.single.classification, '91% Recyclable');
    expect(entries.single.confidence, '97');
    expect(entries.single.eventId, 'evt-1');
  });

  test('fails clearly when the AWS endpoint is not configured', () async {
    final repository = AwsWasteRepository(baseUrl: '');

    expect(
      repository.fetchWaste,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('AWS_WASTE_API_BASE'),
        ),
      ),
    );
  });
}
