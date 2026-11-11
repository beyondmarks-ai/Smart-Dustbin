#include "camera_location.h"
#include "azure_config.h"
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <math.h>
#include "esp_random.h"

namespace {
Preferences settings;
String savedLocation;
String setupToken;
bool storageReady = false;
uint8_t deniedAttempts = 0;
uint32_t deniedSince = 0;
WiFiUDP discovery;
bool discoveryReady = false;
constexpr uint16_t kDiscoveryPort = 4210;
constexpr uint32_t kPairingWindowMs = 5UL * 60UL * 1000UL;
IPAddress appSubscriber;
uint16_t appSubscriberPort = 0;
uint32_t appSubscribedAt = 0;
String lastPushedStatus;

String quoted(const String &value) {
  String out = "\"";
  for (size_t i = 0; i < value.length(); ++i) {
    const unsigned char c = value[i];
    if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
    else if (c < 32) { char escaped[7]; snprintf(escaped, sizeof(escaped), "\\u%04x", c); out += escaped; }
    else out += static_cast<char>(c);
  }
  return out + "\"";
}

bool number(const String &text, double low, double high, double &value) {
  if (text.isEmpty() || text.length() > 30) return false;
  char *end = nullptr;
  value = strtod(text.c_str(), &end);
  return end != text.c_str() && *end == '\0' && isfinite(value) && value >= low && value <= high;
}

String locationResponse() {
  return String("{\"device_id\":") + quoted(DEVICE_ID) +
      ",\"detection_location\":" + (savedLocation.isEmpty() ? String("null") : savedLocation) + "}";
}
}

void setupCameraLocation(WebServer &server) {
  storageReady = settings.begin("bin-location", false);
  if (storageReady) {
    savedLocation = settings.getString("location", "");
    setupToken = settings.getString("setup-token", "");
    if (setupToken.isEmpty()) {
      char token[33];
      snprintf(token, sizeof(token), "%08lx%08lx%08lx%08lx",
               static_cast<unsigned long>(esp_random()), static_cast<unsigned long>(esp_random()),
               static_cast<unsigned long>(esp_random()), static_cast<unsigned long>(esp_random()));
      setupToken = token;
      if (settings.putString("setup-token", setupToken) != setupToken.length()) storageReady = false;
    }
  }
  if (storageReady) Serial.printf("Camera location setup code: %s\n", setupToken.c_str());
  else Serial.println("Location settings storage unavailable");
  Serial.printf("Saved camera location: %s\n", savedLocation.isEmpty() ? "not configured" : "available");

  const char *headers[] = {"x-setup-token"};
  server.collectHeaders(headers, 1);
  server.on("/location", HTTP_GET, [&server]() {
    server.sendHeader("Cache-Control", "no-store");
    server.send(200, "application/json", locationResponse());
  });
  server.on("/location", HTTP_POST, [&server]() {
    if (!authorizeCameraSetup(server)) return;
    if (server.arg("plain").length() > 2048) { server.send(413, "text/plain", "Request too large"); return; }
    double latitude, longitude, accuracy = 0;
    const String source = server.arg("source");
    const bool gps = source == "phone_gps";
    if (!number(server.arg("latitude"), -90, 90, latitude) ||
        !number(server.arg("longitude"), -180, 180, longitude) ||
        (source != "phone_gps" && source != "manual") ||
        (gps && !number(server.arg("accuracy_m"), 0, 100000, accuracy)) ||
        server.arg("label").length() > 160 || server.arg("address").length() > 300 ||
        server.arg("measured_at").length() > 64) {
      server.send(400, "text/plain", "Invalid location or accuracy"); return;
    }
    String location = String("{\"latitude\":") + String(latitude, 7) +
      ",\"longitude\":" + String(longitude, 7) +
      ",\"label\":" + quoted(server.arg("label")) +
      ",\"address\":" + quoted(server.arg("address")) +
      ",\"source\":\"fixed_bin_coordinate\",\"measurement_source\":" + quoted(source) +
      ",\"measured_at\":" + quoted(server.arg("measured_at")) +
      ",\"accuracy_m\":" + (gps ? String(accuracy, 1) : String("null")) + "}";
    if (settings.putString("location", location) != location.length()) {
      server.send(500, "text/plain", "Could not save location; try again"); return;
    }
    savedLocation = location;
    deniedAttempts = 0;
    Serial.println("Camera location saved for future captures");
    server.send(200, "application/json", locationResponse());
  });
  server.on("/pair", HTTP_POST, [&server]() {
    server.sendHeader("Cache-Control", "no-store");
    if (!storageReady) {
      server.send(503, "text/plain", "Setup storage unavailable");
      return;
    }
    if (millis() > kPairingWindowMs) {
      server.send(403, "text/plain", "Pairing window closed; reset the camera and retry");
      return;
    }
    server.send(200, "application/json",
                String("{\"service\":\"ecosort-camera\",\"version\":1,\"ip\":") +
                    quoted(WiFi.localIP().toString()) + ",\"setup_token\":" +
                    quoted(setupToken) + "}");
    Serial.println("Camera paired with a local app during the startup window");
  });
}

