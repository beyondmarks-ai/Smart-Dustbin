#include "motion_azure.h"
#include "azure_tls.h"
#include "camera_location.h"

#include <Arduino.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>
#include <atomic>
#include "esp_random.h"

#include "esp_camera.h"
#include "esp_heap_caps.h"
#include "azure_config.h"
#include "img_converters.h"

namespace {

constexpr uint8_t kFrameCount = 5;
constexpr uint32_t kFrameIntervalMs = 1000;
constexpr uint8_t kUploadAttempts = 3;
constexpr uint8_t kAnalysisAttempts = 3;
constexpr uint32_t kUploadConnectTimeoutMs = 15000;
constexpr uint32_t kUploadRequestTimeoutMs = 30000;
constexpr uint16_t kAnalysisRequestTimeoutMs = 60000;
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
bool uploadActive = false;
std::atomic<bool> uploadCompleted{false};
String eventIdForUpload;
String lastOutcome = "Waiting for an item";
String workerOutcome;
uint32_t completedEvents = 0;
uint32_t failedEvents = 0;
bool workerSucceeded = false;
const char *phase = "warming_up";
String captureLocation;
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

bool azureConfigReady() {
  return strlen(AZURE_BLOB_CONTAINER_URL) > 30 &&
         strlen(AZURE_BLOB_SAS_TOKEN) > 20 &&
         strlen(AZURE_PROCESS_URL) > 30 &&
         strlen(AZURE_DEVICE_INGEST_KEY) > 20 &&
         strncmp(AZURE_BLOB_SAS_TOKEN, "REPLACE_", 8) != 0 &&
         strncmp(AZURE_DEVICE_INGEST_KEY, "REPLACE_", 8) != 0;
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
    phase = "watching";
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
      // Keep division signed: size_t would turn dimming into a huge positive
      // change, making every grid cell falsely report movement.
      static_cast<int16_t>((currentTotal - backgroundTotal) /
                           static_cast<int32_t>(kMotionSampleCount));

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

  Serial.println("WiFi disconnected; reconnecting before Azure upload");
  WiFi.reconnect();
  uint32_t deadline = millis() + kWifiReconnectTimeoutMs;
  while (WiFi.status() != WL_CONNECTED &&
         static_cast<int32_t>(millis() - deadline) < 0) {
    // Connectivity and the setup web server are serviced by the main loop.
    delay(20);
  }
  return WiFi.status() == WL_CONNECTED;
}

bool uploadFrame(const String &eventId, uint8_t frameNumber, const CapturedFrame &frame) {
  if (!waitForWifi()) return false;
  if (time(nullptr) < 1700000000) {
    Serial.println("Waiting for NTP clock before verified TLS upload");
    for (uint8_t i = 0; i < 30 && time(nullptr) < 1700000000; ++i) delay(500);
    if (time(nullptr) < 1700000000) {
      Serial.println("TLS upload deferred: internet time unavailable");
      return false;
    }
  }
  String url = String(AZURE_BLOB_CONTAINER_URL) + "/motion/" + eventId +
      "/frame_" + frameNumber + ".jpg?" + AZURE_BLOB_SAS_TOKEN;
  WiFiClientSecure client;
  client.setCACert(AZURE_ROOT_CA);
  client.setHandshakeTimeout(15);
  HTTPClient http;
  http.setReuse(false);
  http.setConnectTimeout(kUploadConnectTimeoutMs);
  http.setTimeout(kUploadRequestTimeoutMs);
  if (!http.begin(client, url)) {
    Serial.println("Could not initialize the Azure upload request");
    return false;
  }
  http.addHeader("x-ms-blob-type", "BlockBlob");
  http.addHeader("x-ms-version", "2023-11-03");
  http.addHeader("Content-Type", "image/jpeg");
  Serial.printf("Uploading frame %u/5 (%u bytes), RSSI %d dBm, free heap %u\n",
                frameNumber, static_cast<unsigned>(frame.length), WiFi.RSSI(),
                static_cast<unsigned>(ESP.getFreeHeap()));
  int status = http.sendRequest("PUT", frame.data, frame.length);
  String response = status > 0 ? http.getString() : String();
  http.end();
  client.stop();
  if (status != HTTP_CODE_CREATED) {
    Serial.printf("Azure upload frame %u failed (HTTP %d, %s): %s\n", frameNumber,
                  status, HTTPClient::errorToString(status).c_str(), response.c_str());
    return false;
  }
  Serial.printf("Azure uploaded frame %u/5\n", frameNumber);
  return true;
}

bool requestAnalysis(const String &eventId) {
  if (!waitForWifi()) return false;
  WiFiClientSecure client;
  client.setCACert(AZURE_ROOT_CA);
  client.setHandshakeTimeout(15);
  HTTPClient http;
  http.setReuse(false);
  http.setConnectTimeout(kUploadConnectTimeoutMs);
  // HTTPClient takes uint16_t: 90000 wraps to 24464 milliseconds.
  http.setTimeout(kAnalysisRequestTimeoutMs);
  if (!http.begin(client, AZURE_PROCESS_URL)) return false;
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Accept", "application/json");
  http.addHeader("x-device-key", AZURE_DEVICE_INGEST_KEY);
  String body = String("{\"event_id\":\"") + eventId +
      "\",\"device_id\":\"" + DEVICE_ID + "\"";
  body += captureLocation;
  body += "}";
  Serial.printf("Requesting Azure analysis for event %s\n", eventId.c_str());
  int status = http.POST(body);
  String response = status > 0 ? http.getString() : String();
  http.end();
  client.stop();
  if (status != HTTP_CODE_OK) {
    Serial.printf("Azure analysis request failed (HTTP %d, %s): %s\n", status,
                  HTTPClient::errorToString(status).c_str(), response.c_str());
    return false;
  }
  workerOutcome = response;
  Serial.printf("Azure event %s analyzed: %s\n", eventId.c_str(), response.c_str());
  return true;
}

String createEventId() {
  // Unique across devices and reboots, including when NTP is unavailable.
  char id[96];
  snprintf(id, sizeof(id), "%llu-%012llx-%08lx",
           static_cast<unsigned long long>(time(nullptr) > 1700000000 ? time(nullptr) : 0),
           static_cast<unsigned long long>(ESP.getEfuseMac()),
           static_cast<unsigned long>(esp_random()));
  return String(id);
}

void uploadCapturedFrames() {
  if (!azureConfigReady()) {
    Serial.println("Upload skipped: fill in azure_config.h first");
    releaseCapturedFrames();
    return;
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Upload skipped: WiFi is disconnected");
    releaseCapturedFrames();
    return;
  }

  const String &eventId = eventIdForUpload;
  Serial.printf("Starting Azure upload for event %s\n", eventId.c_str());
  bool uploaded = true;
  for (uint8_t index = 0; index < kFrameCount; ++index) {
    bool sent = false;
    for (uint8_t attempt = 1; attempt <= kUploadAttempts && !sent; ++attempt) {
      sent = uploadFrame(eventId, index + 1, capturedFrames[index]);
      if (!sent && attempt < kUploadAttempts) delay(static_cast<uint32_t>(attempt) * 1500);
    }
    if (!sent) {
      uploaded = false;
      break;
    }
  }
  if (uploaded) {
    bool analyzed = false;
    for (uint8_t attempt = 1; attempt <= kAnalysisAttempts && !analyzed; ++attempt) {
      // Retry the same event: the server reuses an existing analysis, so an
      // interrupted response does not create another history record.
      analyzed = requestAnalysis(eventId);
      if (!analyzed && attempt < kAnalysisAttempts) {
        Serial.printf("Retrying analysis for event %s (%u/%u)\n", eventId.c_str(),
                      attempt + 1, kAnalysisAttempts);
        delay(static_cast<uint32_t>(attempt) * 1500);
      }
    }
    workerSucceeded = analyzed;
    if (!analyzed) {
      Serial.printf("Event %s frames uploaded but analysis failed\n", eventId.c_str());
    }
  } else {
    Serial.printf("Event %s upload incomplete; no analysis requested\n", eventId.c_str());
  }
  releaseCapturedFrames();
}

void uploadWorker(void *) {
  uploadCapturedFrames();
  uploadCompleted.store(true);
  vTaskDelete(nullptr);
}

void startMotionCapture() {
  releaseCapturedFrames();
  captureLocation = cameraLocationJson(); // Snapshot now; later setup changes cannot relabel this event.
  eventIdForUpload = createEventId();
  phase = "capturing";
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
    phase = "capture_failed";
    ++failedEvents;
    resetMotionDetector(MOTION_COOLDOWN_MS);
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
    phase = "capture_failed";
    ++failedEvents;
    resetMotionDetector(MOTION_COOLDOWN_MS);
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
    // Keep the Wi-Fi setup portal responsive while HTTPS waits or retries.
    // The worker owns these frames until it publishes completion.
    uploadActive = true;
    phase = "uploading";
    workerSucceeded = false;
    workerOutcome = "Upload or classification failed; see Serial Monitor";
    uploadCompleted.store(false);
    if (xTaskCreate(uploadWorker, "azure-upload", 12288, nullptr, 1, nullptr) != pdPASS) {
      Serial.println("Could not start upload worker: insufficient memory");
      releaseCapturedFrames();
      uploadActive = false;
      phase = "upload_failed";
      ++failedEvents;
      resetMotionDetector(MOTION_COOLDOWN_MS);
    }
  }
}

}  // namespace

