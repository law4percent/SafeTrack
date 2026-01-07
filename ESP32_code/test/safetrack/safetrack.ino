#include <Arduino.h>
#include <HardwareSerial.h>
#include "led.h"
#include "sim7600.h"
#include "firebase.h"





HardwareSerial sim7600(2);
#define SIM_TX 17
#define SIM_RX 16

// ---- EDIT ----
String PROJECT_ID = "your-project-id";
String DEVICE_ID = "DEVICEID12345";
String APN = "internet";
// --------------

// This will be dynamically updated after checking actionOwnerID
String OWNER_UID = "";

bool simSend(String cmd, int wait = 500) {
  SerialAT.println(cmd);
  unsigned long start = millis();
  String response = "";

  while (millis() - start < wait) {
    if (SerialAT.available()) {
      response += SerialAT.readString();
    }
  }

  Serial.print("CMD: ");
  Serial.println(cmd);
  Serial.print("RSP: ");
  Serial.println(response);

  // Basic success check
  if (response.indexOf("OK") != -1) return true;
  if (response.indexOf("ERROR") != -1) return false;
  if (response.indexOf("+CME ERROR") != -1) return false;

  return false;  // Default = failed
}

String httpGET(String url) {
  simSend("AT+HTTPTERM", 200);
  simSend("AT+HTTPINIT", 200);
  simSend("AT+HTTPPARA=\"CID\",1");
  simSend("AT+HTTPPARA=\"URL\",\"" + url + "\"");

  simSend("AT+HTTPACTION=0", 5000);  // GET

  sim7600.println("AT+HTTPREAD");
  delay(500);

  String response = "";
  while (sim7600.available()) {
    response += sim7600.readString();
  }
  return response;
}

void postToFirebase(String url, String json) {
  simSend("AT+HTTPTERM", 200);
  simSend("AT+HTTPINIT", 200);

  simSend("AT+HTTPPARA=\"CID\",1");
  simSend("AT+HTTPPARA=\"CONTENT\",\"application/json\"");
  simSend("AT+HTTPPARA=\"URL\",\"" + url + "\"");

  simSend("AT+HTTPDATA=" + String(json.length()) + ",5000");
  delay(150);
  simSend(json, 300);

  simSend("AT+HTTPACTION=1", 7000);
  simSend("AT+HTTPREAD", 500);
}

String getDate() {
  return "11-21-2025";
}
String getTime() {
  return "10:44";
}

bool checkActionOwnerID() {
  String url =
    "https://" + PROJECT_ID + ".firebaseio.com/realDevices/" + DEVICE_ID + "/actionOwnerID.json";

  Serial.println("\n[Checking actionOwnerID]");

  String response = httpGET(url);

  Serial.println("\nRaw Response: " + response);

  // Firebase returns a quoted string: "RNA7..."
  int start = response.indexOf("\"");
  int end = response.lastIndexOf("\"");

  if (start == -1 || end == -1) {
    Serial.println("Error parsing UID");
    return false;
  }

  OWNER_UID = response.substring(start + 1, end);

  if (OWNER_UID.length() == 0) {
    Serial.println("No owner assigned. Skipping upload.");
    return false;
  }

  Serial.println("Owner UID found: " + OWNER_UID);
  return true;
}

// ---------------------------------------------------------------

void uploadDeviceLogs(float lat, float lng, float alt, float speed) {
  String date = getDate();
  String time = getTime();

  String url =
    "https://" + PROJECT_ID + ".firebaseio.com/deviceLogs/" + OWNER_UID + "/" + DEVICE_ID + "/" + date + "/" + time + ".json";

  String json =
    "{"
    "\"altitude\":"
    + String(alt) + ","
                    "\"latitude\":"
    + String(lat) + ","
                    "\"longitude\":"
    + String(lng) + ","
                    "\"speed\":"
    + String(speed) + "}";

  postToFirebase(url, json);
}

