/*
Path: ESP32_code/test/gps_satellite_test/gps_satellite_test.ino
Description: Test code to get GPS location from SIM7600 using satellite data.
*/

#define TINY_GSM_MODEM_SIM7600

#include <TinyGsmClient.h>
#include <HardwareSerial.h>

// ==================== PIN DEFINITIONS ====================
#define rxPin 16   // SIM7600 RX → ESP32 pin 4
#define txPin 17   // SIM7600 TX → ESP32 pin 2
#define RED_PIN     27  // Red LED for error/unauthorized
#define GRN_PIN     26  // Green LED for success

HardwareSerial SerialAT(1);
#define SerialMon Serial

// ==================== GPRS CONFIGURATION ====================
const char apn[]  = "http.globe.com.ph"; // Your APN
const char gprsUser[] = "";
const char gprsPass[] = "";

// ==================== GLOBAL VARIABLES ====================
float latitude = 0;
float longitude = 0;
float altitude = 0;
float speed_kph = 0;
int heading = 0;

// ==================== MODEM ====================
TinyGsm modem(SerialAT);

void setup() {
  SerialMon.begin(115200);
  delay(10);

  pinMode(RED_PIN, OUTPUT);
  digitalWrite(RED_PIN, LOW);
  pinMode(GRN_PIN, OUTPUT);
  digitalWrite(GRN_PIN, LOW);

  SerialAT.begin(115200, SERIAL_8N1, rxPin, txPin);

  SerialMon.println("\nInitializing modem...");
  if (!modem.restart()) {
    SerialMon.println("⚠️ Modem restart failed, continuing...");
  }

  SerialMon.println("Waiting for network...");
  if (!modem.waitForNetwork()) {
    SerialMon.println("Network not found, check SIM and coverage!");
    while (true) delay(1000);
  }
  SerialMon.println("Network connected.");

#if TINY_GSM_USE_GPRS
  if (!modem.gprsConnect(apn, gprsUser, gprsPass)) {
    SerialMon.println("GPRS connection failed!");
  } else {
    SerialMon.println("GPRS connected.");
  }
#endif
}

void loop() {
  SerialMon.println("\nRequesting GPS location...");

  modem.enableGPS();
  if (modem.getGPS(&latitude, &longitude, &altitude, &speed_kph, &heading)) {
    SerialMon.println("✅ GPS Data Acquired:");
    SerialMon.print("Latitude: "); SerialMon.println(latitude, 8);
    SerialMon.print("Longitude: "); SerialMon.println(longitude, 8);
    SerialMon.print("Altitude: "); SerialMon.println(altitude, 2);
    SerialMon.print("Speed (kph): "); SerialMon.println(speed_kph, 2);
    SerialMon.print("Heading: "); SerialMon.println(heading, 2);
    digitalWrite(GRN_PIN, HIGH);
    digitalWrite(RED_PIN, LOW);
  } else {
    SerialMon.println("⚠️ GPS data not available, retrying...");
    digitalWrite(GRN_PIN, LOW);
    digitalWrite(RED_PIN, HIGH);
  }

  // Blink LED to indicate GPS read attempt
  delay(5000); // Wait 5 seconds before next read
}