void setupMotionAzure() {
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  resetMotionDetector(MOTION_WARMUP_MS);
  Serial.printf("Camera motion detection starts in %lu ms\n",
                static_cast<unsigned long>(MOTION_WARMUP_MS));
  if (!azureConfigReady()) {
    Serial.println("Azure is not configured; edit azure_config.h before testing uploads");
  }
}

void serviceMotionAzure() {
  if (uploadCompleted.exchange(false)) {
    uploadActive = false;
    lastOutcome = workerOutcome;
    if (workerSucceeded) { ++completedEvents; phase = "analyzed"; }
    else { ++failedEvents; phase = "upload_failed"; }
    resetMotionDetector(MOTION_COOLDOWN_MS);
  }
  if (uploadActive) return;
  if (captureSequenceActive &&
      static_cast<int32_t>(millis() - nextCaptureAtMs) >= 0) {
    captureNextFrame();
  }

  if (WiFi.status() == WL_CONNECTED && !uploadActive && !captureSequenceActive &&
      static_cast<int32_t>(millis() - nextMotionCheckAtMs) >= 0) {
    nextMotionCheckAtMs = millis() + MOTION_CHECK_INTERVAL_MS;
    if (cameraMovementDetected()) startMotionCapture();
  }
}


bool triggerAzureCapture() {
  if (uploadActive || captureSequenceActive || WiFi.status() != WL_CONNECTED) return false;
  startMotionCapture();
  return true;
}

bool azureCaptureBusy() { return uploadActive || captureSequenceActive; }

String azureStatusJson() {
  String result = String("{\"state\":\"") + phase + "\",\"event_id\":\"" +
      eventIdForUpload + "\",\"completed_events\":" + completedEvents +
      ",\"failed_events\":" + failedEvents + ",\"last_analysis\":" +
      (lastOutcome.startsWith("{") ? lastOutcome : String("null")) + "}";
  return result;
}
