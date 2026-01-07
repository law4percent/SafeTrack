#include "sim7600.h"

HardwareSerial SerialAT(1); // UART1

// Send AT command and detect success
bool simSend(String cmd, int wait) {
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

  if (response.indexOf("OK") != -1) return true;
  if (response.indexOf("ERROR") != -1) return false;
  if (response.indexOf("+CME ERROR") != -1) return false;

  return false;
}

// Initialize SIM7600
bool simInit() {
  Serial.println("Initializing SIM7600...");

  if (!simSend("AT")) return false;
  if (!simSend("AT+CFUN=1")) return false;
  if (!simSend("AT+CPIN?")) return false;
  if (!simSend("AT+CSQ")) return false;
  if (!simSend("AT+CREG?")) return false;
  if (!simSend("AT+CGATT=1")) return false;

  String APN = "internet";   // <-- change to your APN
  if (!simSend("AT+CGDCONT=1,\"IP\",\"" + APN + "\"")) return false;
  if (!simSend("AT+CGACT=1,1")) return false;

  if (!simSend("AT+NETOPEN", 2000)) return false;

  Serial.println("SIM7600 Successfully Initialized!");
  return true;
}

// HTTP POST
bool simHttpPost(String url, String json, String contentType) {
  
  simSend("AT+HTTPTERM"); // cleanup
  simSend("AT+HTTPINIT");

  simSend("AT+HTTPPARA=\"CID\",1");  
  simSend("AT+HTTPPARA=\"URL\",\"" + url + "\"");
  simSend("AT+HTTPPARA=\"CONTENT\",\"" + contentType + "\"");

  simSend("AT+HTTPDATA=" + String(json.length()) + ",5000");
  delay(200);
  SerialAT.print(json);

  if (!simSend("AT+HTTPACTION=1", 6000)) return false;

  Serial.println("HTTP POST sent.");
  return true;
}
