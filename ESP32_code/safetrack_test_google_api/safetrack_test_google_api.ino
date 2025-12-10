// ==================== MODEM CONFIGURATION ====================
#define TINY_GSM_MODEM_SIM7600
#define TINY_GSM_RX_BUFFER 1024

#include <TinyGsmClient.h>
#include <HardwareSerial.h>
#include <ArduinoJson.h>  // IMPORTANT: Install ArduinoJson library via Library Manager

// ==================== PIN DEFINITIONS ====================
#define UART_BAUD   115200
#define PIN_TX      17
#define PIN_RX      16
#define PWR_PIN     4
#define LED_PIN     27

// ==================== SERIAL CONFIGURATION ====================
HardwareSerial SerialAT(1);
#define SerialMon Serial

// ==================== FIREBASE CONFIGURATION ====================
String firebaseURL = "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app";

// ==================== GOOGLE GEOLOCATION API ====================
const char googleApiKey[] = "AIzaSyB8U54lwyosieENXqSH2Oul_EWZukpDfUA";

// ==================== NETWORK CREDENTIALS ====================
const char apn[] = "http.globe.com.ph";
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
void sendToFirebase(float lat, float lon, String locType, float acc);
bool getLocationFromIP();
bool getLocationFromGoogleAPI();
String sendATCommand(String cmd, unsigned long timeout);

// ==================== SETUP ====================
void setup() {
  SerialMon.begin(115200);
  delay(300);
  SerialMon.println("\n\n=== SIM7600 Network Location Tracker ===");
  SerialMon.println("Cell Tower + IP Location");

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);

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
  SerialMon.println("\n✅ Setup Complete! Starting location tests...\n");
}

// ==================== MAIN LOOP ====================
void loop() {
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

    // Blink LED to indicate success
    for (int i = 0; i < 3; i++) {
      digitalWrite(LED_PIN, LOW);
      delay(200);
      digitalWrite(LED_PIN, HIGH);
      delay(200);
    }
  } else {
    SerialMon.println("\n❌ All location methods failed!");
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

  String payload = "{";
  payload += "\"latitude\":" + String(lat, 6) + ",";
  payload += "\"longitude\":" + String(lon, 6) + ",";
  payload += "\"locationType\":\"" + locType + "\",";
  payload += "\"accuracy\":" + String(acc, 0) + ",";
  payload += "\"timestamp\":{\".sv\":\"timestamp\"}";
  payload += "}";

  SerialMon.println("\n📤 Sending to Firebase...");

  sendATCommand("AT+HTTPTERM", 500);
  delay(300);
  
  sendATCommand("AT+HTTPINIT", 1000);
  sendATCommand("AT+HTTPPARA=\"CID\",1", 500);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + firebaseURL + "/data_logs.json\"", 1000);
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

  sendATCommand("AT+HTTPACTION=1", 15000);
  sendATCommand("AT+HTTPTERM", 500);
  SerialMon.println("✅ Firebase complete\n");
}