void uploadDeviceStatus(float lat, float lng, float alt, int battery, bool sos) {
  String url =
    "https://" + PROJECT_ID + ".firebaseio.com/linkedDevices/" + OWNER_UID + "/devices/" + DEVICE_ID + "/deviceStatus.json";

  String json =
    "{"
    "\"batteryLevel\":"
    + String(battery) + ","
                        "\"lastLocation\":{"
                        "\"altitude\":"
    + String(alt) + ","
                    "\"latitude\":"
    + String(lat) + ","
                    "\"longitude\":"
    + String(lng) + "},"
                    "\"lastUpdate\":\""
    + getDate() + " " + getTime() + "\","
                                    "\"sos\":"
    + String(sos ? "true" : "false") + "}";

  postToFirebase(url, json);
}

// ----------------------------------------------------------------

unsigned long lastSend = 0;

void setup() {
  Serial.begin(115200);
  
  initLED();
  ledWorking();

  sim7600.begin(115200, SERIAL_8N1, SIM_RX, SIM_TX);
  SerialAT.begin(115200, SERIAL_8N1, 16, 17);  
  delay(1000);

  if (!simInit()) {
    Serial.println("SIM7600 Init Failed!");
    while (1);
  }

  if (!max17043Begin()) {
    Serial.println("Battery gauge failed to init — continuing without battery data");
    // maybe set LED error or fallback
  }
}

void loop() {
  if (millis() - lastSend >= 120000) {
      lastSend = millis();
      
      ledWorking();   // blink to show sending

      String json = "{\"temperature\": 25.1, \"status\": \"OK\"}";

      if (firebaseSend("/device_logs/DEVICE123", json)) {
          ledSuccess();   // GREEN
      } else {
          ledError();     // RED
      }

      uploadDeviceLogs()
  }
}
/*
    const int BATTERY_LOW_THRESHOLD = 15; // percent

    if (batteryPercent > 0 && batteryPercent <= BATTERY_LOW_THRESHOLD) {
      // e.g., set RED LED, send special alert, or reduce frequency
      ledError();
      // optionally send a dedicated low-battery node:
      String lowJson = "{\"lowBattery\":true,\"batteryLevel\":"+String(batteryPercent)+"}";
      firebaseSend("/alerts/" + DEVICE_ID, lowJson);
    }


  void loop() {
    if (millis() - lastSend >= 120000) {
      lastSend = millis();

      // read battery
      float soc = max17043GetSOC();       // percent, -1 on error
      float volt = max17043GetVoltage();  // volts, -1 on error
      int batteryPercent = (soc < 0) ? 0 : round(soc);

      // sample other sensors / GPS
      float lat = 1.25;
      float lng = 2.623;
      float alt = 234.23;
      float speed = 2.0;
      bool sos = false;

      // Build JSON for deviceStatus including batteryLevel
      String statusJson = "{";
      statusJson += "\"batteryLevel\":" + String(batteryPercent) + ",";
      statusJson += "\"lastLocation\":{";
      statusJson += "\"altitude\":" + String(alt) + ",";
      statusJson += "\"latitude\":" + String(lat) + ",";
      statusJson += "\"longitude\":" + String(lng);
      statusJson += "},";
      statusJson += "\"lastUpdate\":\"" + getDate() + " " + getTime() + "\",";
      statusJson += "\"sos\":" + String(sos ? "true" : "false");
      statusJson += "}";

      // send logs & status (only if owner UID present etc)
      if (checkActionOwnerID()) {
        uploadDeviceLogs(lat, lng, alt, speed);
        uploadDeviceStatus(lat, lng, alt, batteryPercent, sos);
      }

      // LED feedback
      if (soc >= 0) ledSuccess();
      else ledError();
    }
  }


  void loop() {
    if (millis() - lastSend > 120000) {

      // 1. Check if device has an owner
      if (!checkActionOwnerID()) {
        lastSend = millis();
        return;  // Skip sending
      }

      // 2. Sample data (replace with real GPS)
      float lat = 1.25;
      float lng = 2.623;
      float alt = 234.23;
      float speed = 2.0;
      int battery = 82;
      bool sos = false;

      uploadDeviceLogs(lat, lng, alt, speed);
      uploadDeviceStatus(lat, lng, alt, battery, sos);

      lastSend = millis();
    }
  }
*/