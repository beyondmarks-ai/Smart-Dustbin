# Smart Dustbin

A Flutter dashboard that displays AI-verified waste detections, recycling
guidance, material details, and reuse ideas from a smart dustbin backend.

## Features

- Live waste records fetched from an HTTP API
- Recycling status, confidence, and contamination notes
- Reuse ideas and safety warnings
- Responsive dashboard for compact Android devices
- Widget and golden-image regression tests

## Requirements

- Flutter stable with Dart 3.10.7 or newer
- Android Studio or another configured Android toolchain

Check your setup with:

```sh
flutter doctor
```

## Getting started

```sh
flutter pub get
flutter run
```

By default, the app uses the deployed Smart Dustbin API configured in
`lib/azure_waste_repository.dart`. To use another backend, pass its base URL at
build or run time:

```sh
flutter run \
  --dart-define=AZURE_WASTE_API_BASE=https://your-api.example.com
```

The backend must expose `GET /api/waste?limit=100`.

## Quality checks

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/widget_test.dart
flutter test test/dashboard_golden_test.dart
```

Golden tests can render differently across operating systems. Update the
reference image only after intentionally reviewing a UI change:

```sh
flutter test test/dashboard_golden_test.dart --update-goldens
```

## Project layout

- `lib/azure_waste_repository.dart` - API client and response mapping
- `lib/home_dashboard.dart` - dashboard UI
- `lib/dashboard_data.dart` - waste-entry model
- `test/` - widget fixtures and visual regression tests
- `assets/images/` - bundled waste and dustbin artwork

## Configuration and secrets

Do not commit credentials or signing keys. Local `.env` files, Android
keystores, and generated build/test output are ignored by Git. The current API
integration does not require a client-side secret.
