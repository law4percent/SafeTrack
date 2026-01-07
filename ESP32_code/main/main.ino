/*
  This project implements a SIM7600-based GPS/Location tracker that:

  Connects to a cellular network using GPRS

  Authenticates the device with Firebase Realtime Database

  Obtains location using:

  Google Geolocation API (cell tower triangulation)

  IP-based geolocation as fallback

  Sends the location to Firebase

  Uses Red/Green LEDs for status indicators
*/


// ==================== MODEM CONFIGURATION ====================
#define TINY_GSM_MODEM_SIM7600
#define TINY_GSM_RX_BUFFER 1024

#include <TinyGsmClient.h>
#include <HardwareSerial.h>
#include <ArduinoJson.h>

// ==================== PIN DEFINITIONS ====================
#define UART_BAUD   115200
#define PIN_TX      17
#define PIN_RX      16
#define PWR_PIN     4
#define RED_PIN     27  // Red LED for error/unauthorized
#define GRN_PIN     26  // Green LED for success

// ==================== SERIAL CONFIGURATION ====================
HardwareSerial SerialAT(1);
#define SerialMon Serial

// ==================== FIREBASE CONFIGURATION ====================
String firebaseURL = "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app";
String deviceCode = "DEVICE1234";  // YOUR DEVICE CODE - Change this to match your device

// ==================== GOOGLE GEOLOCATION API ====================
const char googleApiKey[] = "XXXXXXXXXXXXXX";

// ==================== DEVICE AUTHENTICATION ====================
String userUid = "";      // Will be fetched from Firebase
String deviceUid = "";    // Will be fetched from Firebase
bool isAuthorized = false;

// ==================== NETWORK CREDENTIALS ====================
const char apn[] = "internet" // http.globe.com.ph or internet for smart
const char user[] = "";
const char pass[] = "";

// ==================== GLOBAL OBJECTS ====================
TinyGsm modem(SerialAT);

// ==================== LOCATION DATA VARIABLES ====================
float latitude = 0.0;
float longitude = 0.0;
float accuracy = 0.0;
String locationType = "unknown";

// ==================== FUNCTION PROTOTYPES ====================
bool checkNetworkConnection();
void connectNetwork();
bool authenticateDevice();
void sendToFirebase(float lat, float lon, String locType, float acc);
bool getLocationFromIP();
bool getLocationFromGoogleAPI();
String sendATCommand(String cmd, unsigned long timeout);
void blinkRed();
void blinkGreen();

// ==================== SETUP ====================
void setup() {
  SerialMon.begin(115200);
  delay(300);
  SerialMon.println("\n\n=== SIM7600 SafeTrack Device ===");
  SerialMon.println("Device Code: " + deviceCode);

  pinMode(RED_PIN, OUTPUT);
  pinMode(GRN_PIN, OUTPUT);
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GRN_PIN, LOW);

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

  SerialMon.println("\n✅ Setup Complete! Starting location tracking...\n");
}

