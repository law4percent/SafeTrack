/*
 * SafeTrack Device - Production Version v2.3
 * Features: GPS Tracking, SOS Button, Battery Monitoring, Device Status
 * Hardware: ESP32 + SIM7600 + MAX17043
 * https://claude.ai/chat/c76f0b98-63a7-467d-8143-95b59dff9fe4 Remalyn Abao Claude 
 */

// ==================== MODEM CONFIGURATION ====================
#define TINY_GSM_MODEM_SIM7600
#define TINY_GSM_RX_BUFFER 1024

#include <TinyGsmClient.h>
#include <HardwareSerial.h>
#include <ArduinoJson.h>
#include <Wire.h>

// ==================== PIN DEFINITIONS ====================
#define UART_BAUD   115200
#define PIN_TX      17
#define PIN_RX      16
#define PWR_PIN     4
#define RED_PIN     27
#define GRN_PIN     26
#define SOS_BTN     18
#define SDA_PIN     21
#define SCL_PIN     22

#define MAX17043_ADDR 0x36

// ==================== SERIAL CONFIGURATION ====================
HardwareSerial SerialAT(1);
#define SerialMon Serial

// ==================== FIREBASE CONFIGURATION ====================
String firebaseURL = "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app";
String deviceCode = "DEVICE1234";

// ==================== DEVICE AUTHENTICATION ====================
String userUid = "";
String deviceUid = "";
bool isAuthorized = false;

// ==================== NETWORK CREDENTIALS ====================
const char apn[] = "http.globe.com.ph";
const char user[] = "";
const char pass[] = "";

// ==================== GLOBAL OBJECTS ====================
TinyGsm modem(SerialAT);

// ==================== GPS DATA VARIABLES ====================
float latitude = 0.0;
float longitude = 0.0;
float altitude = 0.0;
float speed_kph = 0.0;
int heading = 0;
bool gpsAvailable = false;

float cachedLatitude = 0.0;
float cachedLongitude = 0.0;
float cachedAltitude = 0.0;
bool hasCachedLocation = false;

// ==================== BATTERY & SOS VARIABLES ====================
float batteryPercent = 0.0;
float batteryVoltage = 0.0;
bool sosActive = false;
unsigned long sosStartTime = 0;
unsigned long sosButtonPressStart = 0;
bool sosButtonPressed = false;

// ==================== TIMING VARIABLES ====================
unsigned long lastLocationUpdate = 0;
unsigned long lastHeartbeat = 0;
const unsigned long LOCATION_INTERVAL = 30000;
const unsigned long HEARTBEAT_INTERVAL = 60000;
const unsigned long SOS_TIMEOUT = 60000;
const unsigned long SOS_PRESS_DURATION = 5000;

// ==================== FUNCTION PROTOTYPES ====================
bool checkNetworkConnection();
void connectNetwork();
bool authenticateDevice();
void sendLocationToFirebase();
void sendHeartbeat();
void updateDeviceStatus();
void checkSOSButton();
void readBatteryLevel();
String sendATCommand(String cmd, unsigned long timeout);
bool firebasePUT(String path, String json);
void blinkRed(int times = 1);
void blinkGreen(int times = 1);
void blinkBoth();
void showLowBattery();
void showSOSActive();
void showNoInternet();

