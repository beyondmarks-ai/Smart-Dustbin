#include "camera_wifi.h"
#include "camera_location.h"
#include "motion_azure.h"
#include "wifi_config.h"
#include <WiFi.h>
#include <Preferences.h>

namespace {
// A single NVS blob atomically replaces the known-good pair only after a trial.
struct Profile { char ssid[33]; char password[65]; };
Preferences prefs;
Profile saved = {}, candidate = {};
bool storageReady = false, pending = false, testing = false, apActive = false;
bool wasConnected = false;
uint32_t queuedAt = 0, trialAt = 0, stableAt = 0, offlineAt = 0, apOnlineAt = 0;
String apName;
const char *result = "connecting";

String quoted(const String &s) {
  String out = "\"";
  for (size_t i = 0; i < s.length(); ++i) {
    const unsigned char c = s[i];
    if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
    else if (c < 32) { char escaped[7]; snprintf(escaped, sizeof(escaped), "\\u%04x", c); out += escaped; }
    else out += static_cast<char>(c);
  }
  return out + "\"";
}

bool valid(const String &ssid, const String &password) {
  if (ssid.isEmpty() || ssid.length() > 32 || password.length() < 8 || password.length() > 64) return false;
  for (size_t i = 0; i < ssid.length(); ++i) if (static_cast<unsigned char>(ssid[i]) < 32) return false;
  for (size_t i = 0; i < password.length(); ++i) {
    const unsigned char c = password[i];
    if (c < 32 || c > 126 || (password.length() == 64 && !isxdigit(c))) return false;
  }
  return true;
}

void connectProfile(const Profile &profile) {
  WiFi.disconnect(false, false);
  WiFi.begin(profile.ssid, profile.password);
  stableAt = 0;
  offlineAt = millis();
  wasConnected = false;
}

void startRecovery() {
  if (apActive) return;
  const String password = cameraRecoveryPassword();
  if (password.length() != 16) { Serial.println("Recovery unavailable: no setup code"); return; }
  WiFi.mode(WIFI_AP_STA);
  apActive = WiFi.softAP(apName.c_str(), password.c_str());
  if (apActive) Serial.printf("WiFi recovery: %s, http://192.168.4.1/wifi/setup (password: first 16 setup-code characters)\n", apName.c_str());
}

String statusJson() {
  const bool connected = WiFi.status() == WL_CONNECTED;
  return String("{\"version\":1,\"connected\":") + (connected ? "true" : "false") +
    ",\"state\":" + quoted(pending || testing ? "testing" : result) +
    ",\"ssid\":" + quoted(connected ? WiFi.SSID() : String()) +
    ",\"saved_ssid\":" + quoted(saved.ssid) +
    ",\"ip\":" + quoted(connected ? WiFi.localIP().toString() : String()) +
    ",\"recovery_active\":" + (apActive ? "true" : "false") +
    ",\"recovery_ssid\":" + quoted(apName) + ",\"recovery_ip\":\"192.168.4.1\"}";
}

const char SETUP_PAGE[] PROGMEM = R"HTML(<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>EcoSort Wi-Fi</title></head>
<body style="font:18px sans-serif;max-width:600px;margin:24px auto;padding:16px"><h1>Camera Wi-Fi</h1>
<p>Use a 2.4 GHz WPA2 hotspot. Enter the 32-character setup code printed at startup. A failed trial keeps your previous credentials.</p>
<form id="setup"><p><input id="code" type="password" placeholder="Camera setup code" required autocomplete="off"></p><p><input id="ssid" placeholder="Hotspot name" required></p><p><input id="password" type="password" placeholder="Hotspot password" required autocomplete="new-password"></p><button>Test and save Wi-Fi</button></form>
<pre id="result" style="white-space:pre-wrap"></pre><button onclick="check()">Check connection</button>
<p>If connection is lost, join EcoSort-Setup (password: first 16 characters of your setup code) and open http://192.168.4.1/wifi/setup. On a phone hosting the target hotspot, re-enable that hotspot after submitting.</p>
<script>
const output=document.getElementById('result');
async function check(){try{const r=await fetch('/wifi',{cache:'no-store'});output.textContent=JSON.stringify(await r.json(),null,2);}catch(e){output.textContent='Camera unreachable. Rejoin its network or recovery hotspot, then check again.';}}
document.getElementById('setup').onsubmit=async(e)=>{e.preventDefault();try{const r=await fetch('/wifi',{method:'POST',headers:{'x-setup-token':document.getElementById('code').value,'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({ssid:document.getElementById('ssid').value,password:document.getElementById('password').value})});output.textContent=r.status===202?'Trial accepted, not yet saved. Enable the target hotspot now; wait up to 45 seconds, then check connection.':await r.text();document.getElementById('password').value='';}catch(e){output.textContent='No acknowledgement. Check connection before retrying.';}};check();
</script></body></html>)HTML";
}

void setupCameraWifi(WebServer &server) {
  storageReady = prefs.begin("bin-wifi", false);
  const bool loaded = storageReady && prefs.getBytesLength("profile") == sizeof(Profile) &&
    prefs.getBytes("profile", &saved, sizeof(saved)) == sizeof(saved);
  saved.ssid[32] = 0; saved.password[64] = 0;
  if (!loaded || !valid(saved.ssid, saved.password)) {
    strlcpy(saved.ssid, WIFI_SSID, sizeof(saved.ssid));
    strlcpy(saved.password, WIFI_PASSWORD, sizeof(saved.password));
  }
  char suffix[5]; snprintf(suffix, sizeof(suffix), "%04x", static_cast<unsigned>(ESP.getEfuseMac() & 0xffff));
  apName = String("EcoSort-Setup-") + suffix;
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  connectProfile(saved);
  server.on("/wifi/setup", HTTP_GET, [&server]() { server.sendHeader("Cache-Control", "no-store"); server.send_P(200, "text/html", SETUP_PAGE); });
  server.on("/wifi", HTTP_GET, [&server]() { server.sendHeader("Cache-Control", "no-store"); server.send(200, "application/json", statusJson()); });
  server.on("/wifi", HTTP_POST, [&server]() {
    if (!authorizeCameraSetup(server)) return;
    if (!storageReady) { server.send(503, "text/plain", "WiFi storage unavailable"); return; }
    if (pending || testing || azureCaptureBusy()) { server.send(409, "text/plain", "Camera busy capturing, uploading or testing WiFi; wait and retry"); return; }
    const String ssid = server.arg("ssid"), password = server.arg("password");
    if (!valid(ssid, password)) { server.send(400, "text/plain", "Use a 1-32 byte SSID and an 8-63 printable ASCII password (or 64 hex digits)"); return; }
    candidate = {};
    strlcpy(candidate.ssid, ssid.c_str(), sizeof(candidate.ssid));
    strlcpy(candidate.password, password.c_str(), sizeof(candidate.password));
    pending = true; queuedAt = millis();
    server.sendHeader("Cache-Control", "no-store");
    server.send(202, "application/json", "{\"accepted\":true,\"state\":\"testing\",\"timeout_seconds\":45}");
  });
}

bool cameraWifiChanging() { return pending || testing; }

void serviceCameraWifi() {
  const uint32_t now = millis();
  if (pending && now - queuedAt >= 1000) {
    pending = false; testing = true; trialAt = now; result = "testing";
    startRecovery(); // Recovery is available throughout a credential change.
    connectProfile(candidate);
  }
  const bool connected = WiFi.status() == WL_CONNECTED;
  if (connected) {
    if (!wasConnected) { stableAt = now; apOnlineAt = now; Serial.printf("WiFi connected: http://%s/\n", WiFi.localIP().toString().c_str()); }
    if (testing && WiFi.SSID() == candidate.ssid && now - stableAt >= 3000) {
      testing = false;
      if (prefs.putBytes("profile", &candidate, sizeof(candidate)) == sizeof(candidate)) {
        saved = candidate; result = "connected";
        Serial.println("WiFi credentials tested and saved");
      } else {
        result = "save_failed"; startRecovery(); connectProfile(saved);
        Serial.println("WiFi storage failed; restoring previous network");
      }
      memset(&candidate, 0, sizeof(candidate));
    } else if (!testing && !pending && strcmp(result, "connecting") == 0) result = "connected";
    if (apActive && !testing && !pending && now - apOnlineAt >= 300000) {
      WiFi.softAPdisconnect(true); WiFi.mode(WIFI_STA); apActive = false;
    }
  } else {
    if (wasConnected) offlineAt = now;
    if (!testing && now - offlineAt >= 30000) startRecovery();
  }
  wasConnected = WiFi.status() == WL_CONNECTED;
  if (testing && now - trialAt >= 45000) {
    testing = false; result = "rolled_back";
    memset(&candidate, 0, sizeof(candidate));
    startRecovery(); connectProfile(saved);
    Serial.println("WiFi trial failed; previous credentials retained; recovery available");
  }
}
