// EcoSort Azure: camera motion -> five JPEG frames -> Azure classifier -> Flutter.
// Board: AI Thinker ESP32-CAM. Serial Monitor: 115200 baud.
// Ground GPIO0 only for uploading; disconnect it and reset to run.
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include "esp_camera.h"
#include "wifi_config.h"
#include "motion_azure.h"
#include "camera_location.h"
#include "camera_wifi.h"

WebServer server(80);
bool cameraReady = false;
bool serverReady = false;
uint32_t lastStatus = 0;
uint32_t successfulCaptures = 0;
uint32_t failedCaptures = 0;

const char PAGE[] PROGMEM = R"HTML(<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>EcoSort Azure Camera</title></head>
<body style="font-family:Arial;text-align:center;background:#eee">
<h1>EcoSort Azure Camera</h1><p>Motion starts classification automatically. Hold each item clearly in view for five seconds.</p><button onclick="detect()">Classify this item</button><pre id="cloud">Waiting for status</pre><p id="status">Loading camera image...</p>
<img id="camera" alt="Camera image" style="max-width:100%;width:640px">
<p>Images refresh automatically. <a href="/capture">Open a photo</a> | <a href="/wifi/setup">Change Wi-Fi</a></p>
<script>
const img = document.getElementById('camera');
const statusText = document.getElementById('status');
function nextFrame() { img.src = '/capture?t=' + Date.now(); }
img.onload = () => { statusText.textContent = 'Camera image received: ' + new Date().toLocaleTimeString(); setTimeout(nextFrame, 700); };
img.onerror = () => { statusText.textContent = 'Image capture failed. Check Serial Monitor.'; setTimeout(nextFrame, 2000); };
nextFrame();
async function detect() {
  const response = await fetch('/detect', {method:'POST'});
  document.getElementById('cloud').textContent = await response.text();
}
async function cloudStatus() {
  try {
    const status = await (await fetch('/status')).json();
    document.getElementById('cloud').textContent =
      'State: ' + status.state + '\nAnalyzed events: ' + status.completed_events +
      '\nFailed events: ' + status.failed_events + '\nEvent: ' + status.event_id +
      (status.last_analysis ? '\nResult: ' + status.last_analysis.status + ' - ' +
        status.last_analysis.items.map(item => item.name).join(', ') : '');
  } catch (_) { document.getElementById('cloud').textContent = 'Camera connection lost'; }
}
setInterval(cloudStatus, 2000);
</script></body></html>)HTML";

bool initCamera() {
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  // AI-Thinker ESP32-CAM pin mapping.
  config.pin_d0 = 5;
  config.pin_d1 = 18;
  config.pin_d2 = 19;
  config.pin_d3 = 21;
  config.pin_d4 = 36;
  config.pin_d5 = 39;
  config.pin_d6 = 34;
  config.pin_d7 = 35;
  config.pin_xclk = 0;
  config.pin_pclk = 22;
  config.pin_vsync = 25;
  config.pin_href = 23;
  config.pin_sccb_sda = 26;
  config.pin_sccb_scl = 27;
  config.pin_pwdn = 32;
  config.pin_reset = -1;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_VGA;
  config.jpeg_quality = 12;
  config.fb_count = 1;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  const bool hasPsram = psramFound();
  config.fb_location = hasPsram ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;
  if (hasPsram) {
    config.fb_count = 2;
    config.grab_mode = CAMERA_GRAB_LATEST;
  } else {
    Serial.println("EcoSort requires PSRAM for its five-frame classification buffer.");
    return false;
  }
  Serial.printf("PSRAM: %s\n", hasPsram ? "detected" : "not detected; using DRAM");

  const esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("CAMERA INIT FAILED: 0x%x (%s)\n", err, esp_err_to_name(err));
    Serial.println("Check camera ribbon, 5V power, AI-Thinker board, and remove GPIO0-GND.");
    return false;
  }
  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor) Serial.printf("Camera sensor PID: 0x%04x\n", sensor->id.PID);
  return true;
}

