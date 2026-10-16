# EcoSort Azure camera

This is the active camera-to-Azure firmware for the working AI-Thinker ESP32-CAM (tested with its OV3660 camera). It uses VGA JPEG capture and PSRAM. The separate CameraTestVivo sketch is unchanged.

## Pipeline

1. Camera learns a background for 10 seconds after Wi-Fi connects.
2. Two consecutive changed frames trigger a five-frame capture, spaced one second apart.
3. A background task uploads five JPEGs to the existing private `waste-raw` Azure Blob container using a create/write-only SAS.
4. The device calls the existing `/api/process` Azure Function with its ingest key. Azure AI identifies the item and material, recycling guidance, confidence and best image.
5. Flutter polls `/api/waste` every 10 seconds and fetches the image from `/api/waste/{event_id}/image`.

Motion is a trigger, not a waste classification. Empty scenes and people can trigger capture but should be rejected by the cloud classifier. Verified waste requires at least 80% confidence and evidence in two distinct frames. Ambiguous items appear in the app as **Needs review**. The 15-second cooldown and background relearning reduce repeated events. Keep the camera stationary and present one item clearly for five seconds. Lighting, framing and network latency affect results.

## Flash and run

For a fresh clone, copy `wifi_config.example.h` to `wifi_config.h` and `azure_config.example.h` to `azure_config.h` in this sketch directory. Fill them locally. The matching backend is in `cloud/waste_verifier` at the Flutter workspace root. Both credential files are ignored by Git; never force-add them.

Use `AI Thinker ESP32-CAM`, COM3 (or the detected serial port), 115200 baud.

```powershell
arduino-cli compile --fqbn esp32:esp32:esp32cam arduino/EcoSortAzure
arduino-cli upload -p COM3 --fqbn esp32:esp32:esp32cam --upload-property upload.speed=115200 arduino/EcoSortAzure
```

When using Uno as USB serial, keep Uno RESET grounded. Ground ESP32 GPIO0, reset the ESP32, and upload. Then remove GPIO0 from GND and reset the ESP32 again. Use stable 5V power and 3.3V UART signal levels.

`wifi_config.h` contains the local vivo hotspot credentials. `azure_config.h` contains the existing Azure SAS and device key; both files are excluded from Git. HTTPS validates the server certificate against DigiCert Global Root G2 and requires NTP clock synchronization. The current upload SAS expires 2027-04-02; renew it before expiry. Do not place these credentials in Flutter.

After boot, Serial Monitor reports the camera PID, actual frame capture result and local URL. Opening that URL shows a live preview, event state and the latest cloud result. **Classify this item** starts one manual diagnostic event; otherwise motion starts events automatically. `/status` reports counters and the last analysis. The local controls are intended for a trusted hotspot. No installation coordinates are assumed; configure the physical bin location separately if needed.

Uploads and classification retry three times with bounded waits. The frames remain in RAM while processing; rebooting or a persistent outage can lose that event. Failed events are reported locally and never claimed as successful. App polling is eventually consistent, not instantaneous.

## Validate the Flutter path

```powershell
flutter test tool/azure_live_test.dart --dart-define=LIVE_EVENT_ID=<event-id-from-serial>
flutter build apk --release --dart-define=AZURE_WASTE_API_BASE=https://smart-dustbin-ai-617db5.azurewebsites.net
```

The live check reads a real API event through the Flutter repository and verifies its JPEG photo. No fixture data is uploaded. Android APK: `build/app/outputs/flutter-apk/app-release.apk`.

## Verified installation (2026-10-16)

- Firmware flashed and hash-verified on COM3; OV3660 sensor, PSRAM and 640x480 capture passed.
- Automatic motion events uploaded all five frames with verified HTTPS and were processed by the existing Azure Function.
- Classifier update `2026-10-16-film-aware-v1` deployed successfully. This adds explicit film-versus-bottle visual criteria and high-detail image analysis; poor images can still need review.
- Polythene test event `1792143263-a09af8470968-ecc1309c`: **plastic packaging film**, 80% confidence, evidence in all five frames, verified. The Flutter live test downloaded its 12,506-byte JPEG.
- 17 Flutter tests, Flutter analysis, 3 backend tests and the live Azure-to-Flutter test passed.
- Release APK built and installed on the connected vivo V2031 without clearing app data. History and the actual image/details were checked on the phone. A local screenshot is saved at `build/camera-check/app-result.png`.
- Gradle file watching is disabled in this workspace to avoid a native filesystem-discovery hang during Windows builds.

The existing Azure history is preserved, including earlier diagnostic detections. Older events without coordinates continue to display "Location not recorded"; calibration never changes their historical locations.

## Bin location calibration

The ESP32-CAM has no GPS. In the Android app, open Location (or Settings > Configure camera location), stand beside the bin, and tap **Use phone location**. Allow location access and check the reported accuracy. Enter the local camera IP and the 32-character **Camera location setup code** printed at startup in Serial Monitor, then tap **Save location to camera**.

## Change camera Wi-Fi from the app

