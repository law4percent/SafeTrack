#include <time.h>

// Get current time in readable format
String getCurrentTimeString() {
  time_t now;
  struct tm timeinfo;
  time(&now);
  localtime_r(&now, &timeinfo);
  
  char buffer[20];
  strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &timeinfo);
  return String(buffer);
}

// Update in Firebase
void updateLastUpdate() {
  String timestamp = getCurrentTimeString();
  String path = "linkedDevices/" + String(DEVICE_ID) + "/deviceStatus/lastUpdate";
  Firebase.setString(firebaseData, path, timestamp);
}