void serviceCameraPairing() {
  if (WiFi.status() != WL_CONNECTED) {
    if (discoveryReady) { discovery.stop(); discoveryReady = false; }
    appSubscriberPort = 0;
    return;
  }
  if (!discoveryReady) {
    discoveryReady = discovery.begin(kDiscoveryPort) == 1;
    if (discoveryReady) Serial.printf("Camera discovery ready on UDP %u\n", kDiscoveryPort);
    return;
  }
  const int size = discovery.parsePacket();
  if (size <= 0 || size > 64) return;
  char request[65] = {};
  const int read = discovery.read(reinterpret_cast<uint8_t *>(request), sizeof(request) - 1);
  if (read <= 0) return;
  const String command(request);
  String response;
  if (command == "ECOSORT_DISCOVER_V1") {
    response = String("{\"service\":\"ecosort-camera\",\"version\":1,\"ip\":") +
        quoted(WiFi.localIP().toString()) + ",\"pairing_available\":" +
        (millis() <= kPairingWindowMs ? "true" : "false") + "}";
  } else if (command == "ECOSORT_SUBSCRIBE_V1") {
    appSubscriber = discovery.remoteIP();
    appSubscriberPort = discovery.remotePort();
    appSubscribedAt = millis();
    lastPushedStatus = "";
    response = "{\"service\":\"ecosort-camera\",\"version\":1,\"subscribed\":true}";
  } else {
    return;
  }
  discovery.beginPacket(discovery.remoteIP(), discovery.remotePort());
  discovery.write(reinterpret_cast<const uint8_t *>(response.c_str()), response.length());
  discovery.endPacket();
}

void pushCameraStatus(const String &status) {
  if (!discoveryReady || appSubscriberPort == 0 || millis() - appSubscribedAt > 30000 ||
      status == lastPushedStatus) return;
  discovery.beginPacket(appSubscriber, appSubscriberPort);
  discovery.write(reinterpret_cast<const uint8_t *>(status.c_str()), status.length());
  if (discovery.endPacket()) lastPushedStatus = status;
}

String cameraLocationJson() {
  return savedLocation.isEmpty() ? String("") : String(",\"detection_location\":") + savedLocation;
}

bool authorizeCameraSetup(WebServer &server) {
  if (!storageReady) { server.send(503, "text/plain", "Setup storage unavailable"); return false; }
  if (millis() - deniedSince >= 60000) { deniedAttempts = 0; deniedSince = millis(); }
  if (deniedAttempts >= 5) { server.send(429, "text/plain", "Too many incorrect codes; wait one minute"); return false; }
  if (server.header("x-setup-token") != setupToken) {
    ++deniedAttempts;
    server.send(401, "text/plain", "Incorrect camera setup code"); return false;
  }
  deniedAttempts = 0;
  return true;
}

String cameraRecoveryPassword() {
  return storageReady && setupToken.length() == 32 ? setupToken.substring(0, 16) : String();
}

void printCameraSetupCode() {
  if (storageReady) Serial.printf("Camera setup code: %s\n", setupToken.c_str());
  else Serial.println("Camera setup code unavailable: storage error");
}
