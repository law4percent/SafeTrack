/*
 * SafeTrack Device - Complete Implementation
 * Features: GPS Tracking, SOS Button, Battery Monitoring, Device Status
 * Hardware: ESP32 + SIM7600 + MAX17043
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
#define PIN_TX      17      // SIM7600 TX
#define PIN_RX      16      // SIM7600 RX
#define PWR_PIN     4       // SIM7600 Power
#define RED_PIN     27      // Red LED
#define GRN_PIN     26      // Green LED
#define SOS_BTN     18      // SOS Button (pullup)
#define SDA_PIN     21      // MAX17043 SDA
#define SCL_PIN     22      // MAX17043 SCL

// MAX17043 I2C Address
#define MAX17043_ADDR 0x36

// ==================== SERIAL CONFIGURATION ====================
HardwareSerial SerialAT(1);
#define SerialMon Serial

// ==================== FIREBASE CONFIGURATION ====================
String firebaseURL = "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app";
String deviceCode = "DEVICE1234";  // YOUR DEVICE CODE - Change this!

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
const unsigned long LOCATION_INTERVAL = 30000;  // 30 seconds
const unsigned long HEARTBEAT_INTERVAL = 60000; // 60 seconds
const unsigned long SOS_TIMEOUT = 60000;        // 1 minute
const unsigned long SOS_PRESS_DURATION = 5000;  // 5 seconds

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
  SerialMon.println("\n\n╔════════════════════════════════════╗");
  SerialMon.println("║   SafeTrack Device v2.0           ║");
  SerialMon.println("║   Complete Implementation         ║");
  SerialMon.println("╚════════════════════════════════════╝");
  SerialMon.println("Device Code: " + deviceCode);

  // Initialize LEDs
  pinMode(RED_PIN, OUTPUT);
  pinMode(GRN_PIN, OUTPUT);
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GRN_PIN, LOW);

  // Initialize SOS Button
  pinMode(SOS_BTN, INPUT_PULLUP);

  // Initialize I2C for MAX17043
  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);
  SerialMon.println("✓ I2C initialized for battery monitoring");

  // Test battery sensor
  readBatteryLevel();
  SerialMon.printf("Initial Battery: %.1f%% (%.2fV)\n", batteryPercent, batteryVoltage);

  // Power on SIM7600 module
  SerialMon.println("\n⚡ Powering on SIM7600...");
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH);
  delay(300);
  digitalWrite(PWR_PIN, LOW);
  delay(5000);

  SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX);

  SerialMon.println("Initializing modem...");
  blinkBoth();
  
  if (!modem.restart()) {
    SerialMon.println("⚠️ Failed to restart modem, continuing...");
  }

  String modemInfo = modem.getModemInfo();
  SerialMon.println("Modem Info: " + modemInfo);

  SerialMon.println("\n📡 Establishing Network Connection...");
  if (!checkNetworkConnection()) {
    SerialMon.println("🚫 Network not registered. Attempting full connect...");
  }
  connectNetwork();

  delay(2000);
  
  // Authenticate device with Firebase
  SerialMon.println("\n🔐 Authenticating Device...");
  blinkBoth();
  
  if (authenticateDevice()) {
    SerialMon.println("✅ Device Authorized!");
    SerialMon.println("   User UID: " + userUid);
    SerialMon.println("   Device UID: " + deviceUid);
    isAuthorized = true;
    blinkGreen(3);
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

  // Enable GPS
  SerialMon.println("\n🛰️ Enabling GPS...");
  modem.enableGPS();
  delay(2000);

  SerialMon.println("\n✅ Setup Complete! Starting operation...\n");
}

// ==================== MAIN LOOP ====================
void loop() {
  // Check if device is authorized
  if (!isAuthorized) {
    blinkRed();
    delay(1000);
    return;
  }

  // Check SOS button
  checkSOSButton();

  // Check if SOS timeout (1 minute)
  if (sosActive && (millis() - sosStartTime > SOS_TIMEOUT)) {
    SerialMon.println("⏱️ SOS timeout - deactivating");
    sosActive = false;
    updateDeviceStatus();
  }

  // Read battery level
  readBatteryLevel();
  
  // Show low battery warning if needed
  if (batteryPercent < 20.0) {
    showLowBattery();
  }

  // Check GPRS connection
  if (!modem.isGprsConnected()) {
    SerialMon.println("🔴 GPRS disconnected. Reconnecting...");
    showNoInternet();
    connectNetwork();
    delay(2000);
  }

  // Location update interval (30 seconds) or immediate if SOS
  if (sosActive || (millis() - lastLocationUpdate >= LOCATION_INTERVAL)) {
    SerialMon.println("\n========================================");
    SerialMon.println("=== LOCATION ACQUISITION ===");
    SerialMon.println("========================================\n");

    // Try to get GPS location
    if (modem.getGPS(&latitude, &longitude, &altitude, &speed_kph, &heading)) {
      SerialMon.println("✅ GPS Data Acquired:");
      SerialMon.printf("  Latitude: %.8f\n", latitude);
      SerialMon.printf("  Longitude: %.8f\n", longitude);
      SerialMon.printf("  Altitude: %.2f m\n", altitude);
      SerialMon.printf("  Speed: %.2f km/h\n", speed_kph);
      SerialMon.printf("  Heading: %d°\n", heading);
      SerialMon.printf("  Battery: %.1f%%\n", batteryPercent);
      
      blinkGreen();
      
      // Send to Firebase
      sendLocationToFirebase();
      
      // Update device status (lastLocation, battery, etc.)
      updateDeviceStatus();
      
      lastLocationUpdate = millis();
      
    } else {
      SerialMon.println("⚠️ GPS data not available");
      blinkRed();
      // Don't update lastLocationUpdate on failure to retry sooner
    }
  }

  // Heartbeat update (every 60 seconds)
  if (millis() - lastHeartbeat >= HEARTBEAT_INTERVAL) {
    sendHeartbeat();
    lastHeartbeat = millis();
  }

  delay(100); // Small delay for button debouncing
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
    showNoInternet();
  } else {
    SerialMon.println("✅ GPRS connected!");
    String ip = modem.getLocalIP();
    SerialMon.println("📱 IP Address: " + ip);
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
    SerialMon.println("✗ Failed to get device list");
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
    SerialMon.println("✗ No JSON data found");
    return false;
  }
  
  String jsonData = httpData.substring(jsonStart, jsonEnd + 1);
  
  StaticJsonDocument<2048> doc;
  DeserializationError error = deserializeJson(doc, jsonData);
  
  if (error) {
    SerialMon.print("✗ JSON parse error: ");
    SerialMon.println(error.c_str());
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
  
  // Button is pressed (LOW because of pullup)
  if (buttonState == LOW) {
    if (!sosButtonPressed) {
      // Button just pressed
      sosButtonPressed = true;
      sosButtonPressStart = millis();
      SerialMon.println("🔴 SOS Button pressed...");
    } else {
      // Button held - check if 5 seconds elapsed
      unsigned long pressDuration = millis() - sosButtonPressStart;
      if (pressDuration >= SOS_PRESS_DURATION && !sosActive) {
        // Activate SOS!
        sosActive = true;
        sosStartTime = millis();
        SerialMon.println("🚨 SOS ACTIVATED!");
        
        // Send immediate location update
        if (modem.getGPS(&latitude, &longitude, &altitude, &speed_kph, &heading)) {
          sendLocationToFirebase();
        }
        
        // Update device status with SOS flag
        updateDeviceStatus();
        
        // Visual feedback
        showSOSActive();
      }
    }
  } else {
    // Button released
    if (sosButtonPressed) {
      unsigned long pressDuration = millis() - sosButtonPressStart;
      if (pressDuration < SOS_PRESS_DURATION) {
        SerialMon.println("⚠️ SOS Button released too early (< 5s)");
      }
      sosButtonPressed = false;
    }
  }
  
  // Show SOS active status
  if (sosActive) {
    showSOSActive();
  }
}

// ==================== BATTERY MONITORING ====================

void readBatteryLevel() {
  Wire.beginTransmission(MAX17043_ADDR);
  Wire.write(0x04); // SOC register
  Wire.endTransmission(false);
  
  Wire.requestFrom(MAX17043_ADDR, 2);
  if (Wire.available() == 2) {
    uint8_t msb = Wire.read();
    uint8_t lsb = Wire.read();
    batteryPercent = msb + (lsb / 256.0);
  }
  
  // Read voltage
  Wire.beginTransmission(MAX17043_ADDR);
  Wire.write(0x02); // VCELL register
  Wire.endTransmission(false);
  
  Wire.requestFrom(MAX17043_ADDR, 2);
  if (Wire.available() == 2) {
    uint8_t msb = Wire.read();
    uint8_t lsb = Wire.read();
    uint16_t vcell = (msb << 8) | lsb;
    batteryVoltage = (vcell >> 4) * 1.25 / 1000.0; // Convert to volts
  }
}

// ==================== FIREBASE FUNCTIONS ====================

void sendLocationToFirebase() {
  if (!modem.isGprsConnected()) {
    SerialMon.println("❌ GPRS not connected");
    blinkRed(2);
    return;
  }

  String firebasePath = firebaseURL + "/deviceLogs/" + userUid + "/" + deviceUid + ".json";
  
  SerialMon.println("\n📤 Sending location to Firebase...");

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
    SerialMon.println("✅ Location sent to Firebase!");
    blinkGreen(2);
  } else {
    SerialMon.println("⚠️ Firebase POST failed");
    blinkRed(2);
  }
  
  sendATCommand("AT+HTTPTERM", 500);
}

void updateDeviceStatus() {
  if (!modem.isGprsConnected()) return;

  String statusPath = firebaseURL + "/linkedDevices/" + userUid + "/devices/" + deviceCode + "/deviceStatus.json";
  
  SerialMon.println("\n📊 Updating device status...");

  String payload = "{";
  payload += "\"batteryLevel\":" + String(batteryPercent, 1) + ",";
  payload += "\"lastLocation\":{";
  payload += "\"latitude\":" + String(latitude, 8) + ",";
  payload += "\"longitude\":" + String(longitude, 8) + ",";
  payload += "\"altitude\":" + String(altitude, 2);
  payload += "},";
  payload += "\"lastUpdate\":{\".sv\":\"timestamp\"},";
  payload += "\"sos\":" + String(sosActive ? "true" : "false");
  payload += "}";

  sendATCommand("AT+HTTPTERM", 500);
  delay(300);
  
  sendATCommand("AT+HTTPINIT", 1000);
  sendATCommand("AT+HTTPPARA=\"CID\",1", 500);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + statusPath + "\"", 1000);
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

  // Use PATCH to update
  SerialAT.println("AT+HTTPACTION=3"); // PATCH method
  delay(5000);
  
  SerialMon.println("✅ Device status updated");
  sendATCommand("AT+HTTPTERM", 500);
}

void sendHeartbeat() {
  if (!modem.isGprsConnected()) return;

  String heartbeatPath = firebaseURL + "/linkedDevices/" + userUid + "/devices/" + deviceCode + "/deviceStatus/lastUpdate.json";
  
  SerialMon.println("\n💓 Sending heartbeat...");

  String payload = "{\".sv\":\"timestamp\"}";

  sendATCommand("AT+HTTPTERM", 500);
  delay(300);
  
  sendATCommand("AT+HTTPINIT", 1000);
  sendATCommand("AT+HTTPPARA=\"CID\",1", 500);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + heartbeatPath + "\"", 1000);
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

  sendATCommand("AT+HTTPACTION=2", 10000); // PUT method
  SerialMon.println("✅ Heartbeat sent");
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
  // Slow pulse on red LED
  static unsigned long lastPulse = 0;
  static bool pulseState = false;
  
  if (millis() - lastPulse > 1000) {
    pulseState = !pulseState;
    digitalWrite(RED_PIN, pulseState ? HIGH : LOW);
    lastPulse = millis();
  }
}

void showSOSActive() {
  // Fast blink red LED
  static unsigned long lastBlink = 0;
  static bool blinkState = false;
  
  if (millis() - lastBlink > 300) {
    blinkState = !blinkState;
    digitalWrite(RED_PIN, blinkState ? HIGH : LOW);
    lastBlink = millis();
  }
}

void showNoInternet() {
  // Triple blink red
  blinkRed(3);
}