// ==================== SETUP ====================
void setup() {
  SerialMon.begin(115200);
  delay(300);
  SerialMon.println("\n=== SafeTrack Device v2.3 ===");
  SerialMon.println("Device Code: " + deviceCode);

  pinMode(RED_PIN, OUTPUT);
  pinMode(GRN_PIN, OUTPUT);
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GRN_PIN, LOW);

  pinMode(SOS_BTN, INPUT_PULLUP);

  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);

  readBatteryLevel();
  SerialMon.printf("Battery: %.1f%% (%.2fV)\n", batteryPercent, batteryVoltage);

  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH);
  delay(300);
  digitalWrite(PWR_PIN, LOW);
  delay(5000);

  SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX);

  SerialMon.println("Initializing modem...");
  blinkBoth();
  
  if (!modem.restart()) {
    SerialMon.println("⚠️ Modem restart failed");
  }

  SerialMon.println("Modem: " + modem.getModemInfo());
  SerialMon.println("Connecting to network...");
  
  if (!checkNetworkConnection()) {
    SerialMon.println("Network not registered");
  }
  connectNetwork();

  delay(2000);
  
  SerialMon.println("Authenticating device...");
  blinkBoth();
  
  if (authenticateDevice()) {
    SerialMon.println("✅ Authorized");
    SerialMon.println("User: " + userUid);
    SerialMon.println("Device: " + deviceUid);
    isAuthorized = true;
    blinkGreen(3);
  } else {
    SerialMon.println("❌ Not Authorized");
    isAuthorized = false;
    while (true) {
      blinkRed();
      delay(1000);
    }
  }

  SerialMon.println("Enabling GPS...");
  modem.enableGPS();
  delay(2000);

  SerialMon.println("✅ Setup Complete\n");
}

// ==================== MAIN LOOP ====================
void loop() {
  if (!isAuthorized) {
    blinkRed();
    delay(1000);
    return;
  }

  checkSOSButton();

  if (sosActive && (millis() - sosStartTime > SOS_TIMEOUT)) {
    SerialMon.println("SOS timeout");
    sosActive = false;
    updateDeviceStatus();
  }

  readBatteryLevel();
  
  if (batteryPercent < 20.0) {
    showLowBattery();
  }

  if (!modem.isGprsConnected()) {
    SerialMon.println("GPRS disconnected, reconnecting...");
    showNoInternet();
    connectNetwork();
    delay(2000);
  }

  if (sosActive || (millis() - lastLocationUpdate >= LOCATION_INTERVAL)) {
    SerialMon.println("\n=== Location Update ===");

    if (modem.getGPS(&latitude, &longitude, &altitude, &speed_kph, &heading)) {
      gpsAvailable = true;
      
      SerialMon.printf("GPS: %.6f, %.6f\n", latitude, longitude);
      SerialMon.printf("Alt: %.1fm, Speed: %.1fkm/h\n", altitude, speed_kph);
      
      cachedLatitude = latitude;
      cachedLongitude = longitude;
      cachedAltitude = altitude;
      hasCachedLocation = true;
      
      blinkGreen();
      sendLocationToFirebase();
      lastLocationUpdate = millis();
      
    } else {
      gpsAvailable = false;
      SerialMon.println("GPS unavailable");
      blinkRed();
      
      if (sosActive && hasCachedLocation) {
        SerialMon.println("SOS: Using cached location");
        latitude = cachedLatitude;
        longitude = cachedLongitude;
        altitude = cachedAltitude;
        sendLocationToFirebase();
      }
      
      lastLocationUpdate = millis();
    }
    
    updateDeviceStatus();
  }

  if (millis() - lastHeartbeat >= HEARTBEAT_INTERVAL) {
    sendHeartbeat();
    lastHeartbeat = millis();
  }

  delay(100);
}

// ==================== NETWORK FUNCTIONS ====================

bool checkNetworkConnection() {
  int state = modem.getRegistrationStatus();
  return (state == 1 || state == 5);
}

void connectNetwork() {
  SerialMon.println("Connecting to: " + String(apn));

  if (modem.isGprsConnected()) {
    SerialMon.println("Already connected");
    return;
  }
  
  if (!modem.gprsConnect(apn, user, pass)) {
    SerialMon.println("❌ GPRS failed");
    showNoInternet();
  } else {
    SerialMon.println("✅ GPRS connected");
    SerialMon.println("IP: " + modem.getLocalIP());
  }
}

// ==================== DEVICE AUTHENTICATION ====================

