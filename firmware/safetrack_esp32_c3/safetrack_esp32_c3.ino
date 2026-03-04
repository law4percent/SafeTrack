/*
 * SafeTrack GPS Tracker — ESP32-C3 Super Mini
 * Version: 4.3 (Conflict-free Build)
 *
 * Hardware:
 *   - ESP32-C3 Super Mini
 *   - SIM7600E-H1C (4G LTE + GPS)
 *   - MAX17043 (LiPo fuel gauge, I2C)
 *   - TP4056 (battery charger)
 *   - MT3608 (boost converter 3.7V → 5V)
 *   - LiFePO4 3.7V 2000mAh
 *   - Push button (SOS)
 *
 * Firebase RTDB paths written:
 *   deviceLogs/{userUid}/{deviceCode}/{pushId}
 *     → latitude, longitude, altitude, speed, accuracy,
 *       locationType, timestamp
 *   linkedDevices/{userUid}/devices/{deviceCode}/deviceStatus
 *     → batteryLevel, sos, lastUpdate, lastLocation
 *
 * Firebase path read for auth:
 *   realDevices/{deviceUid}/deviceCode   → match deviceCode
 *   realDevices/{deviceUid}/actionOwnerID → becomes userUid
 */

// ==================== MODEM ====================
#define TINY_GSM_MODEM_SIM7600
#define TINY_GSM_RX_BUFFER 1024
#include <TinyGsmClient.h>
#include <HardwareSerial.h>
#include <ArduinoJson.h>
#include <Wire.h>

// ==================== PINS (ESP32-C3 Super Mini) ====================
#define PIN_RX      20      // SIM7600 TX → ESP32-C3 RX
#define PIN_TX      21      // SIM7600 RX → ESP32-C3 TX
#define RED_PIN      8      // Red LED (onboard or external)
#define GRN_PIN      3      // Green LED
#define SOS_BTN      2      // SOS push button (GPIO2, pulled up)
#define SDA_PIN      6      // MAX17043 SDA
#define SCL_PIN      7      // MAX17043 SCL

// ==================== MAX17043 ====================
#define MAX17043_ADDR  0x36
#define MAX17043_SOC   0x04

// ==================== SERIAL ====================
HardwareSerial SerialAT(1);
#define SerialMon Serial

// ==================== FIREBASE ====================
// ⚠️ Change FIREBASE_URL to match your project region
const String FIREBASE_URL =
    "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app";

// ⚠️ Change DEVICE_CODE to the code printed on this device
const String DEVICE_CODE = "DEVICE1234";

// ==================== APN ====================
const char APN[]  = "http.globe.com.ph";
const char APN_USER[] = "";
const char APN_PASS[] = "";

// ==================== RUNTIME STATE ====================
TinyGsm modem(SerialAT);

// Auth
String userUid     = "";
String deviceUid   = "";
bool   isAuthorized = false;

// GPS
float  gpsLat      = 0.0;
float  gpsLon      = 0.0;
float  gpsAlt      = 0.0;
float  gpsSpeed    = 0.0;   // km/h from TinyGSM
int    gpsHeading  = 0;
bool   gpsValid    = false;
float  lastLat     = 0.0;   // last known good fix
float  lastLon     = 0.0;
float  lastAlt     = 0.0;

// Battery
float  batteryPct  = 0.0;

// SOS
bool          sosActive         = false;
unsigned long sosActivatedAt    = 0;
unsigned long sosPressStart     = 0;
bool          sosHolding        = false;

const unsigned long SOS_HOLD_MS     = 3000;   // hold 3s to activate
const unsigned long SOS_DURATION_MS = 60000;  // auto-cancel after 60s

// Timing
unsigned long lastUpdateMs = 0;
const unsigned long UPDATE_INTERVAL_MS = 30000;  // send every 30s

// ==================== PROTOTYPES ====================
bool  authenticateDevice();
void  connectNetwork();
bool  readGPS();
float readBattery();
void  initMAX17043();
void  sendDeviceStatus();
void  sendLocationLog();
void  handleSOS();
void  blinkRed(int times = 1);
void  blinkGreen(int times = 3);
void  flashSOS();
String httpGet(const String& url);
bool   httpPost(const String& url, const String& payload);

