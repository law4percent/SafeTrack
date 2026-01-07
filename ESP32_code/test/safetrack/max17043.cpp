#include "max17043.h"
#include <Wire.h>
#include <Adafruit_MAX1704x.h>

static Adafruit_MAX1704x lipo = Adafruit_MAX1704x();

bool max17043Begin() {
  Wire.begin(21, 22); // SDA, SCL on ESP32 (change pins if needed)
  if (!lipo.begin()) {
    Serial.println("MAX1704x not found");
    return false;
  }
  // Optional: quick wake/reset/config if needed
  Serial.println("MAX1704x initialized");
  return true;
}

float max17043GetSOC() {
  // returns percentage 0..100
  float soc = lipo.getPercentage();
  if (isnan(soc)) return -1.0;
  return soc;
}

float max17043GetVoltage() {
  // returns battery voltage in volts
  float mV = lipo.getVoltage(); // library returns mV or V depending on impl; check: this returns volts for Adafruit lib
  // If library returns mV, divide by 1000.0. We'll assume volts; guard just in case:
  if (mV > 100.0) {
    // probably mV, convert
    return mV / 1000.0;
  }
  return mV;
}