bool authenticateDevice() {
  if (!modem.isGprsConnected()) {
    connectNetwork();
    delay(2000);
    if (!modem.isGprsConnected()) return false;
  }
  
  String url = firebaseURL + "/realDevices.json";
  
  sendATCommand("AT+HTTPTERM", 500);
  delay(300);
  
  if (sendATCommand("AT+HTTPINIT", 2000).indexOf("OK") == -1) {
    return false;
  }
  
  sendATCommand("AT+HTTPPARA=\"CID\",1", 500);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", 2000);
  
  SerialAT.println("AT+HTTPACTION=0");
  delay(1000);
  
  String actionResp = "";
  unsigned long timeout = millis() + 20000;
  bool success = false;
  
  while (millis() < timeout) {
    while (SerialAT.available()) {
      String line = SerialAT.readStringUntil('\n');
      line.trim();
      
      if (line.indexOf("+HTTPACTION: 0,200") != -1) {
        success = true;
        break;
      }
    }
    if (success) break;
    delay(10);
  }
  
  if (!success) {
    sendATCommand("AT+HTTPTERM", 1000);
    return false;
  }
  
  delay(1000);
  while (SerialAT.available()) SerialAT.read();
  
  SerialAT.println("AT+HTTPREAD=0,4096");
  
  String httpData = "";
  timeout = millis() + 10000;
  
  while (millis() < timeout) {
    while (SerialAT.available()) {
      httpData += (char)SerialAT.read();
    }
    if (httpData.indexOf("+HTTPREAD: 0") != -1) break;
  }
  
  sendATCommand("AT+HTTPTERM", 1000);
  
  int jsonStart = httpData.indexOf("{");
  int jsonEnd = httpData.lastIndexOf("}");
  
  if (jsonStart == -1 || jsonEnd == -1) return false;
  
  String jsonData = httpData.substring(jsonStart, jsonEnd + 1);
  
  StaticJsonDocument<2048> doc;
  DeserializationError error = deserializeJson(doc, jsonData);
  
  if (error) return false;
  
  JsonObject devices = doc.as<JsonObject>();
  
  for (JsonPair deviceEntry : devices) {
    String currentDeviceUid = deviceEntry.key().c_str();
    JsonObject device = deviceEntry.value().as<JsonObject>();
    
    if (device.containsKey("deviceCode")) {
      String currentDeviceCode = device["deviceCode"].as<String>();
      
      if (currentDeviceCode == deviceCode) {
        deviceUid = currentDeviceUid;
        
        if (device.containsKey("actionOwnerID")) {
          String ownerId = device["actionOwnerID"].as<String>();
          
          if (ownerId.length() > 0 && ownerId != "null" && ownerId != "") {
            userUid = ownerId;
            return true;
          }
        }
      }
    }
  }
  
  return false;
}

// ==================== SOS BUTTON HANDLING ====================

void checkSOSButton() {
  bool buttonState = digitalRead(SOS_BTN);
  
  if (buttonState == LOW) {
    if (!sosButtonPressed) {
      sosButtonPressed = true;
      sosButtonPressStart = millis();
      SerialMon.println("SOS button pressed...");
    } else {
      unsigned long pressDuration = millis() - sosButtonPressStart;
      if (pressDuration >= SOS_PRESS_DURATION && !sosActive) {
        sosActive = true;
        sosStartTime = millis();
        SerialMon.println("🚨 SOS ACTIVATED");
        
        if (modem.getGPS(&latitude, &longitude, &altitude, &speed_kph, &heading)) {
          sendLocationToFirebase();
        }
        
        updateDeviceStatus();
        showSOSActive();
      }
    }
  } else {
    sosButtonPressed = false;
  }
  
  if (sosActive) {
    showSOSActive();
  }
}

// ==================== BATTERY MONITORING ====================

void readBatteryLevel() {
  Wire.beginTransmission(MAX17043_ADDR);
  Wire.write(0x04);
  Wire.endTransmission(false);
  
  Wire.requestFrom(MAX17043_ADDR, 2);
  if (Wire.available() == 2) {
    uint8_t msb = Wire.read();
    uint8_t lsb = Wire.read();
    batteryPercent = msb + (lsb / 256.0);
  }
  
  Wire.beginTransmission(MAX17043_ADDR);
  Wire.write(0x02);
  Wire.endTransmission(false);
  
  Wire.requestFrom(MAX17043_ADDR, 2);
  if (Wire.available() == 2) {
    uint8_t msb = Wire.read();
    uint8_t lsb = Wire.read();
    uint16_t vcell = (msb << 8) | lsb;
    batteryVoltage = (vcell >> 4) * 1.25 / 1000.0;
  }
}