// ==================== SETUP ====================
void setup() {
  SerialMon.begin(115200);
  delay(300);
  SerialMon.println("\n\n=== SafeTrack v4.0 — ESP32-C3 ===");
  SerialMon.println("Device: " + DEVICE_CODE);

  // LEDs
  pinMode(RED_PIN, OUTPUT);
  pinMode(GRN_PIN, OUTPUT);
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GRN_PIN, LOW);

  // SOS button — internal pull-up
  pinMode(SOS_BTN, INPUT_PULLUP);

  // I2C for MAX17043
  Wire.begin(SDA_PIN, SCL_PIN);
  initMAX17043();
  batteryPct = readBattery();
  SerialMon.printf("Battery: %.1f%%\n", batteryPct);

  // Start modem UART
  SerialAT.begin(115200, SERIAL_8N1, PIN_RX, PIN_TX);
  delay(300);

  SerialMon.println("Starting modem...");
  if (!modem.restart()) {
    SerialMon.println("⚠️  Modem restart failed, continuing...");
  }
  SerialMon.println("Modem: " + modem.getModemInfo());

  // Enable GPS
  modem.enableGPS();
  SerialMon.println("GPS enabled.");

  // Connect network
  connectNetwork();

  // Authenticate against Firebase realDevices
  SerialMon.println("\n🔐 Authenticating...");
  if (authenticateDevice()) {
    SerialMon.println("✅ Authorized");
    SerialMon.println("   userUid:   " + userUid);
    SerialMon.println("   deviceUid: " + deviceUid);
    isAuthorized = true;
    blinkGreen(3);
  } else {
    SerialMon.println("❌ Not authorized — halting");
    while (true) { blinkRed(1); delay(1000); }
  }

  SerialMon.println("\n✅ Ready. Hold SOS button 3s to trigger.\n");
  lastUpdateMs = millis();
}

// ==================== LOOP ====================
void loop() {
  if (!isAuthorized) { blinkRed(1); delay(1000); return; }

  // ── SOS button check (every loop iteration, non-blocking) ──
  handleSOS();

  // ── Periodic GPS + Firebase update ────────────────────────
  unsigned long now = millis();
  if (now - lastUpdateMs >= UPDATE_INTERVAL_MS) {
    lastUpdateMs = now;

    batteryPct = readBattery();

    // Reconnect GPRS if dropped
    if (!modem.isGprsConnected()) {
      SerialMon.println("⚠️  GPRS dropped — reconnecting...");
      connectNetwork();
    }

    SerialMon.println("\n──────────────────────────────────");
    SerialMon.println("  UPDATE CYCLE");
    SerialMon.println("──────────────────────────────────");

    gpsValid = readGPS();

    SerialMon.printf("  Battery : %.1f%%\n", batteryPct);
    SerialMon.printf("  GPS     : %s\n", gpsValid ? "VALID" : "NO FIX");
    SerialMon.printf("  SOS     : %s\n", sosActive ? "🚨 ACTIVE" : "off");

    // Write to both Firebase paths
    sendLocationLog();    // → deviceLogs (push entry, history)
    sendDeviceStatus();   // → deviceStatus (latest snapshot)

    blinkGreen(2);
    SerialMon.println("  Next update in 30s\n");
  }

  delay(10);
}

