# SafeTrack

> IoT-based student safety monitoring system
> BS Computer Engineering Thesis — Cebu Technological University, Danao Campus

---

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Alert Types](#alert-types)
4. [Circuit Diagram](#circuit-diagram)
5. [3D Model of the Device](#3d-model-of-the-device)
6. [App UI Screenshots](#app-ui-screenshots)
7. [Downloads](#downloads)
8. [Server Setup](#server-setup)
9. [Folder Structure](#folder-structure)
10. [How It Works](#how-it-works)
11. [Guard Rules](#guard-rules)
12. [Logging](#logging)
13. [Multiple Parents and Devices](#multiple-parents-and-devices)
14. [Configuration Reference](#configuration-reference)
15. [Security Notes](#security-notes)

---

## Overview

SafeTrack is an IoT-based child safety monitoring system that helps parents
of elementary school students monitor their child's real-time GPS location,
register safe travel routes, receive deviation alerts, and query an AI
assistant for safety insights.

The system has three components:

| Component | Stack | Status |
|---|---|---|
| Child device | ESP32-C3 + SIM7600 + GPS | ✅ Complete (firmware v4.4) |
| Mobile app | Flutter + Firebase RTDB | ✅ Complete |
| Backend server | Python on laptop | ✅ Complete |

```
ESP32 Device → Firebase RTDB → Server → FCM → Parent's Phone → App
```

The server is the **sole monitor and informer**.
The Flutter app is the **displayer only**.

---

## System Architecture

```
ESP32-C3 (child device)
  └── GPRS → Firebase RTDB

Firebase RTDB
  ├── deviceLogs/{uid}/{code}/{pushId}     ← firmware writes
  ├── deviceStatus/{uid}/{code}            ← firmware writes
  ├── linkedDevices/{uid}/devices/{code}   ← app writes
  ├── devicePaths/{uid}/{code}/{route}     ← app writes
  ├── alertLogs/{uid}/{code}/{pushId}      ← server writes, app reads
  ├── users/{uid}/fcmToken                 ← app writes
  └── serverCooldowns/{uid}/{code}/...     ← server writes (dedup)

Python Server (laptop, always-on)
  ├── sos_monitor.py       ← real-time SOS detection
  ├── deviation_monitor.py ← real-time route deviation
  ├── behavior_monitor.py  ← cron: late, absent, anomaly
  └── silence_monitor.py   ← cron: device heartbeat check

Firebase FCM → Parent's Phone → Flutter App
```

---

## Alert Types

| Type | Trigger | Detection | Cooldown |
|---|---|---|---|
| 🆘 `sos` | Child presses emergency button | Real-time | None |
| ⚠️ `deviation` | Child moves off registered route | Real-time | 5 min per route |
| ⏰ `late` | No GPS near school after grace period | Cron 5 min | Once per day |
| 📋 `absent` | Zero GPS activity during school hours | Cron 5 min | Once per day |
| ⚠️ `anomaly` | Movement after 22:00 or before 05:00 | Cron 5 min | Once per day |
| 📡 `silent` | Device stops transmitting 15+ min | Cron 5 min | 30 min re-alert |

---

## Circuit Diagram

> The circuit diagram shows the hardware wiring of the ESP32-C3 Super Mini
> with the SIM7600E-H1C, MAX17043 fuel gauge, TP4056 charger, and MT3608
> boost converter.

<!-- Replace the image path below with your actual circuit diagram image -->
<!-- Recommended: export as PNG at 1200px wide minimum for clarity -->

![Circuit Diagram](images/circuit_diagram.png)

> **Components:**
> - **ESP32-C3 Super Mini** — main microcontroller (RISC-V, 160MHz)
> - **SIM7600E-H1C** — 4G LTE module with built-in GPS
> - **MAX17043** — LiPo battery fuel gauge (I2C)
> - **TP4056** — LiPo charging module with overcharge protection
> - **MT3608** — DC-DC boost converter (3.7V → 5V)
> - **LiFePO4 3.7V 2000mAh** — primary battery (~8–12hr runtime)
> - **Push button** — SOS trigger (hold 3 seconds to activate)

---

## 3D Model of the Device

> Custom enclosure designed to house the ESP32-C3, SIM7600, and battery
> in a compact, child-safe form factor.

### Renders

<!-- Replace image paths below with your actual 3D render screenshots -->

| Front View | Back View | Assembled |
|---|---|---|
| ![Front](images/3d_front.png) | ![Back](images/3d_back.png) | ![Assembled](images/3d_assembled.png) |

### Download STL File

> 📦 **[Download STL File (Google Drive)](https://drive.google.com/drive/folders/1EYjyFP11LW7h_nx68BAPlHHjCYp_BCfe?usp=drive_link)**
>
> The STL file contains the printable enclosure for the SafeTrack device.
> Recommended print settings: PLA, 0.2mm layer height, 20% infill.

---

## App UI Screenshots

### Authentication
> The Login and Sign up page only for parents

<!-- Replace image paths with your actual screenshots -->
![Authentication - Login and Sign Up](images/authentication_screens.png)

---

### Dashboard
> Shows all linked children with online status, battery level, GPS status, and SOS indicator.

<!-- Replace image paths with your actual screenshots -->
![Dashboard](images/ui_dashboard.png)

---

### Live Location
> Real-time map showing child's position, registered route, and deviation status.

![Live Location](images/ui_live_location.png)

---

### My Children
> Device management — link/unlink devices, set school schedule, manage routes.

![My Children](images/ui_my_children.png)

---

### Route Registration
> Tap-to-drop waypoint editor for registering safe routes with deviation threshold.

![Route Registration](images/ui_route_registration.png)

---

### Alerts Screen
> Full alert history with filter chips for all 6 alert types.

![Alerts Screen](images/ui_alerts.png)

---

### AI Assistant
> Gemini-powered AI chat with real Firebase context and reverse geocoding.

![AI Assistant](images/ui_ai_assistant.png)

---

### Settings
> Help Center with embedded User Manual and notification guide.

![Settings](images/ui_settings.png)

---

### User Manual (in-app)
> Accessible from Settings → Help & Guides → User Manual.

![User Manual Sheet](images/ui_user_manual.png)

---

## Downloads

### 📱 Latest APK

> Install the SafeTrack app on your Android phone directly.
> Minimum Android version: API 21 (Android 5.0)

**[⬇️ Download SafeTrack APK (Google Drive)](https://drive.google.com/drive/folders/1AYsSuv9e3lkmnOq0V9bhxJvm2ejC88V-?usp=drive_link)**

> **How to install:**
> 1. Download the APK file on your Android phone.
> 2. Open your phone Settings → Security → Enable **Install from unknown sources**.
> 3. Open the downloaded APK file and tap **Install**.
> 4. Open SafeTrack and sign up or log in.

---

### 🖨️ STL File (3D Print Enclosure)

**[⬇️ Download STL File (Google Drive)](https://drive.google.com/drive/folders/1EYjyFP11LW7h_nx68BAPlHHjCYp_BCfe?usp=sharing)**

---

## Server Setup

### Requirements

- Python 3.10 or higher
- Firebase project with Realtime Database enabled
- `serviceAccountKey.json` from Firebase Console
- Internet connection (outbound only — no open ports required)

### Steps

**1. Get your Firebase service account key**

Firebase Console → Project Settings → Service Accounts →
Generate new private key → save as `serviceAccountKey.json` in this folder.

**2. Set your database URL in `config.py`**

```python
# Format: https://<project-id>-default-rtdb.<region>.firebasedatabase.app
DATABASE_URL = "https://<your-project-id>-default-rtdb.asia-southeast1.firebasedatabase.app"
```

**3. Install dependencies**

```bash
pip install -r requirements.txt
```

**4. Run the server**

```bash
python main.py
```

### Expected terminal output on startup

```
============================================================
  SafeTrack Server
  Always-on monitoring for student safety
============================================================
📁 Log Directory: /path/to/server/logs
...
[INFO] Firebase initialized
[INFO] Running initial checks on startup...
[INFO] SOS monitor running
[INFO] Deviation monitor running
[INFO] Server is running. Press Ctrl+C to stop.
```

---

## Folder Structure

```
server/
├── main.py                  ← Entry point
├── config.py                ← All thresholds, paths, timezone
├── requirements.txt         ← Python dependencies
├── serviceAccountKey.json   ← Firebase credentials (never commit this)
├── logs/                    ← Auto-created on first run
│   ├── all.log
│   ├── info.log
│   ├── error.log
│   ├── warning.log
│   ├── debug.log
│   └── bug.log
├── services/
│   ├── logger.py            ← Centralized rotating file logger
│   ├── sos_monitor.py       ← Real-time SOS detection
│   ├── deviation_monitor.py ← Real-time route deviation detection
│   ├── behavior_monitor.py  ← Cron: late, absent, anomaly
│   └── silence_monitor.py   ← Cron: device heartbeat check
└── utils/
    ├── haversine.py         ← GPS distance calculations
    └── fcm_sender.py        ← Firebase Cloud Messaging sender
```

---

## How It Works

### Real-Time Monitors (always listening)

**`sos_monitor.py`**
Attaches one RTDB listener per device watching
`linkedDevices/{uid}/devices/{code}/deviceStatus/sos`.
When the field transitions from `false` to `true`, it immediately writes
to `alertLogs` and sends an FCM push to the parent. Resets when SOS clears.

**`deviation_monitor.py`**
Attaches one RTDB listener per device watching `deviceLogs/{uid}/{code}`.
On each new GPS entry it runs a Haversine calculation against all active
registered routes. If the child is beyond the deviation threshold, it fires
an alert with a 5-minute RTDB-backed cooldown per device per route.

### Cron Monitors (every 5 minutes)

**`behavior_monitor.py`**
Fetches the last 200 device logs scoped to today for each enabled device.
Checks three conditions against the device's school schedule:
- **Late** — first GPS ping during school hours was after grace period
- **Absent** — no GPS pings during school hours after grace period
- **Anomaly** — GPS movement detected after 22:00 or before 05:00

**`silence_monitor.py`**
Reads `deviceStatus/lastUpdate` for each enabled device. If the device has
not transmitted for more than 15 minutes during school hours, fires a silent
alert. Re-alerts every 30 minutes if the device stays silent.

---

## Guard Rules

Every monitor skips a device if any of these conditions are true:

| Guard | Applies to |
|---|---|
| `deviceEnabled == false` | All monitors |
| `locationType != 'gps'` | Deviation, Behavior |
| `sos == true` | Deviation, Behavior, Silence |
| Outside school hours | Deviation, Behavior, Silence |
| Cooldown not expired | Deviation, Silence |
| No school schedule set | Behavior, Silence |

---

## Logging

Logs are written to `server/logs/` on first run. Each log type has its own
rotating file (10MB max, 5 backups) plus a combined `all.log`.

```
[2026-03-17 07:05:01.123] [INFO]  [main.py:45]              Server is running
[2026-03-17 07:05:02.456] [INFO]  [deviation_monitor.py:88] Deviation: Juan 85m from Morning Route
[2026-03-17 07:05:02.789] [INFO]  [fcm_sender.py:62]        FCM push sent
[2026-03-17 07:10:01.001] [INFO]  [behavior_monitor.py:112] late alert fired for Maria
[2026-03-17 07:15:00.333] [ERROR] [main.py:78]              Silence check error: connection timeout
```

Console output is color-coded by log type for easy reading during development.

---

## Multiple Parents and Devices

The server monitors **all parent accounts and all their devices simultaneously**.
It reads the entire `linkedDevices` tree on startup and attaches listeners or
runs checks for every enabled device it finds. FCM pushes are routed to each
parent's own FCM token — notifications never cross between accounts.

When a parent enables or disables a device in the app, the server detects the
change in real time and starts or stops that device's listeners automatically.

---

## Configuration Reference

| Setting | Default | Description |
|---|---|---|
| `TIMEZONE` | `Asia/Manila` (PHT) | Timezone for all time comparisons |
| `DEVIATION_COOLDOWN_MINUTES` | `5` | Min time between deviation alerts per device per route |
| `SILENCE_THRESHOLD_MINUTES` | `15` | How long a device must be silent before alerting |
| `SILENCE_REALER_COOLDOWN_MINUTES` | `30` | How often to re-alert if device stays silent |
| `BEHAVIOR_CRON_INTERVAL_MINUTES` | `5` | How often behavior + silence cron runs |
| `LATE_GRACE_PERIOD_MINUTES` | `15` | Grace period after school start before late alert |
| `ANOMALY_NIGHT_HOUR` | `22` | Hour after which movement is anomalous |
| `ANOMALY_EARLY_HOUR` | `5` | Hour before which movement is anomalous |
| `BEHAVIOR_LOG_LIMIT` | `200` | Max device logs fetched per device per check |

---

## Security Notes

- `serviceAccountKey.json` grants full Firebase Admin access — **never commit it to git**
- Add to `.gitignore` immediately:
  ```
  serviceAccountKey.json
  logs/
  __pycache__/
  *.pyc
  ```
- The server only needs outbound internet access — no open ports or public IP required
- All Firebase reads and writes are scoped to the minimum needed paths

---

## Thesis Information

| Field | Detail |
|---|---|
| Institution | Cebu Technological University – Danao Campus |
| Program | BS Computer Engineering |
| Developers | Elyza Camille Good, Jemarie Mae B. Samontanez, Jonnamaye A. Agting |
| Timezone | PHT (UTC+8) |
| Test devices | DEVICE1234 (Juan), DEVICE5678 (Maria), DEVICE9999 (Carlos) |