// ==================== FIREBASE FUNCTIONS ====================

void sendLocationToFirebase() {
  if (!modem.isGprsConnected()) {
    blinkRed(2);
    return;
  }
  
  if (latitude == 0.0 && longitude == 0.0) {
    SerialMon.println("Skipping: Invalid GPS");
    return;
  }

  String firebasePath = firebaseURL + "/deviceLogs/" + userUid + "/" + deviceUid + ".json";
  
  SerialMon.println("Sending location...");

  String payload = "{";
  payload += "\"latitude\":" + String(latitude, 8) + ",";
  payload += "\"longitude\":" + String(longitude, 8) + ",";
  payload += "\"altitude\":" + String(altitude, 2) + ",";
  payload += "\"timestamp\":{\".sv\":\"timestamp\"}";
  payload += "}";

  sendATCommand("AT+HTTPTERM", 500);
  delay(300);
  
  sendATCommand("AT+HTTPINIT", 1000);
  sendATCommand("AT+HTTPPARA=\"CID\",1", 500);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + firebasePath + "\"", 1000);
  sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 500);

  SerialAT.println("AT+HTTPDATA=" + String(payload.length()) + ",10000");
  delay(500);
  
  String resp = "";
  unsigned long start = millis();
  while (millis() - start < 2000) {
    if (SerialAT.available()) resp += (char)SerialAT.read();
    if (resp.indexOf("DOWNLOAD") != -1) break;
  }
  
  if (resp.indexOf("DOWNLOAD") != -1) {
    SerialAT.print(payload);
    delay(1000);
  }

  String actionResp = sendATCommand("AT+HTTPACTION=1", 15000);
  
  if (actionResp.indexOf("+HTTPACTION: 1,200") != -1) {
    SerialMon.println("✅ Location sent");
    blinkGreen(2);
  } else {
    SerialMon.println("⚠️ Send failed");
    blinkRed(2);
  }
  
  sendATCommand("AT+HTTPTERM", 500);
}

void updateDeviceStatus() {
  if (!modem.isGprsConnected()) {
    SerialMon.println("⚠️ GPRS not connected");
    return;
  }

  SerialMon.println("Updating status...");

  // Prepare location values
  int locLat = 0;
  int locLon = 0;
  int locAlt = 0;
  
  if (hasCachedLocation) {
    locLat = (int)cachedLatitude;
    locLon = (int)cachedLongitude;
    locAlt = (int)cachedAltitude;
  }
  
  if (gpsAvailable) {
    locLat = (int)latitude;
    locLon = (int)longitude;
    locAlt = (int)altitude;
  }

  // Update each field separately using PUT (works reliably)
  String basePath = "/linkedDevices/" + userUid + "/devices/" + deviceCode + "/deviceStatus";
  
  bool success = true;
  
  // Battery level
  if (!firebasePUT(basePath + "/batteryLevel.json", String(batteryPercent, 1))) {
    success = false;
  }
  delay(200);
  
  // GPS available
  if (!firebasePUT(basePath + "/gpsAvailable.json", gpsAvailable ? "true" : "false")) {
    success = false;
  }
  delay(200);
  
  // Last location (as object)
  String locPayload = "{\"latitude\":" + String(locLat) + ",\"longitude\":" + String(locLon) + ",\"altitude\":" + String(locAlt) + "}";
  if (!firebasePUT(basePath + "/lastLocation.json", locPayload)) {
    success = false;
  }
  delay(200);
  
  // SOS status
  if (!firebasePUT(basePath + "/sos.json", sosActive ? "true" : "false")) {
    success = false;
  }
  delay(200);
  
  // Timestamp (special Firebase server value)
  if (!firebasePUT(basePath + "/lastUpdate.json", "{\".sv\":\"timestamp\"}")) {
    success = false;
  }
  
  if (success) {
    SerialMon.println("✅ Status updated");
  } else {
    SerialMon.println("⚠️ Some fields failed");
  }
}

