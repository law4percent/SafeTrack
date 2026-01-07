#ifndef SIM7600_H
#define SIM7600_H

#include <Arduino.h>

extern HardwareSerial SerialAT;

bool simInit();
bool simSend(String cmd, int wait = 800);
bool simHttpPost(String url, String json, String contentType = "application/json");

#endif