Open **Settings > Change camera Wi-Fi**. The app reuses your saved camera IP and setup code. Check the connection, enter the target hotspot name/password and select **Test and save Wi-Fi**. This changes the camera's credentials, not the phone's hotspot configuration. The target must be a 2.4 GHz WPA2 network. SSIDs allow 1–32 UTF-8 bytes; passwords allow 8–63 printable ASCII characters or a 64-digit hexadecimal PSK. Spaces are preserved.

The camera acknowledges the trial before disconnecting, pauses new captures and tests for up to 45 seconds. It atomically stores the new SSID/password pair in NVS only after a connection has remained up for three seconds. Failed trials retain the previous profile and attempt to reconnect to it. Rebooting during a trial also retains the previous profile. Updates while capturing/uploading return a busy response; leave the view still and retry. A Wi-Fi association confirms neither internet access nor Azure availability.

After 30 seconds offline, or during a credential trial, a password-protected **EcoSort-Setup-xxxx** recovery hotspot becomes available. Its password is the first 16 characters of the existing camera setup code; the app's **Show recovery Wi-Fi password** button displays it. Join this network in phone Wi-Fi settings and choose to stay connected without internet. Select **Use recovery IP: 192.168.4.1** in the app, or open `http://192.168.4.1/wifi/setup` in a browser. Both paths require the full setup code to change credentials. Recovery remains available for five minutes after connection is restored.

If the configuring phone also hosts the target hotspot, disable its hotspot to join recovery, submit the credentials, then re-enable the target hotspot within the 45-second trial. If the deadline is missed, use recovery and retry. On a different phone/router, leave the target hotspot enabled throughout. The ESP32's single Wi-Fi radio can briefly interrupt recovery clients while changing channels; rejoin and retry status checks if needed.

Use **Check connection** after the trial. An accepted request is not reported as a successful save. If DHCP assigns a new camera IP, find it in the hotspot's connected-devices list or query status through recovery. The app updates the shared camera IP after a successful recovery status check. Location calibration and Azure credentials are independent and retained.

Local setup is HTTP on the trusted hotspot, protected by the device setup code and failed-code rate limiting. Never expose it to the public internet. Neither the API status nor Serial logs print the hotspot password; Flutter never persists it. The camera stores the working profile in ordinary NVS (not encrypted against physical flash extraction). `wifi_config.h` is only the bootstrap profile when no saved profile exists; editing it does not override a saved profile.

## Location storage and verification

The camera validates and saves coordinates in nonvolatile storage. Each future capture snapshots those coordinates and sends them to Azure, including the phone accuracy and measurement time. The app displays the capture location and map. Recalibrate whenever the bin moves. Manual coordinates are supported but are identified as manual, not GPS measurements.

Use only a trusted hotspot: local configuration uses HTTP and a device-specific setup code, while Azure uploads use HTTPS. Do not share the setup code. Phone and camera must be reachable on the same local network. GPS timeouts, disabled location, denied permission, unavailable camera, and failed save acknowledgements are reported without claiming success.

### Location verification (2026-10-16)

- Location-enabled firmware compiled, uploaded and flash-verified; updated release APK installed on the vivo phone.
- Real phone GPS calibration saved through the app, with reported accuracy 12.7 m. The camera retained it across a physical reset and the app read it back.
- Unauthenticated configuration returned HTTP 401; out-of-range latitude returned HTTP 400. Neither changed the saved calibration.
- Event `1792145243-a09af8470968-8b5bab07` classified the presented bag as **plastic bag**, verified at 90%. Azure retained the measured location and accuracy; the live Flutter test verified its coordinates and 11,915-byte JPEG.
- Actual Android detection details showed the photo, coordinates, accuracy and rendered map. Screenshot: `build/camera-check/app-location-result.png` in the Flutter workspace.
- 25 Flutter tests, Flutter analysis, 3 backend tests and the live location/image test passed. An earlier event failed during the hardware retest; subsequent uploads and analyses succeeded. Covered/dark frames were rejected, not relabelled as waste.

For a new real event with calibrated coordinates:

```powershell
flutter test tool/azure_live_test.dart --dart-define=LIVE_EVENT_ID=<event-id> --dart-define=LIVE_REQUIRE_LOCATION=true
```

## Read camera IP and setup code without Serial Monitor

Double-click `Get-CameraSetup.cmd` in the Flutter workspace, or run:

```powershell
powershell -NoProfile -File tool/Get-CameraSetup.ps1
# If several serial devices are connected:
powershell -NoProfile -File tool/Get-CameraSetup.ps1 -Port COM3
```

The script auto-selects a single USB serial port and requests details with the firmware's USB-only `i` command. No reset is needed with current firmware. Older location-enabled firmware can still be read by pressing ESP32 reset after the script starts. GPIO0 must remain disconnected from GND. Keep Uno RESET grounded when using it as the USB adapter. The script closes the port on success, error or timeout and does not write credentials to disk. A busy serial port requires closing the other serial application first. The setup code cannot be retrieved through unauthenticated HTTP.

Parser checks: `powershell -NoProfile -File tool/Get-CameraSetup.ps1 -SelfTest`.

Verified on COM3 on 2026-10-16: USB-query firmware uploaded and hash-verified. After the initial post-upload startup, the script automatically selected COM3 and read both the IP and setup code in approximately 0.5 seconds without a reset. The live Flutter Wi-Fi/location check also passed after reboot, confirming the saved hotspot and bin coordinates were retained.
