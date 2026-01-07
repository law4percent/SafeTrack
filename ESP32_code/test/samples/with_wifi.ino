#include <WiFi.h>
#include <HTTPClient.h>
#include "Adafruit_FONA.h"

// ------ SIM7600 SERIAL ------
HardwareSerial SerialAT(1);    // UART1 for SIM7600
HardwareSerial* fonaSerial = &SerialAT;

const int FONA_RST = 4;        // Your reset pin
Adafruit_FONA_3G fona = Adafruit_FONA_3G(FONA_RST);

// ------ WIFI ------
const char* WIFI_SSID     = "YOUR_WIFI";
const char* WIFI_PASSWORD = "YOUR_PASSWORD";

// ------ FIREBASE ------
String firebaseURL = "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app";

// -----------------------------------------------
// SETUP
// -----------------------------------------------
void setup() {
  Serial.begin(115200);
  Serial.println("Booting...");

  // --- CONNECT TO WIFI ---
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("WiFi Connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); Serial.print(".");
  }
  Serial.println("\nWiFi Connected!");

  // --- INIT SIM7600 ---
  fonaSerial->begin(115200, SERIAL_8N1, 16, 17, false);

  if (!fona.begin(*fonaSerial)) {
    Serial.println("SIM7600 NOT detected. Stopping.");
    while (1);
  }
  Serial.println("SIM7600 Ready.");

  // Turn ON GPS
  Serial.println("Turning ON GPS...");
  fonaSerial->println("AT+CGNSPWR=1");
  delay(1000);
}

// -----------------------------------------------
// MAIN LOOP
// -----------------------------------------------
void loop() {
  getAndSendGPS();
  delay(5000); // Log every 5 seconds
}

// -----------------------------------------------
// READ GPS + SEND TO FIREBASE
// -----------------------------------------------
void getAndSendGPS() {
  // Request GNSS data
  fonaSerial->println("AT+CGNSINF");
  delay(300);

  String gnsData = "";
  while (fonaSerial->available()) {
    gnsData += char(fonaSerial->read());
  }

  if (!gnsData.startsWith("+CGNSINF")) {
    Serial.println("GPS not ready...");
    return;
  }

  Serial.println("RAW GNSS:");
  Serial.println(gnsData);

  // Parse GNSS fields
  float lat = getField(gnsData, 3).toFloat();
  float lon = getField(gnsData, 4).toFloat();
  float alt = getField(gnsData, 5).toFloat();
  float spd = getField(gnsData, 6).toFloat();

  Serial.println("Parsed GPS:");
  Serial.printf("Latitude: %.6f\n", lat);
  Serial.printf("Longitude: %.6f\n", lon);
  Serial.printf("Altitude: %.2f\n", alt);
  Serial.printf("Speed: %.2f\n", spd);

  sendToFirebase(lat, lon, alt, spd);
}

// -----------------------------------------------
// GET FIELD FROM CGNSINF STRING
// Example: getField(data, 3) → latitude
// -----------------------------------------------
String getField(String data, int index) {
  int count = 0;
  int start = 0;

  for (int i = 0; i < data.length(); i++) {
    if (data[i] == ',') {
      count++;
      if (count == index) start = i + 1;
      else if (count == index + 1) return data.substring(start, i);
    }
  }
  return "";
}

// -----------------------------------------------
// SEND GPS DATA TO FIREBASE WITH SERVER TIMESTAMP
// -----------------------------------------------
void sendToFirebase(float lat, float lon, float alt, float speed) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost, cannot send.");
    return;
  }

  // Firebase push path
  String url = firebaseURL + "/data_logs.json";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  // Payload with Firebase server timestamp
  String payload = "{";
  payload += "\"latitude\":" + String(lat, 6) + ",";
  payload += "\"longitude\":" + String(lon, 6) + ",";
  payload += "\"altitude\":" + String(alt, 2) + ",";
  payload += "\"speed\":" + String(speed, 2) + ",";
  payload += "\"timestamp\": {\".sv\": \"timestamp\"}";
  payload += "}";

  int httpCode = http.POST(payload);

  Serial.print("Firebase Response: ");
  Serial.println(httpCode);

  http.end();
}