// ==================== SOS HANDLER ====================
void handleSOS() {
  unsigned long now = millis();

  // Auto-cancel after SOS_DURATION_MS
  if (sosActive && (now - sosActivatedAt >= SOS_DURATION_MS)) {
    sosActive = false;
    digitalWrite(RED_PIN, LOW);
    SerialMon.println("🔔 SOS auto-cancelled (60s elapsed)");
  }

  int btnState = digitalRead(SOS_BTN);

  if (btnState == LOW) {
    // Button is held down
    if (!sosHolding) {
      sosHolding   = true;
      sosPressStart = now;
      SerialMon.println("🔴 SOS button held — keep holding 3s...");
    }
    // Activate once hold threshold reached (and not already active)
    if (!sosActive && (now - sosPressStart >= SOS_HOLD_MS)) {
      sosActive       = true;
      sosActivatedAt  = now;
      SerialMon.println("🚨🚨🚨 SOS ACTIVATED 🚨🚨🚨");
      flashSOS();
      // Immediate Firebase push with SOS flag
      sendLocationLog();
      sendDeviceStatus();
    }
  } else {
    // Button released
    if (sosHolding) {
      unsigned long held = now - sosPressStart;
      if (!sosActive) {
        SerialMon.printf("  Released after %.1fs (need 3s)\n",
                         held / 1000.0);
      }
      sosHolding = false;
    }
  }

  // Blink RED while SOS active
  if (sosActive) {
    digitalWrite(RED_PIN, (now / 500) % 2 == 0 ? HIGH : LOW);
  }
}

// ==================== GPS ====================
bool readGPS() {
  SerialMon.println("  Reading GPS...");
  float lat, lon, alt, spd;
  int   hdg;

  // TinyGSM wraps AT+CGPSINFO for SIM7600
  if (modem.getGPS(&lat, &lon, &alt, &spd, &hdg)) {
    if (lat != 0.0 && lon != 0.0) {
      gpsLat   = lat;
      gpsLon   = lon;
      gpsAlt   = alt;
      gpsSpeed = spd;
      gpsHeading = hdg;
      lastLat  = lat;
      lastLon  = lon;
      lastAlt  = alt;
      SerialMon.printf("  ✅ Lat %.6f  Lon %.6f  Alt %.1fm  Spd %.1fkph\n",
                       lat, lon, alt, spd);
      return true;
    }
  }
  SerialMon.println("  ⚠️  No GPS fix — using cached location");
  return false;
}

// ==================== BATTERY ====================
void initMAX17043() {
  // Quick-start command
  Wire.beginTransmission(MAX17043_ADDR);
  Wire.write(0xFE);
  Wire.write(0x54);
  Wire.write(0x00);
  Wire.endTransmission();
  delay(500);
  SerialMon.println("MAX17043 initialized.");
}

float readBattery() {
  Wire.beginTransmission(MAX17043_ADDR);
  Wire.write(MAX17043_SOC);
  Wire.endTransmission(false);
  Wire.requestFrom(MAX17043_ADDR, 2);
  if (Wire.available() >= 2) {
    uint8_t msb = Wire.read();
    uint8_t lsb = Wire.read();
    float pct = msb + (lsb / 256.0);
    return constrain(pct, 0.0, 100.0);
  }
  return 0.0;
}

// ==================== FIREBASE: deviceLogs (POST = push) ====================
//
// POST to .../deviceLogs/{userUid}/{deviceCode}.json
// Firebase generates a unique push ID → creates history entries
// Flutter app reads these as individual children ordered by timestamp
//
// Payload matches what Flutter's _subscribeToLocation() expects:
//   latitude, longitude, altitude, speed, accuracy,
//   locationType, timestamp (Unix ms)
//
void sendLocationLog() {
  // Use last valid fix if GPS unavailable this cycle
  float lat = gpsValid ? gpsLat : lastLat;
  float lon = gpsValid ? gpsLon : lastLon;
  float alt = gpsValid ? gpsAlt : lastAlt;
  float spd = gpsValid ? gpsSpeed : 0.0;

  // Build Unix timestamp from GPS time or millis fallback
  // SIM7600 AT+CCLK? returns network time — use modem.getGSMDateTime
  // For simplicity we use a server-side timestamp via .sv
  // NOTE: the Flutter app reads 'timestamp' as a Unix ms integer,
  // so we use Firebase server value here.
  // ✅ FIX: Dashboard reads logData['lastUpdate'] for online status,
  //         so we write BOTH 'timestamp' (for live_location/gemini)
  //         AND 'lastUpdate' (for dashboard) with the same server value.
  // ✅ FIX: Dashboard reads logData['batteryLevel'] first before falling
  //         back to deviceStatus, so include it here too.
  StaticJsonDocument<512> doc;
  doc["latitude"]     = lat;
  doc["longitude"]    = lon;
  doc["altitude"]     = round(alt * 10) / 10.0;
  doc["speed"]        = round(spd * 10) / 10.0;  // km/h
  doc["accuracy"]     = gpsValid ? 5.0 : 50.0;   // estimated meters
  doc["locationType"] = gpsValid ? "gps" : "cached";
  doc["sos"]          = sosActive;
  doc["batteryLevel"] = (int)round(batteryPct);   // dashboard reads this from logs

  // Both 'timestamp' and 'lastUpdate' point to the same server value.
  // 'timestamp'  → read by live_location_screen and gemini_service
  // 'lastUpdate' → read by dashboard_screen for online/offline detection
  JsonObject ts = doc.createNestedObject("timestamp");
  ts[".sv"] = "timestamp";
  JsonObject lu = doc.createNestedObject("lastUpdate");
  lu[".sv"] = "timestamp";

  String payload;
  serializeJson(doc, payload);

  // POST → Firebase generates push ID
  String url = FIREBASE_URL + "/deviceLogs/" + userUid + "/"
               + DEVICE_CODE + ".json";

  SerialMon.println("  📤 Sending deviceLogs...");
  SerialMon.println("     " + payload);

  if (httpPost(url, payload)) {
    SerialMon.println("  ✅ deviceLogs push OK");
  } else {
    SerialMon.println("  ❌ deviceLogs push FAILED");
    blinkRed(3);
  }
}

