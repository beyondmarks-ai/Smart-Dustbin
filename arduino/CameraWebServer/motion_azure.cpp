#include "motion_aws.h"

#include <Arduino.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>

#include "esp_camera.h"
#include "esp_heap_caps.h"
#include "aws_config.h"
#include "img_converters.h"

namespace {

constexpr uint8_t kFrameCount = 5;
constexpr uint32_t kFrameIntervalMs = 1000;
constexpr uint8_t kUploadAttempts = 3;
constexpr uint32_t kUploadConnectTimeoutMs = 15000;
constexpr uint32_t kUploadRequestTimeoutMs = 30000;
constexpr uint32_t kWifiReconnectTimeoutMs = 10000;
constexpr uint32_t kInterFrameUploadDelayMs = 1000;
constexpr uint8_t kMotionGridWidth = 16;
constexpr uint8_t kMotionGridHeight = 12;
constexpr size_t kMotionSampleCount = kMotionGridWidth * kMotionGridHeight;
constexpr uint8_t kBackgroundAdaptationDivisor = 8;

struct CapturedFrame {
  uint8_t *data = nullptr;
  size_t length = 0;
};

CapturedFrame capturedFrames[kFrameCount];
bool captureSequenceActive = false;
uint8_t nextFrameIndex = 0;
uint32_t nextCaptureAtMs = 0;

// Q8 fixed-point background: upper 8 bits are luminance and lower 8 bits
// retain fractional changes for smooth adaptation.
uint16_t motionBackgroundQ8[kMotionSampleCount];
bool motionBaselineReady = false;
uint8_t motionConfirmationCount = 0;
uint32_t nextMotionCheckAtMs = 0;
uint8_t *motionDecodeBuffer = nullptr;
size_t motionDecodeCapacity = 0;

bool awsConfigReady() {
  return strlen(AWS_WASTE_API_URL) > 30 &&
         strlen(AWS_WASTE_API_KEY) > 20 &&
         strncmp(AWS_WASTE_API_KEY, "REPLACE_", 8) != 0;
}

void releaseCapturedFrames() {
  for (uint8_t i = 0; i < kFrameCount; ++i) {
    if (capturedFrames[i].data) {
      heap_caps_free(capturedFrames[i].data);
      capturedFrames[i].data = nullptr;
      capturedFrames[i].length = 0;
    }
  }
}

void resetMotionDetector(uint32_t waitMs) {
  motionBaselineReady = false;
  motionConfirmationCount = 0;
  nextMotionCheckAtMs = millis() + waitMs;
}

bool ensureMotionDecodeCapacity(size_t requiredBytes) {
  if (motionDecodeCapacity >= requiredBytes) return true;

  if (motionDecodeBuffer) {
    heap_caps_free(motionDecodeBuffer);
    motionDecodeBuffer = nullptr;
    motionDecodeCapacity = 0;
  }
  motionDecodeBuffer = static_cast<uint8_t *>(
      heap_caps_malloc(requiredBytes, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  if (!motionDecodeBuffer) return false;
  motionDecodeCapacity = requiredBytes;
  return true;
}

uint8_t rgb565Luminance(const uint8_t *pixel) {
  // jpg2rgb565 outputs big-endian RGB565 by default.
  uint16_t rgb = (static_cast<uint16_t>(pixel[0]) << 8) | pixel[1];
  uint16_t red = ((rgb >> 11) & 0x1F) << 3;
  uint16_t green = ((rgb >> 5) & 0x3F) << 2;
  uint16_t blue = (rgb & 0x1F) << 3;
  return static_cast<uint8_t>((red * 77 + green * 150 + blue * 29) >> 8);
}

bool buildMotionSignature(camera_fb_t *fb, uint8_t *signature) {
  if (fb->format != PIXFORMAT_JPEG || fb->width < 8 || fb->height < 8) {
    Serial.println("Motion detection requires JPEG camera frames");
    return false;
  }

  size_t scaledWidth = fb->width / 8;
  size_t scaledHeight = fb->height / 8;
  size_t decodedBytes = scaledWidth * scaledHeight * 2;
  if (!ensureMotionDecodeCapacity(decodedBytes)) {
    Serial.printf("Motion decoder needs %u bytes of PSRAM\n",
                  static_cast<unsigned>(decodedBytes));
    return false;
  }
  if (!jpg2rgb565(fb->buf, fb->len, motionDecodeBuffer, JPG_SCALE_8X)) {
    Serial.println("Motion JPEG decode failed");
    return false;
  }

  // Average every decoded pixel into a grid cell. The old detector sampled
  // one pixel per cell, which amplified JPEG and sensor noise into false motion.
  for (uint8_t gridY = 0; gridY < kMotionGridHeight; ++gridY) {
    size_t startY = static_cast<size_t>(gridY) * scaledHeight / kMotionGridHeight;
    size_t endY = static_cast<size_t>(gridY + 1) * scaledHeight / kMotionGridHeight;
    if (endY <= startY) endY = startY + 1;
    for (uint8_t gridX = 0; gridX < kMotionGridWidth; ++gridX) {
      size_t startX = static_cast<size_t>(gridX) * scaledWidth / kMotionGridWidth;
      size_t endX = static_cast<size_t>(gridX + 1) * scaledWidth / kMotionGridWidth;
      if (endX <= startX) endX = startX + 1;

      uint32_t luminanceTotal = 0;
      size_t pixelCount = 0;
      for (size_t y = startY; y < endY && y < scaledHeight; ++y) {
        for (size_t x = startX; x < endX && x < scaledWidth; ++x) {
          size_t pixelIndex = (y * scaledWidth + x) * 2;
          luminanceTotal += rgb565Luminance(motionDecodeBuffer + pixelIndex);
          ++pixelCount;
        }
      }
      signature[gridY * kMotionGridWidth + gridX] =
          pixelCount ? static_cast<uint8_t>(luminanceTotal / pixelCount) : 0;
    }
  }
  return true;
}

bool cameraMovementDetected() {
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("Motion check could not get a camera frame");
    return false;
  }

  uint8_t currentSignature[kMotionSampleCount];
  bool signatureReady = buildMotionSignature(fb, currentSignature);
  esp_camera_fb_return(fb);
  if (!signatureReady) return false;

  if (!motionBaselineReady) {
    for (size_t i = 0; i < kMotionSampleCount; ++i) {
      motionBackgroundQ8[i] = static_cast<uint16_t>(currentSignature[i]) << 8;
    }
    motionBaselineReady = true;
    Serial.println("Camera motion background learned");
    return false;
  }

  int32_t backgroundTotal = 0;
  int32_t currentTotal = 0;
  for (size_t i = 0; i < kMotionSampleCount; ++i) {
    backgroundTotal += motionBackgroundQ8[i] >> 8;
    currentTotal += currentSignature[i];
  }
  int16_t globalLightChange =
      static_cast<int16_t>((currentTotal - backgroundTotal) / kMotionSampleCount);

  size_t changedPixels = 0;
  for (size_t i = 0; i < kMotionSampleCount; ++i) {
    int16_t difference = static_cast<int16_t>(currentSignature[i]) -
                         static_cast<int16_t>(motionBackgroundQ8[i] >> 8) -
                         globalLightChange;
    if (abs(difference) >= MOTION_PIXEL_DIFFERENCE) ++changedPixels;
  }

  uint8_t changedPercent = static_cast<uint8_t>(changedPixels * 100 / kMotionSampleCount);
  if (changedPercent >= MOTION_CHANGED_PERCENT) {
    if (motionConfirmationCount < 255) ++motionConfirmationCount;
    Serial.printf("Camera movement: %u%% changed (%u/%u confirmation)\n",
                  changedPercent, motionConfirmationCount, MOTION_CONFIRMATION_FRAMES);
  } else {
    motionConfirmationCount = 0;
    // Adapt only while the scene is stable. Holding the background steady
    // during a candidate makes real movement persist across confirmations.
    for (size_t i = 0; i < kMotionSampleCount; ++i) {
      int32_t targetQ8 = static_cast<int32_t>(currentSignature[i]) << 8;
      int32_t backgroundQ8 = motionBackgroundQ8[i];
      motionBackgroundQ8[i] = static_cast<uint16_t>(
          backgroundQ8 + (targetQ8 - backgroundQ8) / kBackgroundAdaptationDivisor);
    }
  }

  return motionConfirmationCount >= MOTION_CONFIRMATION_FRAMES;
}

bool waitForWifi() {
  if (WiFi.status() == WL_CONNECTED) return true;

  Serial.println("WiFi disconnected; reconnecting before AWS post");
  WiFi.reconnect();
  uint32_t deadline = millis() + kWifiReconnectTimeoutMs;
  while (WiFi.status() != WL_CONNECTED &&
         static_cast<int32_t>(millis() - deadline) < 0) {
    delay(250);
  }
  return WiFi.status() == WL_CONNECTED;
}

bool postEventOnce(const String &eventId, uint8_t attempt) {
  if (!waitForWifi()) {
    Serial.printf("AWS post attempt %u: WiFi reconnection timed out\n", attempt);
    return false;
  }

  WiFiClientSecure client;
  client.setInsecure(); // Function URL uses HTTPS; replace with a pinned CA for production.
  HTTPClient http;
  http.setConnectTimeout(kUploadConnectTimeoutMs);
  http.setTimeout(kUploadRequestTimeoutMs);
  if (!http.begin(client, AWS_WASTE_API_URL)) {
    Serial.printf("AWS post attempt %u: unable to start HTTPS request\n", attempt);
    return false;
  }

  http.addHeader("Content-Type", "application/json");
  http.addHeader("Accept", "application/json");
  http.addHeader("x-api-key", AWS_WASTE_API_KEY);
  String body = String("{\"event_id\":\"") + eventId +
                "\",\"device_id\":\"esp32-camera-01\",\"evidence_summary\":\"Motion event captured by ESP32 camera\",\"items\":[{\"name\":\"Unclassified waste\",\"category\":\"other\",\"material\":\"Unknown\",\"recyclable\":false,\"recycling_confidence\":0,\"reuse_safe\":false}]}";
  int status = http.POST(body);
  String response = status > 0 ? http.getString() : String();
  http.end();

  client.stop();
  if (status != HTTP_CODE_CREATED) {
    if (status < 0) {
      Serial.printf("AWS post attempt %u failed: %s (%d), RSSI %d dBm, heap %u\n",
                    attempt, HTTPClient::errorToString(status).c_str(), status,
                    WiFi.RSSI(), static_cast<unsigned>(ESP.getFreeHeap()));
    } else {
      Serial.printf("AWS post attempt %u failed (HTTP %d): %s\n",
                    attempt, status, response.c_str());
    }
    return false;
  }
  Serial.printf("AWS event %s accepted\n", eventId.c_str());
  return true;
}

bool postEvent(const String &eventId) {
  for (uint8_t attempt = 1; attempt <= kUploadAttempts; ++attempt) {
    if (postEventOnce(eventId, attempt)) return true;
    if (attempt < kUploadAttempts) {
      delay(static_cast<uint32_t>(attempt) * 2000);
    }
  }
  Serial.printf("AWS event post abandoned after %u attempts: %s\n",
                kUploadAttempts, eventId.c_str());
  return false;
}

String createEventId() {
  time_t now = time(nullptr);
  if (now > 1700000000) return String(static_cast<unsigned long>(now));
  return String("boot_") + millis();
}

void uploadCapturedFrames() {
  if (!awsConfigReady()) {
    Serial.println("Upload skipped: fill in aws_config.h first");
    releaseCapturedFrames();
    return;
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Upload skipped: WiFi is disconnected");
    releaseCapturedFrames();
    return;
  }

  String eventId = createEventId();
  postEvent(eventId);
  releaseCapturedFrames();
}

void startMotionCapture() {
  releaseCapturedFrames();
  captureSequenceActive = true;
  nextFrameIndex = 0;
  // Exactly five frames at +1, +2, +3, +4 and +5 seconds.
  nextCaptureAtMs = millis() + kFrameIntervalMs;
  Serial.println("Camera movement confirmed; starting five-frame capture");
}

void captureNextFrame() {
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.printf("Frame %u capture failed; aborting event\n", nextFrameIndex + 1);
    captureSequenceActive = false;
    releaseCapturedFrames();
    return;
  }

  uint8_t *copy = static_cast<uint8_t *>(
      heap_caps_malloc(fb->len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  if (!copy) {
    Serial.printf("Not enough PSRAM for frame %u (%u bytes)\n",
                  nextFrameIndex + 1, static_cast<unsigned>(fb->len));
    esp_camera_fb_return(fb);
    captureSequenceActive = false;
    releaseCapturedFrames();
    return;
  }

  memcpy(copy, fb->buf, fb->len);
  capturedFrames[nextFrameIndex].data = copy;
  capturedFrames[nextFrameIndex].length = fb->len;
  esp_camera_fb_return(fb);
  Serial.printf("Captured frame %u/%u\n", nextFrameIndex + 1, kFrameCount);

  ++nextFrameIndex;
  nextCaptureAtMs += kFrameIntervalMs;
  if (nextFrameIndex == kFrameCount) {
    captureSequenceActive = false;
    uploadCapturedFrames();
    resetMotionDetector(MOTION_COOLDOWN_MS);
  }
}

}  // namespace

void setupMotionAws() {
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  resetMotionDetector(MOTION_WARMUP_MS);
  Serial.printf("Camera motion detection starts in %lu ms\n",
                static_cast<unsigned long>(MOTION_WARMUP_MS));
  if (!awsConfigReady()) {
    Serial.println("AWS is not configured; edit aws_config.h before testing uploads");
  }
}

void serviceMotionAws() {
  if (captureSequenceActive &&
      static_cast<int32_t>(millis() - nextCaptureAtMs) >= 0) {
    captureNextFrame();
  }

  if (!captureSequenceActive &&
      static_cast<int32_t>(millis() - nextMotionCheckAtMs) >= 0) {
    nextMotionCheckAtMs = millis() + MOTION_CHECK_INTERVAL_MS;
    if (cameraMovementDetected()) startMotionCapture();
  }
}
