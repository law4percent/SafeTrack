#include "firebase.h"
#include "sim7600.h"

String FIREBASE_URL = "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app/";

bool firebaseSend(String path, String json) {
  String url = FIREBASE_URL + path + ".json";

  Serial.println("Sending to Firebase: " + url);
  return simHttpPost(url, json);
}