// ==================== FIREBASE: deviceStatus (PUT = overwrite) ==============
//
// PUT to .../deviceStatus/{deviceCode}.json
// Always overwrites — this is the "latest snapshot" node.
// Flutter dashboard and AI assistant read battery + SOS from here.
//
void sendDeviceStatus() {
  // ✅ Path matches real RTDB structure:
  //    linkedDevices/{userUid}/devices/{deviceCode}/deviceStatus
  // ✅ Field names match RTDB schema:
  //    batteryLevel (not battery), sos (not isSOS)
  // ✅ lastLocation updated with current GPS fix
  StaticJsonDocument<256> doc;
  doc["batteryLevel"] = (int)round(batteryPct);
  doc["sos"]          = sosActive;
  doc["lastUpdate"]   = (unsigned long)(millis()); // overwritten by server .sv below

  // lastLocation — mirrors the nested object already in RTDB
  JsonObject loc = doc.createNestedObject("lastLocation");
  loc["latitude"]  = gpsValid ? gpsLat  : lastLat;
  loc["longitude"] = gpsValid ? gpsLon  : lastLon;
  loc["altitude"]  = gpsValid ? gpsAlt  : lastAlt;

  // Server-side timestamp for lastUpdate
  // Firebase resolves {".sv":"timestamp"} to Unix ms on write
  doc.remove("lastUpdate");
  JsonObject ts = doc.createNestedObject("lastUpdate");
  ts[".sv"] = "timestamp";

  String payload;
  serializeJson(doc, payload);

  // PATCH via POST + x-http-method-override
  // Path: linkedDevices/{userUid}/devices/{deviceCode}/deviceStatus
  String url = FIREBASE_URL
               + "/linkedDevices/" + userUid
               + "/devices/" + DEVICE_CODE
               + "/deviceStatus.json";

  SerialMon.println("  📤 Sending deviceStatus → linkedDevices path...");
  SerialMon.println("     " + payload);
  _httpPostOverwrite(url, payload);
}

// ==================== NETWORK ====================
void connectNetwork() {
  if (modem.isGprsConnected()) {
    SerialMon.println("GPRS already connected.");
    return;
  }
  SerialMon.println("Waiting for network registration...");
  if (!modem.waitForNetwork(30000)) {
    SerialMon.println("❌ Network registration timeout");
    return;
  }
  SerialMon.print("Connecting GPRS (APN: ");
  SerialMon.print(APN);
  SerialMon.println(")...");
  if (!modem.gprsConnect(APN, APN_USER, APN_PASS)) {
    SerialMon.println("❌ GPRS connect failed");
  } else {
    SerialMon.println("✅ GPRS connected — IP: " + modem.getLocalIP());
  }
}

