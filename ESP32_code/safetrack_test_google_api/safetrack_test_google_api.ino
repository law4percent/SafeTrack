// ==================== MODEM CONFIGURATION ====================
#define TINY_GSM_MODEM_SIM7600
#define TINY_GSM_RX_BUFFER 1024

#include <TinyGsmClient.h>
#include <HardwareSerial.h>

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
const char googleApiKey[] = "YOUR_GOOGLE_API_KEY"; // Get free key from https://console.cloud.google.com

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
bool getLocationFromLBS();
String sendATCommand(String cmd, unsigned long timeout);

// ==================== SETUP ====================
void setup() {
  SerialMon.begin(115200);
  delay(300);
  SerialMon.println("\n\n=== SIM7600 Network Location Tracker ===");
  SerialMon.println("Testing IP-based Location");

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

  // Try IP-based Location
  SerialMon.println("📍 Getting IP-based Location");
  SerialMon.println("-----------------------------------");
  
  if (getLocationFromIP()) {
    SerialMon.println("\n✅ Location acquired successfully!");
    SerialMon.println("\n📊 Location Summary:");
    SerialMon.printf("  Type: %s\n", locationType.c_str());
    SerialMon.printf("  Latitude: %.6f\n", latitude);
    SerialMon.printf("  Longitude: %.6f\n", longitude);
    SerialMon.printf("  Accuracy: ~%.0f meters\n", accuracy);

    sendToFirebase(latitude, longitude, locationType, accuracy);

    // Blink LED to indicate success
    for (int i = 0; i < 3; i++) {
      digitalWrite(LED_PIN, LOW);
      delay(200);
      digitalWrite(LED_PIN, HIGH);
      delay(200);
    }
  } else {
    SerialMon.println("\n❌ Location acquisition failed!");
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

// ==================== LOCATION FUNCTION ====================

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
  SerialMon.println("✓ HTTP initialized");
  
  SerialMon.println("Step 3: Setting CID...");
  sendATCommand("AT+HTTPPARA=\"CID\",1", 1000);
  
  SerialMon.println("Step 4: Setting URL...");
  sendATCommand("AT+HTTPPARA=\"URL\",\"http://ip-api.com/json/?fields=status,lat,lon,city,regionName,country,query\"", 2000);
  
  SerialMon.println("Step 5: Executing HTTP GET request...");
  // Send action command (expects immediate OK)
  SerialAT.println("AT+HTTPACTION=0");
  
  // Wait for the immediate "OK" and discard it
  String init_resp = "";
  unsigned long init_timeout = millis() + 2000;
  while (millis() < init_timeout) {
    if (SerialAT.available()) {
      init_resp += (char)SerialAT.read();
    }
    if (init_resp.indexOf("OK") != -1) {
      SerialMon.println("✓ Command accepted: " + init_resp);
      break;
    }
  }

  SerialMon.println("Step 6: Waiting for HTTP 200 result...");
  
  // Wait for the asynchronous result: +HTTPACTION: 0,200
  String action_result = "";
  unsigned long action_timeout = millis() + 20000; // 20 seconds for the request
  bool action_success = false;
  
  while (millis() < action_timeout) {
    while (SerialAT.available()) {
      String line = SerialAT.readStringUntil('\n');
      line.trim();
      SerialMon.println(">> " + line); // Print all URCs for debugging
      
      // Check for the successful response code
      if (line.indexOf("+HTTPACTION: 0,200") != -1) {
        action_success = true;
        action_result = line;
        break;
      }
      
      // Check for other HTTP status codes
      if (line.indexOf("+HTTPACTION: 0,") != -1) {
        action_result = line;
        SerialMon.println("⚠️ HTTP request completed with non-200 status");
        break;
      }
    }
    if (action_success || action_result.length() > 0) {
      break;
    }
    delay(10); // Don't hog the CPU
  }
  
  if (!action_success) {
    SerialMon.println("✗ HTTP GET failed or timed out (No +HTTPACTION: 0,200)");
    if (action_result.length() > 0) {
      SerialMon.println("Received: " + action_result);
    }
    sendATCommand("AT+HTTPTERM", 1000);
    return false;
  }
  SerialMon.println("✓ HTTP 200 OK received: " + action_result);
  
  // FIX 1: Add delay to let modem transition state
  SerialMon.println("Waiting for modem to be ready...");
  delay(1000); // Give the modem time to fully transition state
  
  SerialMon.println("Step 7: Reading HTTP response...");
  
  // 1. Clear ALL PENDING DATA (Crucial to clear any trailing newlines/OKs from Step 6)
  SerialMon.println("Clearing serial buffer...");
  while (SerialAT.available()) {
    SerialAT.read();
  }
  delay(100);
  
  // 2. Send AT+HTTPREAD command (with explicit byte range for reliability)
  SerialMon.println("Sending AT+HTTPREAD=0,1024...");
  SerialAT.println("AT+HTTPREAD=0,1024");
  
  // 3. Clear the Command Echo from the Modem
  SerialMon.println("Waiting for command echo and response...");
  String echo_resp = "";
  unsigned long echo_timeout = millis() + 1000;
  
  while (millis() < echo_timeout) {
    while (SerialAT.available()) {
      char c = SerialAT.read();
      echo_resp += c;
      SerialMon.print(c);
    }
    
    // Check for OK or ERROR
    if (echo_resp.indexOf("OK") != -1 || echo_resp.indexOf("ERROR") != -1) {
      SerialMon.println("\n✓ Initial response received.");
      break;
    }
  }
  
  // 4. Read the Complete Response (Data + OK/ERROR)
  String httpReadResp = "";
  unsigned long timeout = millis() + 10000;
  bool foundTerminal = false;
  
  SerialMon.println("Reading HTTP data...");
  while (millis() < timeout) {
    while (SerialAT.available()) {
      char c = SerialAT.read();
      httpReadResp += c;
      SerialMon.print(c);
    }
    
    // Look for the +HTTPREAD: 0 which indicates end of data
    if (httpReadResp.indexOf("+HTTPREAD: 0") != -1) {
      foundTerminal = true;
      SerialMon.println("\n✓ End of data marker received.");
      break;
    }
    
    delay(10);
  }
  
  SerialMon.println("\n--- End of HTTP Response ---");
  SerialMon.println("Raw response length: " + String(httpReadResp.length()));
  
  if (!foundTerminal && httpReadResp.length() < 20) {
    SerialMon.println("⚠️ Response may be incomplete");
  }
  
  // Extract the raw JSON data
  // The data is usually between +HTTPREAD: <length> and the final OK
  int dataStart = httpReadResp.indexOf("{");
  int dataEnd = httpReadResp.lastIndexOf("}");
  String httpData = "";
  
  if (dataStart != -1 && dataEnd != -1 && dataEnd > dataStart) {
    // Extract the JSON object including the closing brace
    httpData = httpReadResp.substring(dataStart, dataEnd + 1);
    SerialMon.println("✓ Found JSON data successfully");
  } else {
    SerialMon.println("✗ Could not find JSON data in response");
    SerialMon.println("Looking for '{' and '}'...");
    SerialMon.println("dataStart: " + String(dataStart) + ", dataEnd: " + String(dataEnd));
  }
  
  SerialMon.println("\nStep 8: Terminating HTTP session...");
  sendATCommand("AT+HTTPTERM", 1000);
  
  if (httpData.length() < 10) {
    SerialMon.println("✗ No valid data received (data too short)");
    return false;
  }
  
  SerialMon.println("\n📄 Extracted JSON Data:");
  SerialMon.println(httpData);
  SerialMon.println();
  
  // Parse JSON manually
  SerialMon.println("Step 9: Parsing location data...");
  
  // Check status
  int statusIdx = httpData.indexOf("\"status\":\"");
  if (statusIdx != -1) {
    int statusStart = statusIdx + 10;
    int statusEnd = httpData.indexOf("\"", statusStart);
    String status = httpData.substring(statusStart, statusEnd);
    
    if (status != "success") {
      SerialMon.println("✗ API status: " + status);
      return false;
    }
    SerialMon.println("✓ API status: success");
  }
  
  // Extract latitude
  int latIdx = httpData.indexOf("\"lat\":");
  if (latIdx == -1) {
    SerialMon.println("✗ Latitude not found");
    return false;
  }
  
  int latStart = latIdx + 6;
  int latEnd = httpData.indexOf(",", latStart);
  if (latEnd == -1) latEnd = httpData.indexOf("}", latStart);
  
  String latStr = httpData.substring(latStart, latEnd);
  latStr.trim();
  latitude = latStr.toFloat();
  SerialMon.println("✓ Latitude: " + String(latitude, 6));
  
  // Extract longitude
  int lonIdx = httpData.indexOf("\"lon\":");
  if (lonIdx == -1) {
    SerialMon.println("✗ Longitude not found");
    return false;
  }
  
  int lonStart = lonIdx + 6;
  int lonEnd = httpData.indexOf(",", lonStart);
  if (lonEnd == -1) lonEnd = httpData.indexOf("}", lonStart);
  
  String lonStr = httpData.substring(lonStart, lonEnd);
  lonStr.trim();
  longitude = lonStr.toFloat();
  SerialMon.println("✓ Longitude: " + String(longitude, 6));
  
  // Extract city
  int cityIdx = httpData.indexOf("\"city\":\"");
  if (cityIdx != -1) {
    int cityStart = cityIdx + 8;
    int cityEnd = httpData.indexOf("\"", cityStart);
    String city = httpData.substring(cityStart, cityEnd);
    SerialMon.println("✓ City: " + city);
  }
  
  // Extract country
  int countryIdx = httpData.indexOf("\"country\":\"");
  if (countryIdx != -1) {
    int countryStart = countryIdx + 11;
    int countryEnd = httpData.indexOf("\"", countryStart);
    String country = httpData.substring(countryStart, countryEnd);
    SerialMon.println("✓ Country: " + country);
  }
  
  // Validate coordinates
  if (latitude == 0.0 && longitude == 0.0) {
    SerialMon.println("✗ Invalid coordinates (0,0)");
    return false;
  }
  
  locationType = "ip";
  accuracy = 5000.0;  // IP-based location: ~5km accuracy
  
  return true;
}

// ==================== FIREBASE FUNCTION ====================

void sendToFirebase(float lat, float lon, String locType, float acc) {
  if (!modem.isGprsConnected()) {
    SerialMon.println("❌ Cannot send to Firebase: GPRS not connected");
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
  SerialMon.println("Payload: " + payload);

  sendATCommand("AT+HTTPTERM", 500);
  delay(300);
  
  sendATCommand("AT+HTTPINIT", 1000);
  sendATCommand("AT+HTTPPARA=\"CID\",1", 500);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + firebaseURL + "/data_logs.json\"", 1000);
  sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 500);

  SerialMon.println("Writing payload...");
  SerialAT.println("AT+HTTPDATA=" + String(payload.length()) + ",10000");
  
  delay(500);
  String resp = "";
  unsigned long start = millis();
  while (millis() - start < 2000) {
    if (SerialAT.available()) {
      resp += (char)SerialAT.read();
    }
    if (resp.indexOf("DOWNLOAD") != -1) break;
  }
  
  if (resp.indexOf("DOWNLOAD") != -1) {
    SerialMon.println("✓ Ready to write payload");
    SerialAT.print(payload);
    delay(1000);
    SerialMon.println("✓ Payload written");
  } else {
    SerialMon.println("✗ HTTPDATA setup failed");
    sendATCommand("AT+HTTPTERM", 500);
    return;
  }

  SerialMon.println("Executing POST...");
  resp = sendATCommand("AT+HTTPACTION=1", 15000);
  
  if (resp.indexOf("+HTTPACTION: 1,200") != -1) {
    SerialMon.println("✅ Firebase POST successful!");
  } else if (resp.indexOf("+HTTPACTION: 1,") != -1) {
    int codeStart = resp.indexOf("+HTTPACTION: 1,") + 15;
    int codeEnd = resp.indexOf(",", codeStart);
    String statusCode = resp.substring(codeStart, codeEnd);
    SerialMon.println("⚠️ Firebase POST status: " + statusCode);
  } else {
    SerialMon.println("⚠️ Firebase POST timeout");
  }

  sendATCommand("AT+HTTPTERM", 500);
  SerialMon.println("📊 Firebase transmission complete\n");
}