# SafeTrack: IoT-Based Child Safety Monitoring System with AI-Assisted Parental Guidance

SafeTrack is an integrated child safety monitoring system that combines a custom-built IoT tracker device with a real-time mobile application and an AI-powered assistant. The system is designed to provide parents of elementary school students with continuous visibility into their child's location, safety status, and route compliance — particularly during school commutes and within school premises.

---

## Overview

SafeTrack addresses a critical gap in child safety monitoring: the period between when a child leaves home and when they arrive at school, and vice versa. Using a combination of GPS tracking, 4G LTE connectivity, Firebase cloud infrastructure, Haversine-based geofencing, and Google Gemini AI, SafeTrack delivers real-time alerts, route deviation detection, and intelligent contextual answers to parental safety queries.

---

## Problem Being Solved

The safety of elementary school children during their daily commute and within school campuses remains a persistent concern for parents and guardians. Conventional monitoring methods — such as phone calls or manual check-ins — are unreliable, disruptive, and provide no real-time spatial awareness. Existing commercial GPS trackers often lack intelligent alert systems, require expensive subscription plans, or depend on infrastructure not readily available in developing regions.

SafeTrack proposes a low-cost, locally deployable, and AI-augmented solution tailored to the needs of parents who want affordable and reliable child monitoring.

---

## Project Goals

1. Design and develop a custom IoT tracker device capable of real-time GPS tracking and 4G LTE data transmission.
2. Build a cross-platform mobile application for parents to monitor child location, route compliance, and device status.
3. Implement a Haversine-based route deviation detection algorithm with configurable thresholds.
4. Integrate a context-aware AI assistant to answer parental safety questions using real-time device data.
5. Evaluate system accuracy, response latency, and battery performance under real-world conditions.

---

## System Components

### 1. IoT Tracker Device

The hardware component is a custom-built portable device carried by the child. It is designed to be compact, durable, and power-efficient.

**Hardware Components:**

| Component | Specification | Purpose |
|---|---|---|
| ESP32-C3 Super Mini | RISC-V 160MHz, Wi-Fi + BLE | Main microcontroller |
| SIM7600E-H1C | 4G LTE Cat-4, integrated GPS | Cellular data + GPS receiver |
| MAX17043 | I²C LiPo fuel gauge | Battery percentage monitoring |
| TP4056 | 1A LiPo charging module | Safe battery charging |
| MT3608 | DC-DC boost converter | Regulates 3.7V → 5V for SIM module |
| LiFePO4 Battery | 3.7V, 2000mAh | Primary power source |
| Push Button | Momentary tactile switch | SOS / emergency trigger |

**Firmware:**
- Written in C/C++ using the Arduino framework for ESP32
- Reads GPS NMEA sentences from the SIM7600E-H1C via UART
- Reads battery percentage from MAX17043 via I²C
- Detects SOS button press via GPIO interrupt
- Transmits JSON payload to Firebase Realtime Database via HTTPS POST over 4G LTE

**Sample Payload:**
```json
{
  "latitude": 10.316742,
  "longitude": 123.890561,
  "accuracy": 4.8,
  "speed": 0.0,
  "altitude": 11.2,
  "locationType": "gps",
  "battery": 84,
  "isSOS": false,
  "timestamp": 1709123456000
}
```

---

### 2. Firebase Backend

Firebase Realtime Database serves as the cloud backbone of the system, providing:

- **Real-time data synchronization** between the IoT device and the parent app
- **Offline persistence** — the app caches the last known state when connectivity is lost
- **Scalable NoSQL structure** organized by user ID and device code
- **Firebase Authentication** for secure parent account management

Key data nodes:
- `linkedDevices/` — stores parent-device relationships and child names
- `deviceLogs/` — time-series GPS log entries pushed by the IoT device
- `deviceStatus/` — current battery, SOS flag, and last update timestamp
- `devicePaths/` — parent-registered safe routes and geofence configurations

---

### 3. Parent Mobile Application

Built with **Flutter (Dart)** for cross-platform compatibility (Android primary target). The app provides:

- **Dashboard** — summary of all linked children, battery status, and SOS alerts
- **Live Location** — real-time map view powered by OpenStreetMap and flutter_map
- **My Children** — device management, linking, and route access
- **Route Registration** — tap-to-drop waypoint map editor with threshold configuration
- **AI Assistant** — Gemini-powered chat interface with Firebase-aware context

**State management:** Provider pattern  
**Background processing:** Workmanager for periodic deviation checks when app is closed  
**Notifications:** flutter_local_notifications for deviation and SOS alerts

---

### 4. Geofencing & Deviation Detection

The system implements a **path-based geofencing** approach rather than traditional circular geofences, which are unsuitable for linear routes such as school commutes.

**Algorithm:**

1. The parent registers a route as an ordered sequence of GPS waypoints.
2. For each GPS update from the child's device, the system calculates the **perpendicular distance** from the child's position to the nearest segment of the registered route.
3. Distance is computed using the **Haversine formula** for accurate great-circle calculations on Earth's curved surface.
4. If the distance exceeds the parent-configured threshold (20m–200m), a deviation alert is triggered.

**Why Haversine over Euclidean distance:**  
Euclidean distance treats GPS coordinates as flat Cartesian coordinates, introducing significant errors over distances greater than a few hundred meters. Haversine correctly accounts for Earth's spherical geometry, providing meter-level accuracy suitable for route monitoring.

---

### 5. AI Assistant

The AI component uses **Google Gemini API** with a retrieval-augmented generation (RAG) approach. The system:

- Fetches real-time device data from Firebase before each query (battery, location, SOS status, recent logs)
- Injects this data as context into the Gemini system prompt
- Applies a hardcoded knowledge base covering the system's architecture, tech stack, and algorithms
- Classifies questions into categories (location, safety, device status, reassurance, child status) and handles broad questions by requesting time-range clarification before generating a response
- Ends every response with a relevant follow-up question to encourage dialogue

---

## System Flow

```
Child carries IoT device
        │
        ▼
SIM7600E-H1C reads GPS + sends HTTPS POST
        │
        ▼
Firebase Realtime Database (deviceLogs, deviceStatus)
        │
        ├──► Parent App (live stream via onValue listener)
        │         │
        │         ├──► Map renders child position
        │         ├──► PathMonitorService checks deviation
        │         │         └──► Notification if threshold exceeded
        │         └──► AI Assistant queries Firebase context
        │
        └──► Workmanager (background, every 15 min)
                  └──► Same deviation check while app closed
```

---

## Development Environment

| Tool | Version / Detail |
|---|---|
| Flutter SDK | ≥ 3.x (Dart ≥ 3.x) |
| Arduino IDE / PlatformIO | ESP32-C3 firmware development |
| Firebase Console | Project configuration |
| Android Studio | IDE for Flutter development |
| Target Platform | Android (API 21+) |
| Database | Firebase Realtime Database |
| AI API | Google Gemini API |

---

## Expected Outcomes

- A functional IoT-to-app pipeline with end-to-end latency under 5 seconds under normal 4G connectivity
- Haversine deviation detection with configurable accuracy suitable for real-world routes
- A parent-facing AI assistant capable of answering contextual safety questions using live data
- A complete system demonstrating integration of embedded systems, mobile development, cloud infrastructure, and artificial intelligence

---

## Repository Structure

```
SafeTrack/
├── app/                        # Flutter parent application
│   └── SafeTrack/
│       ├── lib/
│       │   ├── main.dart
│       │   ├── screens/
│       │   └── services/
│       └── android/
│           └── app/src/main/
│               └── AndroidManifest.xml
├── firmware/                   # ESP32-C3 Arduino firmware
│   └── safetrack_firmware.ino
├── docs/
│   ├── README_APP.md
│   ├── README.md
│   └── USER_MANUAL.md
└── .env.example
```

---

## Acknowledgments

- Google Firebase for real-time cloud infrastructure
- Google Gemini for AI API access
- OpenStreetMap contributors for open mapping data
- The Flutter and ESP32 open-source communities