void capturePhoto() {
  if (!cameraReady) { server.send(503, "text/plain", "Camera unavailable"); return; }
  camera_fb_t *frame = esp_camera_fb_get();
  if (!frame) {
    ++failedCaptures;
    Serial.println("CAPTURE FAILED: camera returned no frame");
    server.send(503, "text/plain", "Camera capture failed. Check Serial Monitor.");
    return;
  }
  server.sendHeader("Cache-Control", "no-store");
  server.setContentLength(frame->len);
  server.send(200, "image/jpeg", "");
  server.sendContent(reinterpret_cast<const char *>(frame->buf), frame->len);
  esp_camera_fb_return(frame);
  ++successfulCaptures;
}

void printStatus() {
  if (!cameraReady) {
    Serial.println("Camera unavailable: initialization failed. Fix connection and reset.");
  } else if (WiFi.status() != WL_CONNECTED) {
    Serial.printf("Wi-Fi offline, status=%d; recovery hotspot opens after 30 seconds\n", WiFi.status());
  } else {
    Serial.printf("EcoSort camera URL: http://%s/ | captures=%lu failures=%lu\n",
                  WiFi.localIP().toString().c_str(),
                  static_cast<unsigned long>(successfulCaptures),
                  static_cast<unsigned long>(failedCaptures));
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n=== EcoSort Azure waste detection ===");
  setupCameraLocation(server);
  cameraReady = initCamera();

  // Test actual image acquisition before trying Wi-Fi.
  camera_fb_t *frame = cameraReady ? esp_camera_fb_get() : nullptr;
  if (frame) {
    Serial.printf("CAMERA FRAME OK: %ux%u, %u bytes\n",
                  static_cast<unsigned>(frame->width), static_cast<unsigned>(frame->height),
                  static_cast<unsigned>(frame->len));
    ++successfulCaptures;
    esp_camera_fb_return(frame);
  } else {
    ++failedCaptures;
    Serial.println("CAMERA FRAME FAILED: sensor initialized but no image received");
  }

  server.on("/", HTTP_GET, []() { server.send_P(200, "text/html", PAGE); });
  server.on("/capture", HTTP_GET, capturePhoto);
  server.on("/status", HTTP_GET, []() {
    server.sendHeader("Cache-Control", "no-store");
    server.send(200, "application/json", azureStatusJson());
  });
  server.on("/detect", HTTP_POST, []() {
    server.send(cameraReady && !cameraWifiChanging() && triggerAzureCapture() ? 202 : 409, "text/plain",
                "Present the item for five seconds; see status below.");
  });
  setupCameraWifi(server);
  server.begin(); // Also serve recovery while the upstream hotspot is offline.
}

void loop() {
  server.handleClient();
  serviceCameraWifi();
  if (cameraReady && !cameraWifiChanging()) {
    if (!serverReady && WiFi.status() == WL_CONNECTED) {
      serverReady = true;
      setupMotionAzure();
      printStatus();
    }
    if (serverReady) serviceMotionAzure();
  }
  if (Serial.available()) {
    const char command = Serial.read();
    if (command == 'i') {
      printCameraSetupCode(); // USB only; never expose the setup code over HTTP.
      if (WiFi.status() == WL_CONNECTED) Serial.printf("Camera IP: %s\n", WiFi.localIP().toString().c_str());
      else if (WiFi.getMode() == WIFI_AP_STA) Serial.printf("Camera IP: %s (recovery)\n", WiFi.softAPIP().toString().c_str());
      else Serial.println("Camera IP: offline; waiting for hotspot or recovery");
    } else if (command == 'c' && cameraReady && serverReady && !cameraWifiChanging()) {
      triggerAzureCapture();
    }
  }
  if (millis() - lastStatus >= 15000) {
    lastStatus = millis();
    printStatus();
  }
  delay(2);
}
