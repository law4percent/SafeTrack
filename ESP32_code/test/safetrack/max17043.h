#ifndef MAX17043_H
#define MAX17043_H

#include <Arduino.h>

bool max17043Begin();
float max17043GetSOC();      // % State-of-charge
float max17043GetVoltage();  // battery voltage in volts

#endif