// ==================== MAIN LOOP ====================
void loop() {
  // Check if device is authorized
  if (!isAuthorized) {
    blinkRed();
    delay(1000);
    return;
  }

  SerialMon.println("\n========================================");
  SerialMon.println("=== LOCATION ACQUISITION ATTEMPT ===");
  SerialMon.println("========================================\n");

  // Check GPRS connection
  if (!modem.isGprsConnected()) {
    SerialMon.println("🔴 GPRS disconnected. Reconnecting...");
    connectNetwork();
    delay(2000);
  }

  bool locationFound = false;

  // Method 1: Try Cell Tower Location via Google API (Most Accurate)
  SerialMon.println("📶 Method 1: Cell Tower Location (Google API)");
  SerialMon.println("-----------------------------------");
  if (getLocationFromGoogleAPI()) {
    SerialMon.println("✅ Cell Tower location acquired!");
    locationFound = true;
  } else {
    SerialMon.println("❌ Cell Tower location failed\n");
  }

  // Method 2: Try IP-based Location (Fallback)
  if (!locationFound) {
    SerialMon.println("📍 Method 2: IP-based Location (Fallback)");
    SerialMon.println("-----------------------------------");
    if (getLocationFromIP()) {
      SerialMon.println("✅ IP-based location acquired!");
      locationFound = true;
    } else {
      SerialMon.println("❌ IP-based location failed\n");
    }
  }

  // Send to Firebase if location was found
  if (locationFound) {
    SerialMon.println("\n📊 Location Summary:");
    SerialMon.printf("  Type: %s\n", locationType.c_str());
    SerialMon.printf("  Latitude: %.6f\n", latitude);
    SerialMon.printf("  Longitude: %.6f\n", longitude);
    SerialMon.printf("  Accuracy: %.0f meters\n", accuracy);

    sendToFirebase(latitude, longitude, locationType, accuracy);

    // Blink green LED to indicate success
    blinkGreen();
  } else {
    SerialMon.println("\n❌ All location methods failed!");
    blinkRed();
  }

  SerialMon.println("\n⏱️  Waiting 30 seconds before next update...\n");
  delay(30000);
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

// ==================== DEVICE AUTHENTICATION ====================

bool authenticateDevice() {
  SerialMon.println("Checking device authorization in Firebase...");
  SerialMon.println("Looking for deviceCode: " + deviceCode);
  
  // Get realDevices list from Firebase
  String url = firebaseURL + "/realDevices.json";
  
  sendATCommand("AT+HTTPTERM", 500);
  delay(300);
  
  if (sendATCommand("AT+HTTPINIT", 2000).indexOf("OK") == -1) {
    SerialMon.println("✗ HTTP init failed");
    return false;
  }
  
  sendATCommand("AT+HTTPPARA=\"CID\",1", 500);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", 2000);
  
  SerialMon.println("Executing GET request...");
  SerialAT.println("AT+HTTPACTION=0");
  
  delay(1000);
  
  // Wait for response
  String actionResp = "";
  unsigned long timeout = millis() + 20000;
  bool success = false;
  
  while (millis() < timeout) {
    while (SerialAT.available()) {
      String line = SerialAT.readStringUntil('\n');
      line.trim();
      
      if (line.indexOf("+HTTPACTION: 0,200") != -1) {
        success = true;
        SerialMon.println("✓ HTTP 200 OK");
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
  
  // Read response
  SerialMon.println("Reading device data...");
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
  
  SerialMon.println("Parsing device data...");
  
  // Extract JSON
  int jsonStart = httpData.indexOf("{");
  int jsonEnd = httpData.lastIndexOf("}");
  
  if (jsonStart == -1 || jsonEnd == -1) {
    SerialMon.println("✗ No JSON data found");
    return false;
  }
  
  String jsonData = httpData.substring(jsonStart, jsonEnd + 1);
  
  // Parse JSON to find our device
  StaticJsonDocument<2048> doc;
  DeserializationError error = deserializeJson(doc, jsonData);
  
  if (error) {
    SerialMon.print("✗ JSON parse error: ");
    SerialMon.println(error.c_str());
    return false;
  }
  
  // Search for device with matching deviceCode
  JsonObject devices = doc.as<JsonObject>();
  
  for (JsonPair deviceEntry : devices) {
    String currentDeviceUid = deviceEntry.key().c_str();
    JsonObject device = deviceEntry.value().as<JsonObject>();
    
    if (device.containsKey("deviceCode")) {
      String currentDeviceCode = device["deviceCode"].as<String>();
      
      if (currentDeviceCode == deviceCode) {
        // Found matching device!
        deviceUid = currentDeviceUid;
        
        // Check if it has an owner
        if (device.containsKey("actionOwnerID")) {
          String ownerId = device["actionOwnerID"].as<String>();
          
          if (ownerId.length() > 0 && ownerId != "null" && ownerId != "") {
            userUid = ownerId;
            SerialMon.println("✓ Device found and authorized!");
            SerialMon.println("  Device UID: " + deviceUid);
            SerialMon.println("  Owner UID: " + userUid);
            return true;
          } else {
            SerialMon.println("✗ Device found but no owner assigned");
            SerialMon.println("  actionOwnerID is empty");
            return false;
          }
        } else {
          SerialMon.println("✗ Device found but no actionOwnerID field");
          return false;
        }
      }
    }
  }
  
  SerialMon.println("✗ Device code not found in Firebase");
  return false;
}

// ==================== HELPER FUNCTION ====================

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

// ==================== GOOGLE API LOCATION FUNCTION ====================

bool getLocationFromGoogleAPI() {
    if (googleApiKey[0] == 'Y') {
        SerialMon.println("✗ ERROR: Google API Key not set!");
        return false;
    }

    SerialMon.println("Step 1: Getting Cell Tower Information...");
    
    // Try AT+CPSI? first (works on SIM7600)
    String cellDataResp = sendATCommand("AT+CPSI?", 3000);
    SerialMon.println("Cell Data Response:");
    SerialMon.println(cellDataResp);
    
    String mcc = "";
    String mnc = "";
    String lac = "";
    String cid = "";
    
    // Parse AT+CPSI? response
    // Format: +CPSI: LTE,Online,515-02,0x0FA8,31138397,32,EUTRAN-BAND1...
    int cpsiIdx = cellDataResp.indexOf("+CPSI:");
    if (cpsiIdx != -1) {
        String line = cellDataResp.substring(cpsiIdx);
        int lineEnd = line.indexOf('\n');
        if (lineEnd != -1) {
            line = line.substring(0, lineEnd);
        }
        
        SerialMon.println("Parsing CPSI line: " + line);
        
        // Split by comma
        int pos = 0;
        int fieldNum = 0;
        String fields[10];
        
        while (pos < line.length() && fieldNum < 10) {
            int nextComma = line.indexOf(',', pos);
            if (nextComma == -1) nextComma = line.length();
            
            fields[fieldNum] = line.substring(pos, nextComma);
            fields[fieldNum].trim();
            fieldNum++;
            pos = nextComma + 1;
        }
        
        // Fields: [0]=+CPSI: LTE, [1]=Online, [2]=515-02, [3]=0x0FA8, [4]=31138397...
        if (fieldNum >= 5) {
            // Parse MCC-MNC from field[2] (e.g., "515-02")
            String mccMnc = fields[2];
            int dashPos = mccMnc.indexOf('-');
            if (dashPos != -1) {
                mcc = mccMnc.substring(0, dashPos);
                mnc = mccMnc.substring(dashPos + 1);
            }
            
            // LAC is field[3] (hex format like "0x0FA8")
            lac = fields[3];
            if (lac.startsWith("0x") || lac.startsWith("0X")) {
                lac = lac.substring(2);
                lac = String((long)strtol(lac.c_str(), NULL, 16));
            }
            
            // CID is field[4] (decimal)
            cid = fields[4];
            
            SerialMon.printf("✓ Parsed Cell: MCC=%s, MNC=%s, LAC=%s, CID=%s\n", 
                           mcc.c_str(), mnc.c_str(), lac.c_str(), cid.c_str());
        }
    }
    
    if (mcc.length() == 0 || lac.length() == 0 || cid.length() == 0) {
        SerialMon.println("✗ Failed to parse cell tower data");
        return false;
    }

    SerialMon.println("\nStep 2: Constructing JSON Payload...");
    
    // Create JSON payload using ArduinoJson
    StaticJsonDocument<256> doc;
    doc["considerIp"] = false;
    
    JsonArray cellTowers = doc.createNestedArray("cellTowers");
    JsonObject primaryCell = cellTowers.createNestedObject();
    
    primaryCell["cellId"] = cid.toInt();
    primaryCell["locationAreaCode"] = lac.toInt();
    primaryCell["mobileCountryCode"] = mcc.toInt();
    primaryCell["mobileNetworkCode"] = mnc.toInt();
    
    String payload;
    serializeJson(doc, payload);
    
    SerialMon.println("JSON Payload: " + payload);

    // Step 3: HTTP POST to Google Geolocation API
    String googleUrl = "https://www.googleapis.com/geolocation/v1/geolocate?key=" + String(googleApiKey);

    SerialMon.println("\nStep 3: Sending to Google Geolocation API...");
    
    sendATCommand("AT+HTTPTERM", 500);
    delay(300);
    
    if (sendATCommand("AT+HTTPINIT", 2000).indexOf("OK") == -1) {
        SerialMon.println("✗ HTTP init failed");
        return false;
    }
    
    sendATCommand("AT+HTTPPARA=\"CID\",1", 500);
    sendATCommand("AT+HTTPPARA=\"URL\",\"" + googleUrl + "\"", 2000);
    sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 500);

    SerialMon.println("Step 4: Writing payload...");
    SerialAT.println("AT+HTTPDATA=" + String(payload.length()) + ",10000");
    delay(500);
    
    String resp = "";
    unsigned long start = millis();
    while (millis() - start < 2000) {
        if (SerialAT.available()) resp += (char)SerialAT.read();
        if (resp.indexOf("DOWNLOAD") != -1) break;
    }
    
    if (resp.indexOf("DOWNLOAD") != -1) {
        SerialMon.println("✓ Ready to write");
        SerialAT.print(payload);
        delay(1000);
    } else {
        SerialMon.println("✗ HTTPDATA setup failed");
        sendATCommand("AT+HTTPTERM", 500);
        return false;
    }

    SerialMon.println("Step 5: Executing POST...");
    SerialAT.println("AT+HTTPACTION=1");
    
    // Wait for async response
    String actionResp = "";
    unsigned long timeout = millis() + 20000;
    bool success = false;
    
    while (millis() < timeout) {
        while (SerialAT.available()) {
            String line = SerialAT.readStringUntil('\n');
            line.trim();
            SerialMon.println(">> " + line);
            
            if (line.indexOf("+HTTPACTION: 1,200") != -1) {
                success = true;
                break;
            }
            if (line.indexOf("+HTTPACTION: 1,") != -1) {
                actionResp = line;
                break;
            }
        }
        if (success || actionResp.length() > 0) break;
        delay(10);
    }
    
    if (!success) {
        SerialMon.println("✗ Google API POST failed");
        SerialMon.println("Response: " + actionResp);
        sendATCommand("AT+HTTPTERM", 500);
        return false;
    }
    
    SerialMon.println("✓ POST successful!");
    
    delay(1000);
    while (SerialAT.available()) SerialAT.read();
    
    SerialMon.println("Step 6: Reading response...");
    SerialAT.println("AT+HTTPREAD=0,1024");
    
    String httpReadResp = "";
    timeout = millis() + 10000;
    
    while (millis() < timeout) {
        while (SerialAT.available()) {
            char c = SerialAT.read();
            httpReadResp += c;
            SerialMon.print(c);
        }
        if (httpReadResp.indexOf("+HTTPREAD: 0") != -1) {
            break;
        }
    }
    
    SerialMon.println("\n--- End Response ---");
    
    sendATCommand("AT+HTTPTERM", 500);

    // Parse JSON response
    int dataStart = httpReadResp.indexOf("{");
    int dataEnd = httpReadResp.lastIndexOf("}");
    String jsonResponse = "";
    
    if (dataStart != -1 && dataEnd != -1 && dataEnd > dataStart) {
        jsonResponse = httpReadResp.substring(dataStart, dataEnd + 1);
        SerialMon.println("\n📄 JSON Response:");
        SerialMon.println(jsonResponse);
    } else {
        SerialMon.println("✗ No JSON found in response");
        return false;
    }

    // Parse with ArduinoJson
    StaticJsonDocument<512> responseDoc;
    DeserializationError error = deserializeJson(responseDoc, jsonResponse);

    if (error) {
        SerialMon.print("✗ JSON Parse Error: ");
        SerialMon.println(error.c_str());
        return false;
    }

    // Extract location
    if (responseDoc.containsKey("location")) {
        latitude = responseDoc["location"]["lat"].as<float>();
        longitude = responseDoc["location"]["lng"].as<float>();
        accuracy = responseDoc["accuracy"].as<float>();
        locationType = "cell_tower";
        
        SerialMon.println("\n✓ Google API Success!");
        SerialMon.printf("  Lat: %.6f, Lon: %.6f, Acc: %.0fm\n", latitude, longitude, accuracy);
        return true;
    } else if (responseDoc.containsKey("error")) {
        String errorMsg = responseDoc["error"]["message"].as<String>();
        SerialMon.println("✗ Google API Error: " + errorMsg);
        return false;
    }
    
    SerialMon.println("✗ Unexpected response format");
    return false;
}

// ==================== IP LOCATION FUNCTION ====================

bool getLocationFromIP() {
  SerialMon.println("Step 1: Terminating any existing HTTP session...");
  sendATCommand("AT+HTTPTERM", 1000);
  delay(500);
  
  SerialMon.println("Step 2: Initializing HTTP...");
  String resp = sendATCommand("AT+HTTPINIT", 2000);
  if (resp.indexOf("OK") == -1) {
    SerialMon.println("✗ HTTP init failed");
    return false;
  }
  
  sendATCommand("AT+HTTPPARA=\"CID\",1", 1000);
  sendATCommand("AT+HTTPPARA=\"URL\",\"http://ip-api.com/json/?fields=status,lat,lon,city,regionName,country\"", 2000);
  
  SerialMon.println("Step 3: Executing GET...");
  SerialAT.println("AT+HTTPACTION=0");
  
  delay(500);
  
  String actionResult = "";
  unsigned long timeout = millis() + 20000;
  bool success = false;
  
  while (millis() < timeout) {
    while (SerialAT.available()) {
      String line = SerialAT.readStringUntil('\n');
      line.trim();
      
      if (line.indexOf("+HTTPACTION: 0,200") != -1) {
        success = true;
        SerialMon.println("✓ HTTP 200 OK");
        break;
      }
    }
    if (success) break;
    delay(10);
  }
  
  if (!success) {
    SerialMon.println("✗ HTTP GET failed");
    sendATCommand("AT+HTTPTERM", 1000);
    return false;
  }
  
  delay(1000);
  while (SerialAT.available()) SerialAT.read();
  
  SerialMon.println("Step 4: Reading response...");
  SerialAT.println("AT+HTTPREAD=0,1024");
  
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
    SerialMon.println("✗ No JSON found");
    return false;
  }
  
  String jsonData = httpData.substring(jsonStart, jsonEnd + 1);
  SerialMon.println("JSON: " + jsonData);
  
  // Simple parsing
  int latIdx = jsonData.indexOf("\"lat\":");
  int lonIdx = jsonData.indexOf("\"lon\":");
  
  if (latIdx != -1 && lonIdx != -1) {
    int latStart = latIdx + 6;
    int latEnd = jsonData.indexOf(",", latStart);
    latitude = jsonData.substring(latStart, latEnd).toFloat();
    
    int lonStart = lonIdx + 6;
    int lonEnd = jsonData.indexOf(",", lonStart);
    longitude = jsonData.substring(lonStart, lonEnd).toFloat();
    
    locationType = "ip";
    accuracy = 5000.0;
    
    return true;
  }
  
  return false;
}

// ==================== FIREBASE FUNCTION ====================

void sendToFirebase(float lat, float lon, String locType, float acc) {
  if (!modem.isGprsConnected()) {
    SerialMon.println("❌ GPRS not connected");
    return;
  }

  // Build dynamic Firebase path: /deviceLogs/{userUid}/{deviceUid}
  String firebasePath = firebaseURL + "/deviceLogs/" + userUid + "/" + deviceUid + ".json";
  
  SerialMon.println("\n📤 Sending to Firebase...");
  SerialMon.println("Path: /deviceLogs/" + userUid + "/" + deviceUid);

  String payload = "{";
  payload += "\"latitude\":" + String(lat, 6) + ",";
  payload += "\"longitude\":" + String(lon, 6) + ",";
  payload += "\"locationType\":\"" + locType + "\",";
  payload += "\"accuracy\":" + String(acc, 0) + ",";
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
    SerialMon.println("✓ Payload sent");
  }

  String actionResp = sendATCommand("AT+HTTPACTION=1", 15000);
  
  if (actionResp.indexOf("+HTTPACTION: 1,200") != -1) {
    SerialMon.println("✅ Firebase POST successful!");
  } else {
    SerialMon.println("⚠️ Firebase POST may have failed");
  }
  
  sendATCommand("AT+HTTPTERM", 500);
  SerialMon.println("📊 Firebase transmission complete\n");
}