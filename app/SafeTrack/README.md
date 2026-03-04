# SafeTrack — Child Safety Monitoring App

SafeTrack is a real-time child safety monitoring system designed for parents of elementary school students. It combines a custom-built IoT tracker device worn or carried by the child with a Flutter-based parent mobile application. The system allows parents to monitor their child's live GPS location, register safe travel routes, receive deviation alerts, and communicate with an AI assistant for contextual safety insights — all in real time.

The project addresses the growing concern of child safety during school commutes and on school premises, where parents have limited visibility into their child's whereabouts.

---

## Features

### Real-Time Location Tracking
- Live GPS coordinates streamed from the child's IoT device via Firebase Realtime Database
- Location updates displayed on an OpenStreetMap-based interactive map
- Online/offline status detection based on last known update timestamp
- Support for GPS, network, and IP-based location types

### Route Registration & Geofencing
- Parents can define named safe travel routes (e.g., Home → School) by tapping waypoints on a map
- Configurable deviation threshold per route (20m – 200m)
- Multiple routes per device supported
- Routes can be toggled active/paused without deletion

### Deviation Detection & Alerts
- Haversine-based algorithm calculates the child's perpendicular distance to the nearest route segment
- If the child deviates beyond the registered threshold, a push notification is sent immediately
- 5-minute alert cooldown per device to prevent notification spam
- Background monitoring via Workmanager ensures alerts fire even when the app is closed

### SOS Emergency Button
- Physical push button on the IoT device sends an instant SOS signal
- Parent app receives a high-priority full-screen notification
- SOS events are logged with timestamp to Firebase

### AI Assistant (Gemini-powered)
- Context-aware chatbot powered by Google Gemini API
- Pulls real-time device data from Firebase (battery, location, SOS status, activity logs)
- Categorized question handling: location, safety, device status, reassurance, and child status
- Clarifies broad questions by asking for time range before querying data
- Hardcoded RAG knowledge base covering system architecture, tech stack, and algorithms

### Battery & Device Monitoring
- Real-time battery percentage via MAX17043 fuel gauge IC
- Low battery warnings surfaced in the parent app and AI assistant
- Device online/offline status tracked per linked child

---

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│                   PARENT APP (Flutter)               │
│  Dashboard │ Live Map │ Routes │ AI Chat │ Children  │
└─────────────────┬───────────────────────────────────┘
                  │ Firebase Realtime Database (RTDB)
                  │ (read/write, real-time streams)
┌─────────────────┴───────────────────────────────────┐
│              FIREBASE BACKEND                        │
│  linkedDevices │ deviceLogs │ devicePaths │ status   │
└─────────────────┬───────────────────────────────────┘
                  │ HTTPS POST (JSON payload)
