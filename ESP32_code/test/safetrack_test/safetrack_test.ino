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

// ==================== NETWORK CREDENTIALS ====================
const char apn[] = "internet";  // Update with your carrier's APN
const char user[] = "";
const char pass[] = "";

// ==================== GLOBAL OBJECTS ====================
TinyGsm modem(SerialAT);

// ==================== GPS DATA VARIABLES ====================
float latitude = 0.0;
float longitude = 0.0;
float altitude = 0.0;
float speed = 0.0;
int vsat = 0, usat = 0;
float accuracy = 0.0;
int year = 0, month = 0, day = 0;
int hour = 0, minute = 0, second = 0;

// ==================== FUNCTION PROTOTYPES ====================
bool checkNetworkConnection();
void connectNetwork();
void sendToFirebase(float lat, float lon, float alt, float spd);

// ==================== SETUP ====================
void setup() {
  SerialMon.begin(115200);
  delay(300);
  SerialMon.println("=== SIM7600 GPS Tracker Booting ===");

  // Initialize LED
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);

  // Power on SIM7600 module
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH);
  delay(300);
  digitalWrite(PWR_PIN, LOW);
  delay(1000);

  // Initialize modem serial communication
  SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX);

  // Initialize modem
  SerialMon.println("Initializing modem...");
  if (!modem.restart()) {
    SerialMon.println("⚠️  Failed to restart modem, continuing...");
  }

  // Display modem information
  String modemName = modem.getModemName();
  delay(500);
  SerialMon.println("Modem Name: " + modemName);

  String modemInfo = modem.getModemInfo();
  delay(500);
  SerialMon.println("Modem Info: " + modemInfo);

  // Enable GPS
  modem.sendAT("+CGNSPWR=1");
  modem.waitResponse(1000);
  modem.sendAT("+CGNSINF");
  modem.waitResponse(1000);
  modem.enableGPS();
  delay(5000);  // Wait 5 seconds for GPS to start
  SerialMon.println("📡 GPS enabled. Waiting for fix...");
}

// ==================== MAIN LOOP ====================
void loop() {
  // Attempt to get GPS fix
  if (modem.getGPS(&latitude, &longitude, &speed, &altitude,
                   &vsat, &usat, &accuracy,
                   &year, &month, &day, &hour, &minute, &second)) {

    SerialMon.println("✅ GPS Fix Acquired!");
    SerialMon.printf("Lat: %.6f | Lon: %.6f | Alt: %.2fm | Speed: %.2fkm/h\n",
                     latitude, longitude, altitude, speed);
    SerialMon.printf("Satellites: %d visible, %d used | Accuracy: %.2fm\n",
                     vsat, usat, accuracy);

    // Check network connection before sending data
    if (checkNetworkConnection()) {
      sendToFirebase(latitude, longitude, altitude, speed);

      // Blink LED to indicate successful transmission
      digitalWrite(LED_PIN, LOW);
      delay(200);
      digitalWrite(LED_PIN, HIGH);
    } else {
      SerialMon.println("🔴 No network connection. Attempting to reconnect...");
      connectNetwork();
    }

  } else {
    SerialMon.println("🟡 GPS not fixed yet, retrying...");
  }

  delay(10000);  // Wait 10 seconds before next update
}

// ==================== NETWORK FUNCTIONS ====================

bool checkNetworkConnection() {
  int state = modem.getRegistrationStatus();
  // 1 = Registered (Home), 5 = Registered (Roaming)
  if (state == 1 || state == 5) {
    SerialMon.println("📶 Network registered");
    return true;
  } else {
    SerialMon.printf("🚫 Network not registered (Status: %d)\n", state);
    return false;
  }
}

void connectNetwork() {
  SerialMon.print("Connecting to APN: ");
  SerialMon.println(apn);

  // Disconnect existing GPRS connection if any
  if (modem.isGprsConnected()) {
    modem.gprsDisconnect();
    delay(1000);
  }

  // Establish GPRS connection
  if (!modem.gprsConnect(apn, user, pass)) {
    SerialMon.println("❌ Failed to connect GPRS!");
  } else {
    SerialMon.println("✅ GPRS connected!");
  }
}

// ==================== FIREBASE FUNCTION ====================

void sendToFirebase(float lat, float lon, float alt, float spd) {
  // Verify GPRS connection
  if (!modem.isGprsConnected()) {
    SerialMon.println("❌ Cannot send to Firebase: GPRS not connected");
    return;
  }

  // Construct JSON payload
  String payload = "{";
  payload += "\"latitude\":" + String(lat, 6) + ",";
  payload += "\"longitude\":" + String(lon, 6) + ",";
  payload += "\"altitude\":" + String(alt, 2) + ",";
  payload += "\"speed\":" + String(spd, 2) + ",";
  payload += "\"timestamp\":{\".sv\":\"timestamp\"}";
  payload += "}";

  SerialMon.println("📤 Sending to Firebase...");

  // Initialize HTTP session
  modem.sendAT("+HTTPTERM");
  modem.waitResponse(500);
  modem.sendAT("+HTTPINIT");
  modem.waitResponse(500);
  modem.sendAT("+HTTPPARA=\"CID\",1");
  modem.waitResponse(500);
  modem.sendAT("+HTTPPARA=\"URL\",\"" + firebaseURL + "/data_logs.json\"");
  modem.waitResponse(500);
  modem.sendAT("+HTTPPARA=\"CONTENT\",\"application/json\"");
  modem.waitResponse(500);

  // Write HTTP data
  modem.sendAT("+HTTPDATA=" + String(payload.length()) + ",10000");
  if (modem.waitResponse("+HTTPACTION: ") == 1) {
    modem.stream.write(payload.c_str());
    modem.stream.flush();
    SerialMon.println("✍️  Payload written, executing POST...");
  } else {
    SerialMon.println("❌ Error setting up HTTPDATA");
    modem.sendAT("+HTTPTERM");
    modem.waitResponse(500);
    return;
  }

  // Execute HTTP POST
  modem.sendAT("+HTTPACTION=1");

  String httpResponse;
  modem.waitResponse(10000, httpResponse);

  // Parse response
  int actionIndex = httpResponse.indexOf("+HTTPACTION: 1,");
  if (actionIndex != -1) {
    int codeStart = actionIndex + String("+HTTPACTION: 1,").length();
    String statusCodeStr = httpResponse.substring(codeStart, httpResponse.indexOf(",", codeStart));
    SerialMon.println("✅ HTTP POST Complete! Status: " + statusCodeStr);
  } else {
    SerialMon.println("⚠️  HTTP POST timeout or error");
    SerialMon.println("Raw response: " + httpResponse);
  }

  // Terminate HTTP session
  modem.sendAT("+HTTPTERM");
  modem.waitResponse(500);

  SerialMon.println("📊 Data transmission complete\n");
}