// ==================== HTTP HELPERS ====================
//
// httpPost  — POST request (Firebase push, generates push ID)
// _httpPut  — PUT request  (Firebase overwrite, deviceStatus)
//
// Both use raw SIM7600 AT+HTTP commands for full control.
// AT+HTTPACTION=0 → GET
// AT+HTTPACTION=1 → POST  (Firebase: creates push-ID child)
// AT+HTTPACTION=2 → HEAD
// AT+HTTPACTION=3 → DELETE
//
// ⚠️  SIM7600 has no native PUT or PATCH AT command.
//   For deviceLogs  : plain POST → Firebase generates push ID (history)
//   For deviceStatus: POST + ?x-http-method-override=PATCH in URL
//                     → Firebase treats as PATCH (flat overwrite)
//
String _sendAT(const String& cmd, unsigned long timeoutMs = 2000) {
  SerialAT.println(cmd);
  String resp;
  unsigned long deadline = millis() + timeoutMs;
  while (millis() < deadline) {
    while (SerialAT.available()) resp += (char)SerialAT.read();
    if (resp.indexOf("OK") != -1 || resp.indexOf("ERROR") != -1) break;
  }
  return resp;
}

bool _httpRequest(const String& url, const String& payload, int action) {
  // action: 0=GET, 1=POST
  _sendAT("AT+HTTPTERM", 500);
  delay(200);
  if (_sendAT("AT+HTTPINIT", 2000).indexOf("OK") == -1) {
    SerialMon.println("  HTTP INIT failed");
    return false;
  }
  _sendAT("AT+HTTPPARA=\"CID\",1", 500);
  _sendAT("AT+HTTPPARA=\"URL\",\"" + url + "\"", 1000);

  if (action == 1) {
    // POST — send payload
    _sendAT("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 500);
    SerialAT.println("AT+HTTPDATA=" + String(payload.length()) + ",10000");
    delay(300);
    // Wait for DOWNLOAD prompt
    String r;
    unsigned long dl = millis() + 3000;
    while (millis() < dl) {
      while (SerialAT.available()) r += (char)SerialAT.read();
      if (r.indexOf("DOWNLOAD") != -1) break;
    }
    if (r.indexOf("DOWNLOAD") == -1) {
      SerialMon.println("  HTTPDATA prompt timeout");
      _sendAT("AT+HTTPTERM", 500);
      return false;
    }
    SerialAT.print(payload);
    delay(500);
  }

  // Execute request
  SerialAT.println("AT+HTTPACTION=" + String(action));
  String result;
  unsigned long deadline = millis() + 20000;
  while (millis() < deadline) {
    while (SerialAT.available()) result += (char)SerialAT.read();
    if (result.indexOf("+HTTPACTION:") != -1 ||
        result.indexOf("+HTTPACTION: ") != -1) break;
  }

  _sendAT("AT+HTTPTERM", 500);

  bool ok = (result.indexOf(",200,") != -1 ||
             result.indexOf(",201,") != -1);
  if (!ok) {
    SerialMon.println("  HTTP response: " + result);
  }
  return ok;
}

bool httpPost(const String& url, const String& payload) {
  return _httpRequest(url, payload, 1);
}

// PUT via POST + Firebase method override header workaround
// SIM7600 AT commands don't support PUT natively.
// Firebase REST API accepts POST to a node path ending in .json
// and treats it as a push (new child). For overwrite (PUT behaviour),
// we POST directly to the exact node path — Firebase will merge,
// effectively replacing the fields we send.
void _httpPostOverwrite(const String& url, const String& payload) {
  // Firebase REST API does not support PUT via AT+HTTPACTION.
  // Appending ?x-http-method-override=PATCH tells Firebase to treat
  // this POST as a PATCH — merging/overwriting fields at the exact
  // node path rather than creating a new push-ID child.
  // This is the correct way to keep deviceStatus as a flat object.
  String patchUrl = url;
  // Remove trailing .json before appending override param
  if (patchUrl.endsWith(".json")) {
    patchUrl = patchUrl.substring(0, patchUrl.length() - 5);
  }
  patchUrl += ".json?x-http-method-override=PATCH";

  bool ok = _httpRequest(patchUrl, payload, 1);
  if (ok) {
    SerialMon.println("  ✅ deviceStatus PATCH OK");
  } else {
    SerialMon.println("  ❌ deviceStatus PATCH FAILED");
    blinkRed(2);
  }
}

String httpGet(const String& url) {
  _sendAT("AT+HTTPTERM", 500);
  delay(200);
  if (_sendAT("AT+HTTPINIT", 2000).indexOf("OK") == -1) return "";
  _sendAT("AT+HTTPPARA=\"CID\",1", 500);
  _sendAT("AT+HTTPPARA=\"URL\",\"" + url + "\"", 1000);

  SerialAT.println("AT+HTTPACTION=0");
  String result;
  unsigned long deadline = millis() + 20000;
  while (millis() < deadline) {
    while (SerialAT.available()) result += (char)SerialAT.read();
    if (result.indexOf("+HTTPACTION:") != -1) break;
  }

  if (result.indexOf(",200,") == -1) {
    _sendAT("AT+HTTPTERM", 500);
    return "";
  }

  delay(500);
  while (SerialAT.available()) SerialAT.read(); // flush

  SerialAT.println("AT+HTTPREAD=0,4096");
  String body;
  deadline = millis() + 10000;
  while (millis() < deadline) {
    while (SerialAT.available()) body += (char)SerialAT.read();
    if (body.indexOf("+HTTPREAD: 0") != -1) break;
  }
  _sendAT("AT+HTTPTERM", 500);

  int s = body.indexOf("{");
  int e = body.lastIndexOf("}");
  if (s == -1 || e == -1) return "";
  return body.substring(s, e + 1);
}

// ==================== DEVICE AUTHENTICATION ====================
//
// Reads realDevices node, finds the entry whose deviceCode matches
// DEVICE_CODE, then extracts actionOwnerID as userUid.
//
bool authenticateDevice() {
  String url = FIREBASE_URL + "/realDevices.json";
  SerialMon.println("  GET " + url);

  String json = httpGet(url);
  if (json.isEmpty()) {
    SerialMon.println("  ❌ Empty response from realDevices");
    return false;
  }

  StaticJsonDocument<4096> doc;
  if (deserializeJson(doc, json) != DeserializationError::Ok) {
    SerialMon.println("  ❌ JSON parse error");
    return false;
  }

  for (JsonPair entry : doc.as<JsonObject>()) {
    String uid    = entry.key().c_str();
    JsonObject dev = entry.value().as<JsonObject>();

    if (!dev.containsKey("deviceCode")) continue;
    if (String(dev["deviceCode"].as<const char*>()) != DEVICE_CODE) continue;

    if (!dev.containsKey("actionOwnerID")) continue;
    String owner = dev["actionOwnerID"].as<String>();
    if (owner.isEmpty() || owner == "null") continue;

    deviceUid = uid;
    userUid   = owner;
    return true;
  }

  return false;
}

// ==================== LED HELPERS ====================
void blinkRed(int times) {
  for (int i = 0; i < times; i++) {
    digitalWrite(RED_PIN, HIGH);
    delay(200);
    digitalWrite(RED_PIN, LOW);
    delay(200);
  }
}

void blinkGreen(int times) {
  for (int i = 0; i < times; i++) {
    digitalWrite(GRN_PIN, HIGH);
    delay(200);
    digitalWrite(GRN_PIN, LOW);
    delay(200);
  }
}

void flashSOS() {
  // Morse: S (···) O (−−−) S (···)
  auto dot  = []() { digitalWrite(RED_PIN,HIGH);delay(150);
                      digitalWrite(RED_PIN,LOW); delay(150); };
  auto dash = []() { digitalWrite(RED_PIN,HIGH);delay(400);
                      digitalWrite(RED_PIN,LOW); delay(150); };
  for (int i=0;i<3;i++) dot();  delay(200);
  for (int i=0;i<3;i++) dash(); delay(200);
  for (int i=0;i<3;i++) dot();
}
