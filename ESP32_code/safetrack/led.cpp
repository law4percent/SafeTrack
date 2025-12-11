#include "led.h"

#define LED_GREEN 26
#define LED_RED   27

void initLED() {
  pinMode(LED_GREEN, OUTPUT);
  pinMode(LED_RED, OUTPUT);
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(LED_RED, LOW);
}

// All OFF
void ledOff() {
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(LED_RED, LOW);
}

// Successful connection or data sent
void ledSuccess() {
  digitalWrite(LED_GREEN, HIGH);
  digitalWrite(LED_RED, LOW);
}

// Error state (SIM7600 or Firebase)
void ledError() {
  digitalWrite(LED_RED, HIGH);
  digitalWrite(LED_GREEN, LOW);
}

// Working / Processing
void ledWorking() {
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(LED_RED, LOW);
  delay(200);
  digitalWrite(LED_GREEN, HIGH);
  delay(200);
}