void sendHeartbeat() {
  if (!modem.isGprsConnected()) return;

  String heartbeatPath = "/linkedDevices/" + userUid + "/devices/" + deviceCode + "/deviceStatus/lastUpdate.json";
  
  SerialMon.println("Sending heartbeat...");

  if (firebasePUT(heartbeatPath, "{\".sv\":\"timestamp\"}")) {
    SerialMon.println("✅ Heartbeat sent");
  }
}

// ==================== FIREBASE PUT HELPER ====================

bool firebasePUT(String path, String value) {
  String url = firebaseURL + path;
  
  sendATCommand("AT+HTTPTERM", 300);
  delay(300);
  
  if (sendATCommand("AT+HTTPINIT", 1500).indexOf("OK") == -1) {
    return false;
  }
  
  sendATCommand("AT+HTTPPARA=\"CID\",1", 300);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", 800);
  sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 300);

  SerialAT.println("AT+HTTPDATA=" + String(value.length()) + ",10000");
  delay(500);
  
  String resp = "";
  unsigned long start = millis();
  while (millis() - start < 1500) {
    if (SerialAT.available()) resp += (char)SerialAT.read();
    if (resp.indexOf("DOWNLOAD") != -1) break;
  }
  
  if (resp.indexOf("DOWNLOAD") == -1) {
    sendATCommand("AT+HTTPTERM", 300);
    return false;
  }
  
  SerialAT.print(value);
  delay(800);

  // Clear buffer
  while (SerialAT.available()) SerialAT.read();
  delay(300);
  
  SerialAT.println("AT+HTTPACTION=2");
  delay(300);
  
  bool success = false;
  unsigned long timeout = millis() + 15000;
  
  while (millis() < timeout) {
    while (SerialAT.available()) {
      String line = SerialAT.readStringUntil('\n');
      line.trim();
      
      if (line.indexOf("+HTTPACTION: 2,200") != -1) {
        success = true;
        break;
      }
    }
    if (success) break;
    delay(50);
  }
  
  sendATCommand("AT+HTTPTERM", 300);
  return success;
}

// ==================== HELPER FUNCTIONS ====================

String sendATCommand(String cmd, unsigned long timeout) {
  String response = "";
  SerialAT.println(cmd);
  
  unsigned long start = millis();
  while (millis() - start < timeout) {
    while (SerialAT.available()) {
      char c = SerialAT.read();
      response += c;
    }
    if (response.indexOf("OK") != -1 || response.indexOf("ERROR") != -1) {
      break;
    }
  }
  
  return response;
}

// ==================== LED FUNCTIONS ====================

void blinkRed(int times) {
  for (int i = 0; i < times; i++) {
    digitalWrite(RED_PIN, HIGH);
    digitalWrite(GRN_PIN, LOW);
    delay(200);
    digitalWrite(RED_PIN, LOW);
    delay(200);
  }
}

void blinkGreen(int times) {
  for (int i = 0; i < times; i++) {
    digitalWrite(GRN_PIN, HIGH);
    digitalWrite(RED_PIN, LOW);
    delay(200);
    digitalWrite(GRN_PIN, LOW);
    delay(200);
  }
}

void blinkBoth() {
  for (int i = 0; i < 2; i++) {
    digitalWrite(RED_PIN, HIGH);
    digitalWrite(GRN_PIN, LOW);
    delay(200);
    digitalWrite(RED_PIN, LOW);
    digitalWrite(GRN_PIN, HIGH);
    delay(200);
  }
  digitalWrite(GRN_PIN, LOW);
}

void showLowBattery() {
  static unsigned long lastPulse = 0;
  static bool pulseState = false;
  
  if (millis() - lastPulse > 1000) {
    pulseState = !pulseState;
    digitalWrite(RED_PIN, pulseState ? HIGH : LOW);
    lastPulse = millis();
  }
}

void showSOSActive() {
  static unsigned long lastBlink = 0;
  static bool blinkState = false;
  
  if (millis() - lastBlink > 300) {
    blinkState = !blinkState;
    digitalWrite(RED_PIN, blinkState ? HIGH : LOW);
    lastBlink = millis();
  }
}

void showNoInternet() {
  blinkRed(3);
}