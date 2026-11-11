import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dustbin/camera_status_service.dart';

void main() {
  test('parses camera push status and rejects discovery acknowledgements', () {
    final update = CameraStatusUpdate.parse(
      '{"service":"ecosort-camera","version":1,"state":"capturing",'
      '"event_id":"event-1","completed_events":2,"failed_events":1}',
    );
    expect(update.state, 'capturing');
    expect(update.eventId, 'event-1');
    expect(update.completedEvents, 2);
    expect(update.failedEvents, 1);
    expect(
      () => CameraStatusUpdate.parse(
        '{"service":"ecosort-camera","version":1,"subscribed":true}',
      ),
      throwsFormatException,
    );
  });
}
