# Smart Dustbin

A Flutter dashboard that displays AI-verified waste detections, recycling
guidance, material details, and reuse ideas from a smart dustbin backend.

## Features

- Live waste records fetched from an HTTP API
- Fill-level estimate based on a configurable 50-item bin capacity
- Confirmed clear-all action for visible waste records
- Automatic 10-second refresh and scrolling when new waste arrives
- Recycling status, confidence, and contamination notes
- Reuse ideas and safety warnings
- Responsive dashboard for compact Android devices
- Widget and golden-image regression tests

## Requirements

- Flutter stable with Dart 3.10.7 or newer
- Android Studio or another configured Android toolchain
- AWS CLI v2 authenticated to the AWS account you want to use

Check your setup with:

```sh
flutter doctor
```

## Deploy the AWS backend

The backend is serverless and uses an AWS Lambda Function URL, DynamoDB,
Secrets Manager, CloudWatch Logs, and a least-privilege Lambda role. First
authenticate the AWS CLI:

```powershell
aws login
aws sts get-caller-identity
```

Then deploy the stack (the default region is `us-east-1`):

```powershell
.\backend\deploy.ps1
```

The script prints `Flutter API URL`. Use that value when running or building
the app:

```powershell
flutter run --dart-define=AWS_WASTE_API_BASE=https://example.lambda-url.us-east-1.on.aws
```

To add a test record after deployment, use the output secret ARN:

```powershell
.\backend\send_sample.ps1 `
  -ApiBaseUrl https://example.lambda-url.us-east-1.on.aws `
  -SecretArn arn:aws:secretsmanager:us-east-1:123456789012:secret:example
```

The dashboard calls `GET /api/waste?limit=100`. Capture/verification services
write the same JSON record format with `POST /api/waste` and the generated
secret in the `x-api-key` header. Never put that ingestion key in the Flutter
application.

## Run the Flutter app

```sh
flutter pub get
flutter run --dart-define=AWS_WASTE_API_BASE=<Flutter-API-URL>
```

Without `AWS_WASTE_API_BASE`, the app still opens but displays a backend
configuration error instead of attempting to reach the retired Azure service.

## Connect the ESP32 IoT camera

The complete live data path is:

```text
ESP32 camera → HTTPS POST → AWS Lambda Function URL → DynamoDB → Flutter app
```

1. Open `arduino/CameraWebServer` in Arduino IDE and install the ESP32 board
   package.
2. Copy `aws_config.example.h` to `aws_config.h`. The real `aws_config.h` is
   ignored by Git because it contains device credentials.
3. Set `WIFI_SSID` and `WIFI_PASSWORD` for the network used by the ESP32.
4. Retrieve the ingestion secret from AWS Secrets Manager and set
   `AWS_WASTE_API_KEY` to that value. Do not put this key in the Flutter app.
5. Select the correct camera board (the default sketch uses the ESP32-CAM
   pin mapping), choose the device COM port, and upload the sketch.
6. Open Serial Monitor at 115200 baud. After Wi-Fi connects, motion is learned
   for 15 seconds; confirmed motion posts an event to `/api/waste`.
7. Build/install the Flutter app with the same API URL. It refreshes every
   10 seconds and displays new records from DynamoDB.

The ESP32 currently sends a motion event as `Unclassified waste`. To show
plastic, paper, organic, or hazardous classifications, connect an image
verification service that converts the captured event into the documented
`items` JSON format before posting it to AWS.

### Build a release APK

From the repository root:

```powershell
flutter pub get
flutter build apk --release `
  --dart-define=AWS_WASTE_API_BASE=https://5s5v65nhf4kbtqygqktzc5u7rm0fxnmf.lambda-url.us-east-1.on.aws/
```

The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`.

## Quality checks

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/widget_test.dart
flutter test test/dashboard_golden_test.dart
flutter test test/aws_waste_repository_test.dart
python -m unittest backend/test_app.py
```

Golden tests can render differently across operating systems. Update the
reference image only after intentionally reviewing a UI change:

```sh
flutter test test/dashboard_golden_test.dart --update-goldens
```

## Project layout

- `lib/aws_waste_repository.dart` - AWS API client and response mapping
- `lib/home_dashboard.dart` - dashboard UI
- `lib/dashboard_data.dart` - waste-entry model
- `backend/function/app.py` - Lambda GET/POST API
- `backend/template.yaml` - DynamoDB, Lambda, IAM, Function URL, and secret
- `backend/deploy.ps1` - AWS CLI deployment automation
- `test/` - widget fixtures and visual regression tests
- `assets/images/` - bundled waste and dustbin artwork
- `arduino/CameraWebServer/` - ESP32-CAM firmware synchronized with the AWS API

## Configuration and secrets

Do not commit AWS credentials, the ingestion secret, or signing keys. The
Flutter app only receives the public read endpoint. Ingestion credentials stay
in AWS Secrets Manager and are used only by the trusted capture service.

## Azure migration note

The previous Azure endpoint is no longer referenced. This repository never
contained the Azure backend or its database credentials, so historical Azure
records cannot be copied automatically. The AWS table starts empty unless you
still have an export of those records.
