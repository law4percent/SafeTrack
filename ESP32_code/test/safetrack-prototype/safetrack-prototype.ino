/*
 * SafeTrack GPS Tracker - Complete Implementation v3
 * Features: GPS tracking, Battery monitoring, SOS button, Firebase sync
 * Hardware: ESP32 + SIM7600 + MAX17043
 * 
 * SOS status is included in regular deviceLogs updates
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

// ==================== MAX17043 CONFIGURATION ====================
#define MAX17043_ADDR 0x36
#define MAX17043_VCELL 0x02
#define MAX17043_SOC   0x04

// ==================== SERIAL CONFIGURATION ====================
HardwareSerial SerialAT(1);
#define SerialMon Serial

// ==================== FIREBASE CONFIGURATION ====================
String firebaseURL = "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app";
String deviceCode = "DEVICE1234";  // CHANGE THIS TO YOUR DEVICE CODE

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

// ==================== GPS DATA ====================
float currentLat = 0.0;
float currentLon = 0.0;
float currentAlt = 0.0;
float lastValidLat = 0.0;
float lastValidLon = 0.0;
float lastValidAlt = 0.0;
bool gpsAvailable = false;
float gpsSpeed = 0.0;
int gpsHeading = 0;

// ==================== BATTERY DATA ====================
float batteryLevel = 0.0;

// ==================== SOS FUNCTIONALITY ====================
bool sosActive = false;
bool sosButtonPressed = false;
unsigned long sosButtonPressStart = 0;
unsigned long sosActivatedTime = 0;
unsigned long lastButtonCheck = 0;
const unsigned long SOS_HOLD_TIME = 5000;      // 5 seconds
const unsigned long SOS_ACTIVE_DURATION = 60000; // 1 minute
const unsigned long BUTTON_CHECK_INTERVAL = 100; // Check every 100ms

// ==================== TIMING ====================
unsigned long lastUpdate = 0;
const unsigned long UPDATE_INTERVAL = 30000; // 30 seconds

// ==================== FUNCTION PROTOTYPES ====================
bool checkNetworkConnection();
void connectNetwork();
bool authenticateDevice();
void sendToFirebase();
String sendATCommand(String cmd, unsigned long timeout);
void blinkRed();
void blinkGreen();
void flashSOSPattern();
bool readGPS();
float readBatteryLevel();
void initMAX17043();
void handleSOSButton();

// ==================== SETUP ====================
void setup() {
  SerialMon.begin(115200);
  delay(300);
  SerialMon.println("\n\n=== SafeTrack GPS Tracker v3 ===");
  SerialMon.println("Device Code: " + deviceCode);

  // Initialize pins
  pinMode(RED_PIN, OUTPUT);
  pinMode(GRN_PIN, OUTPUT);
  pinMode(SOS_BTN, INPUT_PULLUP);
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GRN_PIN, LOW);

  // Test button reading
  SerialMon.print("SOS Button initial state: ");
  SerialMon.println(digitalRead(SOS_BTN) == LOW ? "PRESSED" : "RELEASED");

  // Initialize I2C for battery monitor
  Wire.begin(SDA_PIN, SCL_PIN);
  initMAX17043();
  
  // Read initial battery level
  batteryLevel = readBatteryLevel();
  SerialMon.printf("Initial Battery: %.1f%%\n", batteryLevel);

  // Power on SIM7600 module
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH);
  delay(300);
  digitalWrite(PWR_PIN, LOW);
  delay(5000);

  SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX);

  SerialMon.println("Initializing modem...");
  if (!modem.restart()) {
    SerialMon.println("⚠️ Failed to restart modem, continuing...");
  }

  String modemInfo = modem.getModemInfo();
  SerialMon.println("Modem Info: " + modemInfo);

  // Enable GPS
  SerialMon.println("Enabling GPS...");
  modem.enableGPS();
  delay(2000);

  SerialMon.println("\n📡 Establishing Network Connection...");
  if (!checkNetworkConnection()) {
    SerialMon.println("🚫 Network not registered. Attempting full connect...");
  }
  connectNetwork();

  delay(2000);
  
  // Authenticate device with Firebase
  SerialMon.println("\n🔐 Authenticating Device...");
  if (authenticateDevice()) {
    SerialMon.println("✅ Device Authorized!");
    SerialMon.println("   User UID: " + userUid);
    SerialMon.println("   Device UID: " + deviceUid);
    isAuthorized = true;
    blinkGreen();
  } else {
    SerialMon.println("❌ Device Not Authorized!");
    SerialMon.println("   Please assign device in Firebase");
    isAuthorized = false;
    
    // Blink red LED continuously and halt
    while (true) {
      blinkRed();
      delay(1000);
    }
  }

  SerialMon.println("\n✅ Setup Complete! Starting tracking...");
  SerialMon.println("📌 Press and HOLD SOS button for 5 seconds to activate\n");
  
  lastUpdate = millis();
}

// ==================== MAIN LOOP ====================
void loop() {
  // Check authorization
  if (!isAuthorized) {
    blinkRed();
    delay(1000);
    return;
  }

  // CRITICAL: Check SOS button frequently (every 100ms)
  unsigned long currentMillis = millis();
  if (currentMillis - lastButtonCheck >= BUTTON_CHECK_INTERVAL) {
    lastButtonCheck = currentMillis;
    handleSOSButton();
  }

  // Periodic updates (every 30 seconds)
  if (currentMillis - lastUpdate >= UPDATE_INTERVAL) {
    lastUpdate = currentMillis;
    
    // Check battery level
    batteryLevel = readBatteryLevel();
    if (batteryLevel < 15.0) {
      SerialMon.println("⚠️ LOW BATTERY: " + String(batteryLevel, 1) + "%");
      blinkRed();
    }

    // Check GPRS connection
    if (!modem.isGprsConnected()) {
      SerialMon.println("🔴 GPRS disconnected. Reconnecting...");
      connectNetwork();
      delay(2000);
    }

    SerialMon.println("\n========================================");
    SerialMon.println("=== LOCATION UPDATE ===");
    SerialMon.println("========================================");

    // Read GPS data
    gpsAvailable = readGPS();

    // Display current status
    SerialMon.println("\n📊 Current Status:");
    SerialMon.printf("  Battery: %.1f%%\n", batteryLevel);
    SerialMon.printf("  GPS: %s\n", gpsAvailable ? "AVAILABLE" : "UNAVAILABLE");
    SerialMon.printf("  SOS: %s\n", sosActive ? "🚨 ACTIVE" : "INACTIVE");
    
    if (gpsAvailable) {
      SerialMon.printf("  Current: %.6f, %.6f, %.1fm\n", currentLat, currentLon, currentAlt);
    } else {
      SerialMon.println("  Using last known location");
      SerialMon.printf("  Last: %.6f, %.6f, %.1fm\n", lastValidLat, lastValidLon, lastValidAlt);
    }

    // Send to Firebase
    sendToFirebase();

    // Success indication
    blinkGreen();

    SerialMon.println("\n⏱️  Next update in 30 seconds...\n");
  }
  
  // Small delay to prevent CPU hogging
  delay(10);
}

// ==================== NETWORK FUNCTIONS ====================

bool checkNetworkConnection() {
  int state = modem.getRegistrationStatus();
  if (state == 1 || state == 5) {
    SerialMon.println("📶 Network registered.");
    return true;
  } else {
    SerialMon.printf("🚫 Network not registered (Status: %d)\n", state);
    return false;
  }
}

void connectNetwork() {
  SerialMon.print("Connecting to APN: ");
  SerialMon.println(apn);

  if (modem.isGprsConnected()) {
    SerialMon.println("GPRS already connected.");
    return;
  }
  
  if (!modem.gprsConnect(apn, user, pass)) {
    SerialMon.println("❌ Failed to connect GPRS!");
  } else {
    SerialMon.println("✅ GPRS connected!");
    String ip = modem.getLocalIP();
    SerialMon.println("📱 IP Address: " + ip);
  }
}

// ==================== GPS FUNCTION ====================

bool readGPS() {
  SerialMon.println("📡 Reading GPS data...");
  
  float lat, lon, alt, speed;
  int heading;
  
  if (modem.getGPS(&lat, &lon, &alt, &speed, &heading)) {
    // Valid GPS data received
    if (lat != 0.0 && lon != 0.0) {
      currentLat = lat;
      currentLon = lon;
      currentAlt = alt;
      gpsSpeed = speed;
      gpsHeading = heading;
      
      // Update last valid location
      lastValidLat = lat;
      lastValidLon = lon;
      lastValidAlt = alt;
      
      SerialMon.println("✅ GPS lock acquired");
      SerialMon.printf("   Lat: %.6f, Lon: %.6f, Alt: %.1fm\n", lat, lon, alt);
      return true;
    }
  }
  
  SerialMon.println("⚠️ GPS unavailable - will use cached location");
  return false;
}

// ==================== BATTERY FUNCTIONS ====================

void initMAX17043() {
  SerialMon.println("Initializing MAX17043 battery monitor...");
  
  // Send quick-start command to ensure accurate readings
  Wire.beginTransmission(MAX17043_ADDR);
  Wire.write(0xFE);
  Wire.write(0x54);
  Wire.write(0x00);
  Wire.endTransmission();
  
  delay(500);
  SerialMon.println("✅ MAX17043 initialized");
}

float readBatteryLevel() {
  Wire.beginTransmission(MAX17043_ADDR);
  Wire.write(MAX17043_SOC);
  Wire.endTransmission(false);
  
  Wire.requestFrom(MAX17043_ADDR, 2);
  
  if (Wire.available() >= 2) {
    uint8_t msb = Wire.read();
    uint8_t lsb = Wire.read();
    
    // Calculate percentage (MSB is integer part, LSB/256 is fractional)
    float percentage = msb + (lsb / 256.0);
    return percentage;
  }
  
  return 0.0;
}

// ==================== SOS BUTTON HANDLER ====================

void handleSOSButton() {
  int buttonState = digitalRead(SOS_BTN);
  unsigned long currentMillis = millis();
  
  // Check if SOS should be deactivated (1 minute passed)
  if (sosActive && (currentMillis - sosActivatedTime >= SOS_ACTIVE_DURATION)) {
    sosActive = false;
    SerialMon.println("🔔 SOS automatically deactivated after 1 minute");
    digitalWrite(RED_PIN, LOW);
  }
  
  // Button is pressed (LOW because of pull-up)
  if (buttonState == LOW) {
    if (!sosButtonPressed) {
      // Button just pressed
      sosButtonPressed = true;
      sosButtonPressStart = currentMillis;
      SerialMon.println("🔴 SOS button pressed! Hold for 5 seconds...");
      digitalWrite(RED_PIN, HIGH);
    } else if (!sosActive) {
      // Button is being held, check duration
      unsigned long holdDuration = currentMillis - sosButtonPressStart;
      
      // Show progress every second
      if (holdDuration % 1000 < BUTTON_CHECK_INTERVAL) {
        int secondsHeld = holdDuration / 1000;
        if (secondsHeld > 0 && secondsHeld < 5) {
          SerialMon.printf("   Holding... %d/5 seconds\n", secondsHeld);
        }
      }
      
      // Activate SOS after 5 seconds
      if (holdDuration >= SOS_HOLD_TIME) {
        sosActive = true;
        sosActivatedTime = currentMillis;
        SerialMon.println("\n🚨🚨🚨 SOS ACTIVATED! 🚨🚨🚨");
        SerialMon.println("Will remain active for 1 minute");
        SerialMon.println("SOS status will be sent in next Firebase update");
        
        // Visual feedback - fast flash pattern
        flashSOSPattern();
        
        // Send immediate update to Firebase with SOS active
        sendToFirebase();
      }
    }
  } else {
    // Button released
    if (sosButtonPressed) {
      unsigned long holdDuration = currentMillis - sosButtonPressStart;
      
      if (holdDuration < SOS_HOLD_TIME && !sosActive) {
        SerialMon.printf("⚠️ SOS button released too early (held for %.1f sec, need 5 sec)\n", 
                        holdDuration / 1000.0);
        digitalWrite(RED_PIN, LOW);
      }
      
      sosButtonPressed = false;
      sosButtonPressStart = 0;
    }
  }
  
  // Keep LED on while SOS is active
  if (sosActive) {
    // Slow blink to indicate active SOS
    if ((currentMillis / 500) % 2 == 0) {
      digitalWrite(RED_PIN, HIGH);
    } else {
      digitalWrite(RED_PIN, LOW);
    }
  }
}

// ==================== DEVICE AUTHENTICATION ====================

bool authenticateDevice() {
  SerialMon.println("Checking device authorization in Firebase...");
  
  String url = firebaseURL + "/realDevices.json";
  
  sendATCommand("AT+HTTPTERM", 500);
  delay(300);
  
  if (sendATCommand("AT+HTTPINIT", 2000).indexOf("OK") == -1) {
    SerialMon.println("✗ HTTP init failed");
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
  
  if (jsonStart == -1 || jsonEnd == -1) {
    return false;
  }
  
  String jsonData = httpData.substring(jsonStart, jsonEnd + 1);
  
  StaticJsonDocument<2048> doc;
  DeserializationError error = deserializeJson(doc, jsonData);
  
  if (error) {
    SerialMon.println("✗ JSON parse error");
    return false;
  }
  
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
          
          if (ownerId.length() > 0 && ownerId != "null") {
            userUid = ownerId;
            return true;
          }
        }
      }
    }
  }
  
  return false;
}

// ==================== FIREBASE FUNCTION ====================

void sendToFirebase() {
  if (!modem.isGprsConnected()) {
    SerialMon.println("❌ GPRS not connected");
    return;
  }

  String firebasePath = firebaseURL + "/deviceLogs/" + userUid + "/" + deviceCode + ".json";
  
  SerialMon.println("\n📤 Sending to Firebase...");
  SerialMon.println("Path: /deviceLogs/" + userUid + "/" + deviceCode);

  // Build JSON payload with new structure
  StaticJsonDocument<512> doc;
  
  doc["batteryLevel"] = round(batteryLevel * 10) / 10.0;
  doc["gpsAvailable"] = gpsAvailable;
  doc["sos"] = sosActive;  // SOS status in regular updates
  
  // Current location (live or cached)
  JsonObject currentLoc = doc.createNestedObject("currentLocation");
  currentLoc["latitude"] = gpsAvailable ? currentLat : lastValidLat;
  currentLoc["longitude"] = gpsAvailable ? currentLon : lastValidLon;
  currentLoc["altitude"] = gpsAvailable ? currentAlt : lastValidAlt;
  currentLoc["status"] = gpsAvailable ? "success" : "cached";
  
  // Last valid location
  JsonObject lastLoc = doc.createNestedObject("lastLocation");
  lastLoc["latitude"] = lastValidLat;
  lastLoc["longitude"] = lastValidLon;
  lastLoc["altitude"] = lastValidAlt;
  
  // Timestamp (server-side)
  JsonObject ts = doc.createNestedObject("lastUpdate");
  ts[".sv"] = "timestamp";
  
  String payload;
  serializeJson(doc, payload);
  
  SerialMon.println("Payload: " + payload);
  if (sosActive) {
    SerialMon.println("⚠️ SOS STATUS ACTIVE - Sending emergency alert!");
  }

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
    SerialMon.println("✅ Firebase updated successfully!");
    if (sosActive) {
      SerialMon.println("🚨 SOS alert sent to parent!");
    }
  } else {
    SerialMon.println("⚠️ Firebase update may have failed");
  }
  
  sendATCommand("AT+HTTPTERM", 500);
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

void blinkRed() {
  digitalWrite(RED_PIN, HIGH);
  digitalWrite(GRN_PIN, LOW);
  delay(200);
  digitalWrite(RED_PIN, LOW);
  delay(200);
}

void blinkGreen() {
  for (int i = 0; i < 3; i++) {
    digitalWrite(GRN_PIN, HIGH);
    digitalWrite(RED_PIN, LOW);
    delay(200);
    digitalWrite(GRN_PIN, LOW);
    delay(200);
  }
}

void flashSOSPattern() {
  // S-O-S pattern in morse code
  // S = 3 short, O = 3 long, S = 3 short
  
  // S
  for (int i = 0; i < 3; i++) {
    digitalWrite(RED_PIN, HIGH);
    delay(100);
    digitalWrite(RED_PIN, LOW);
    delay(100);
  }
  delay(200);
  
  // O
  for (int i = 0; i < 3; i++) {
    digitalWrite(RED_PIN, HIGH);
    delay(300);
    digitalWrite(RED_PIN, LOW);
    delay(100);
  }
  delay(200);
  
  // S
  for (int i = 0; i < 3; i++) {
    digitalWrite(RED_PIN, HIGH);
    delay(100);
    digitalWrite(RED_PIN, LOW);
    delay(100);
  }
}