// Standalone AI-Thinker ESP32-CAM camera test; no cloud or motion code.
// Board: AI Thinker ESP32-CAM. Serial Monitor: 115200 baud.
// Ground GPIO0 only for uploading; disconnect it and reset to run.
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include "esp_camera.h"
#include "wifi_config.h"

WebServer server(80);
bool cameraReady = false;
bool serverReady = false;
uint32_t lastStatus = 0;
uint32_t successfulCaptures = 0;
uint32_t failedCaptures = 0;

const char PAGE[] PROGMEM = R"HTML(<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ESP32 Camera Test</title></head>
<body style="font-family:Arial;text-align:center;background:#eee">
<h1>ESP32-CAM Test</h1><p id="status">Loading camera image...</p>
<img id="camera" alt="Camera image" style="max-width:100%;width:640px">
<p>Images refresh automatically. <a href="/capture">Open a photo</a></p>
<script>
const img = document.getElementById('camera');
const statusText = document.getElementById('status');
function nextFrame() { img.src = '/capture?t=' + Date.now(); }
img.onload = () => { statusText.textContent = 'Camera image received: ' + new Date().toLocaleTimeString(); setTimeout(nextFrame, 700); };
img.onerror = () => { statusText.textContent = 'Image capture failed. Check Serial Monitor.'; setTimeout(nextFrame, 2000); };
nextFrame();
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
  config.frame_size = FRAMESIZE_QVGA;
  config.jpeg_quality = 12;
  config.fb_count = 1;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  const bool hasPsram = psramFound();
  config.fb_location = hasPsram ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;
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
    Serial.printf("Waiting for hotspot '%s'; Wi-Fi status=%d\n", WIFI_SSID, WiFi.status());
  } else {
    Serial.printf("Camera test URL: http://%s/ | captures=%lu failures=%lu\n",
                  WiFi.localIP().toString().c_str(),
                  static_cast<unsigned long>(successfulCaptures),
                  static_cast<unsigned long>(failedCaptures));
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n=== Standalone AI-Thinker camera test ===");
  cameraReady = initCamera();
  if (!cameraReady) return;

  // Test actual image acquisition before trying Wi-Fi.
  camera_fb_t *frame = esp_camera_fb_get();
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
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.printf("Connecting to hotspot: %s\n", WIFI_SSID);
}

void loop() {
  if (cameraReady && WiFi.status() == WL_CONNECTED) {
    if (!serverReady) {
      server.begin();
      serverReady = true;
      printStatus();
    }
    server.handleClient();
  }
  if (millis() - lastStatus >= 15000) {
    lastStatus = millis();
    printStatus();
  }
  delay(2);
}