┌─────────────────┴───────────────────────────────────┐
│           IoT TRACKER DEVICE (ESP32-C3)              │
│  SIM7600E-H1C GPS + 4G LTE │ SOS Button             │
│  MAX17043 Battery Gauge │ TP4056 Charger             │
│  LiFePO4 3.7V 2000mAh │ MT3608 Boost Converter      │
└─────────────────────────────────────────────────────┘
```

---

## Tech Stack

### Parent Application
| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| State Management | Provider |
| Mapping | flutter_map + OpenStreetMap tiles |
| Backend | Firebase Realtime Database |
| Authentication | Firebase Auth |
| AI Assistant | Google Gemini API |
| Notifications | flutter_local_notifications |
| Background Tasks | Workmanager |
| Distance Algorithm | Haversine Formula |

### IoT Tracker Device
| Component | Role |
|---|---|
| ESP32-C3 Super Mini | Main microcontroller (C/C++ Arduino) |
| SIM7600E-H1C | 4G LTE data transmission + GPS receiver |
| MAX17043 | LiPo battery fuel gauge (I²C) |
| TP4056 | LiPo battery charging module |
| MT3608 | DC-DC boost converter (3.7V → 5V) |
| LiFePO4 3.7V 2000mAh | Primary power source |
| Push Button | SOS trigger |

---

## Firebase Data Structure

```json
{
  "linkedDevices": {
    "{userId}": {
      "devices": {
        "{deviceCode}": {
          "childName": "Diane",
          "deviceEnabled": true
        }
      }
    }
  },
  "deviceLogs": {
    "{userId}": {
      "{deviceCode}": {
        "{pushId}": {
          "latitude": 10.3167,
          "longitude": 123.8907,
          "accuracy": 5.2,
          "speed": 0.0,
          "altitude": 12.3,
          "locationType": "gps",
          "timestamp": 1709123456000
        }
      }
    }
  },
  "deviceStatus": {
    "{deviceCode}": {
      "battery": 87,
      "isSOS": false,
      "lastUpdate": 1709123456000
    }
  },
  "devicePaths": {
    "{userId}": {
      "{deviceCode}": {
        "{routeId}": {
          "pathName": "Home to School",
          "deviationThresholdMeters": 50,
          "isActive": true,
          "waypoints": {
            "wp_0": { "latitude": 10.3167, "longitude": 123.8907, "label": "Home" },
            "wp_1": { "latitude": 10.3210, "longitude": 123.8950, "label": "School" }
          }
        }
      }
    }
  }
}
```

---

## Project Structure

```
lib/
├── main.dart
├── screens/
│   ├── auth/
│   │   └── login_screen.dart
│   ├── dashboard_screen.dart
│   ├── live_location_screen.dart
│   ├── my_children_screen.dart
│   ├── route_registration_screen.dart
│   └── ask_ai_screen.dart
└── services/
    ├── auth_service.dart
    ├── gemini_service.dart
    ├── haversine_service.dart
    ├── path_monitor_service.dart
    ├── notification_service.dart
    └── background_monitor_service.dart
```

---

## Setup & Installation

### Prerequisites
- Flutter SDK ≥ 3.x
- Firebase project with Realtime Database and Authentication enabled
- Google Gemini API key
- Android device or emulator (API 21+)

### Steps

1. Clone the repository and navigate to the app directory.

2. Add the following to `pubspec.yaml` under `dependencies`:
```yaml
firebase_core: ^3.x.x
firebase_auth: ^5.x.x
firebase_database: ^11.x.x
flutter_map: ^7.x.x
latlong2: ^0.9.x
provider: ^6.x.x
flutter_dotenv: ^5.x.x
flutter_local_notifications: ^18.x.x
workmanager: ^0.5.x
```

3. Create a `.env` file in the project root:
```
GEMINI_API_KEY=your_gemini_api_key_here
```

4. Add `.env` to your `pubspec.yaml` assets and to `.gitignore`.

5. Place your `google-services.json` in `android/app/`.

6. Run:
```bash
flutter pub get
flutter run
```

---

## Algorithm: Haversine + Perpendicular Path Distance

The deviation detection uses a two-step approach:

1. **Haversine Formula** — computes the great-circle distance between two GPS coordinates on Earth's surface, accounting for the planet's curvature. Accurate to within a few meters for distances relevant to school routes.

2. **Segment Projection** — for each route segment A→B, the child's position P is projected onto the segment using a parameter `t ∈ [0, 1]`. If `t < 0`, the nearest point is A; if `t > 1`, the nearest point is B; otherwise the nearest point is the projection. The minimum distance across all segments is the child's distance from the route.

This approach is more accurate than point-to-point distance and handles curved paths correctly.

---

## Limitations & Future Work

- The IoT device requires cellular coverage (4G LTE) to transmit data; GPS accuracy may degrade indoors.
- Background monitoring interval is limited to 15 minutes minimum by Android's Workmanager constraints.
- Route deviation detection is one-directional — it does not yet account for expected travel direction.
- Future versions may incorporate machine learning for behavioral pattern analysis.
