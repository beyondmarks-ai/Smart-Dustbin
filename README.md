# Smart-Dustbin

Flutter UI for the single ESP32-CAM Azure waste-detection system. The working Azure camera firmware is now [EcoSortAzure](arduino/EcoSortAzure/README.md). The standalone [CameraTestVivo](arduino/CameraTestVivo/CameraTestVivo.ino) remains available for camera-only diagnosis.

EcoSort AI combines an Android Flutter app, ESP32-CAM firmware and Azure image classification. The active Azure backend is included in [cloud/waste_verifier](cloud/waste_verifier/README.md). The `backend/` and `arduino/CameraWebServer/` directories are retained as legacy AWS implementations, not the active pipeline.

## Fresh clone

```powershell
git clone https://github.com/beyondmarks-ai/Smart-Dustbin.git
cd Smart-Dustbin
flutter pub get
flutter test
```

Validated with Flutter 3.47.5 / Dart 3.13.4, Python 3.11 and ESP32 Arduino core 3.3.11. Install Flutter and the Android SDK for app builds, Arduino CLI for firmware, and Azure CLI for cloud deployment. Copy the firmware `.example.h` files to the corresponding local configuration filenames and fill in your own network/Azure credentials. They are ignored by Git. See the firmware and cloud guides below.

This is a prototype, not a production-secured deployment. See [SECURITY.md](SECURITY.md) before exposing cloud endpoints. No Wi-Fi passwords, ingest secrets, setup codes or SAS tokens are included. Android release builds currently use a development signing key; configure your own release signing before store distribution.

## Features

- Welcome screen on every fresh launch, saved local session and logout.
- Dashboard, analytics and detection history with image thumbnails.
- Detection details with captured item, confidence, time, fixed camera coordinates and Open in Maps.
- Location screen with phone GPS permission handling, accuracy and persistent camera calibration.
- Camera Wi-Fi settings with connection trials, saved credentials and a protected recovery hotspot.
- Feedback saved on device with an offline sentiment estimate and aggregate percentages.
- Light, dark and system themes; cloud connection status; configurable item capacity.
- Fill-level reset preserves detection history and Excel reports.
- EcoSort AI Android launcher name and custom bin/leaf icon.

Account authentication remains local device access. Google sign-in is not connected. The app never presents a local session as verified cloud identity.

## Build

```powershell
flutter pub get
flutter build apk --release --dart-define=AZURE_WASTE_API_BASE=https://smart-dustbin-ai-617db5.azurewebsites.net
```

Release APK: `build/app/outputs/flutter-apk/app-release.apk`.

The historical filename `lib/aws_waste_repository.dart` is retained for compatibility with existing callers. It now reads the Azure Function `GET /api/waste` endpoint using `AZURE_WASTE_API_BASE`. Older AWS deployment folders are not the active pipeline.

The existing Azure service is also the default endpoint for `flutter run`. The app refreshes every 10 seconds without overlapping requests. Each detection includes the captured photo and classification. Uncertain records are labelled **Needs review**, rather than presented as verified results. Connection status refers to Azure access, not a live camera heartbeat.

## Checks

```powershell
flutter analyze
flutter test --no-pub
```

Generate Windows UI previews with `flutter test tool/ui_preview_test.dart --update-goldens --no-pub`. The script uses local fixtures, including an example college location; these are never uploaded to the live service.

Location maps use OpenStreetMap tiles with attribution and the map package's default cache. The map needs internet; saved coordinates remain readable when offline.

To calibrate, stand beside the bin and open **Location > Use phone location**. Enter the camera IP and startup setup code from Serial Monitor, then **Save location to camera**. This saves coordinates on the ESP32 for future events, including after restarts. Recalibrate after moving the bin. Old detections are not retroactively assigned a location. See the [firmware guide](arduino/EcoSortAzure/README.md#bin-location-calibration).

To change the hotspot used by the camera, open **Settings > Change camera Wi-Fi**. Test and save the new credentials, then check the connection. A failed trial keeps the previous network; the protected EcoSort-Setup recovery hotspot also supports setup when the old network is unavailable. See the [Wi-Fi recovery guide](arduino/EcoSortAzure/README.md#change-camera-wi-fi-from-the-app).

To read the camera IP and setup code without Arduino Serial Monitor, double-click **Get-CameraSetup.cmd**, or run `powershell -NoProfile -File tool/Get-CameraSetup.ps1`. Current firmware answers directly over USB; older firmware requires a reset while the script listens. Keep the setup code private.

<!-- beyond-marks-credit:start -->
---
### Built by Beyond Marks AI Academy

Developed by **Rakesh Kumar** at [Beyond Marks AI Academy](https://beyondmarks.ai).
<!-- beyond-marks-credit:end -->
