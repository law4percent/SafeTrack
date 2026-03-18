# SafeTrack — Project Plan & Goal
> Last updated: March 17, 2026

---

## Project Overview

**SafeTrack** is an IoT-based student safety tracking system built as a thesis project.
It consists of three components:

| Component | Stack | Status |
|---|---|---|
| Child device | ESP32-C3 + SIM7600 (GPRS) + GPS | ✅ Complete (firmware v4.4) |
| Mobile app | Flutter + Firebase RTDB | ✅ App-side FCM complete |
| Backend server | Python on laptop (physical machine) | ✅ Complete |

---

## Architecture

```
ESP32-C3 (child device)
  └── GPRS → Firebase RTDB

Firebase RTDB
  ├── deviceLogs/{uid}/{code}/{pushId}     ← firmware writes (flat fields)
  ├── deviceStatus/{uid}/{code}            ← firmware writes (nested lastLocation)
  ├── linkedDevices/{uid}/devices/{code}   ← app writes (metadata, schedule)
  ├── devicePaths/{uid}/{code}/{route}     ← app writes (waypoints)
  ├── alertLogs/{uid}/{code}/{pushId}      ← server writes, app reads
  ├── realDevices/{code}                   ← auth lookup
  ├── users/{uid}/fcmToken                 ← app writes (FCM token)
  └── serverCooldowns/{uid}/{code}/...     ← server writes (dedup)

Python Server (laptop, always-on)
  ├── deviation_monitor.py  ← RTDB listener → Haversine → FCM push
  ├── behavior_monitor.py   ← cron 5 min → late/absent/anomaly → FCM push
  └── silence_monitor.py    ← cron 5 min → heartbeat check → FCM push

Firebase FCM
  └── push to parent's phone

Flutter App (parent phone — displayer only)
  ├── FCM receiver          ← receives server push
  ├── notification_service  ← shows notification to parent
  └── alerts_screen         ← reads alertLogs, displays history
```

---

## Roles

### Server — The Monitor and Informer
- Only component that performs active detection
- Reads RTDB in real time and on cron
- Writes alerts to `alertLogs`
- Sends FCM push to parent's phone
- Runs 24/7 on parent's laptop

### App — The Displayer
- Receives FCM push from server (doorbell)
- Shows notification to parent via `NotificationService`
- Displays full alert history via `AlertScreen` (reads `alertLogs`)
- Displays live map via `LiveLocationsScreen`
- No active monitoring logic — server handles everything

---

## Completed ✅

### Firmware (ESP32-C3 v4.4)
- GPS + GPRS data transmission to Firebase RTDB
- Flat field schema: `latitude`, `longitude`, `altitude`, `speed`, `accuracy`,
  `locationType`, `batteryLevel`, `sos`, `timestamp`, `lastUpdate`
- SOS retry queue (offline SOS stored, auto-sent when reconnected)
- GPRS resilience: non-blocking checks, honest LED feedback
- Authentication via `realDevices/{uid}` → `actionOwnerID`
- Transmission interval: every 2 minutes (SOS: immediate)

### Flutter App — Core Screens
- Firebase Auth (login/signup)
- Dashboard with real-time child status cards (battery, GPS, online status, SOS)
- Live Location screen with embedded OpenStreetMap + full-screen map
- Route registration screen (tap-to-drop waypoints, Haversine deviation)
- My Children screen (link/unlink/edit devices, school schedule fields)
- Activity Log screen (per-device location history)
- Ask AI screen (Gemini AI with Firebase context, model switcher, RAG knowledge base)
- Settings screen
- Alerts screen (all alert types, filter chips, live childName substitution)

### Flutter App — Services
- `path_monitor_service.dart` — SOS save to alertLogs, DeviationEvent model
  (detection logic retained but deactivated — server is primary detector)
- `behavior_monitor_service.dart` — retained but deactivated (server is primary)
- `background_monitor_service.dart` — retained but deactivated (server is primary)
- `notification_service.dart` — 3 channels + `showFromFcm()` for FCM messages
- `haversine_service.dart` — Haversine math (used by route registration UI)

### Flutter App — FCM Integration ✅
- `firebase_messaging: ^16.0.2` added to `pubspec.yaml`
- FCM background handler registered in `main.dart`
- FCM token saved to `users/{uid}/fcmToken` on login + token refresh
- `FirebaseMessaging.onMessage` → `showFromFcm()` (foreground, SOS skipped)
- `FirebaseMessaging.onMessageOpenedApp` → `_routeFcmMessage()` (background tap)
- `getInitialMessage()` in `AuthWrapper.initState` (killed-state tap)
- Tap routing: SOS + deviation → `LiveLocationsScreen`, others → `AlertScreen`
- SOS FCM skipped in foreground — app RTDB listener handles it immediately

### Flutter App — Alert Types ✅
- `'silent'` filter chip added to `AlertScreen`
- `'silent'` case added to `_alertConfig()` (📡 Device Silent, deepPurple)
- `'silent'` added to `cancelAllForDevice()` and `showBehaviorAlert()` titles

### Flutter App — SOS Architecture ✅
- `dashboard_screen.dart` — removed `PathMonitorService().saveSosAlert()` from
  `_listenToSOS()` — server now owns alertLogs write for SOS
- `dashboard_screen.dart` — removed unused `path_monitor_service.dart` import
- `dashboard_screen.dart` — removed lat/lng extraction block (no longer needed)
- `main.dart` — SOS type skipped in `onMessage` foreground listener to prevent
  duplicate notification (app RTDB listener already shows it immediately)
- App still shows local SOS notification instantly via `_listenToSOS()`
- Server owns: alertLogs write + FCM push for SOS
- App owns: local notification display for SOS (foreground only)

### Python Server — Config ✅
- `requirements.txt` — `firebase-admin==6.5.0`, `pytz==2024.1`
- `config.py` — all thresholds, paths, timezone centralized

---

## App-Side Files — Final Status ✅

| File | Status | Notes |
|---|---|---|
| `pubspec.yaml` | ✅ Done | `firebase_messaging: ^16.0.2` added |
| `main.dart` | ✅ Done | FCM init, token save, routing, SOS skip |
| `notification_service.dart` | ✅ Done | `showFromFcm()`, `'silent'` support |
| `alerts_screen.dart` | ✅ Done | `'silent'` chip + config |
| `dashboard_screen.dart` | ✅ Done | SOS local notif only, no alertLogs write |

### Python Server — Core Files ✅

| File | Status | Notes |
|---|---|---|
| `requirements.txt` | ✅ Done | `firebase-admin==6.5.0`, `pytz==2024.1` |
| `config.py` | ✅ Done | Fill in `DATABASE_URL` before running |
| `utils/haversine.py` | ✅ Done | Port of `haversine_service.dart` |
| `utils/fcm_sender.py` | ✅ Done | Firebase Admin SDK FCM |
| `services/logger.py` | ✅ Done | Copy of existing logger |
| `services/deviation_monitor.py` | ✅ Done | Port of `path_monitor_service.dart` |
| `services/behavior_monitor.py` | ✅ Done | Port of `behavior_monitor_service.dart` |
| `services/silence_monitor.py` | ✅ Done | New — no Dart equivalent |
| `main.py` | ✅ Done | Entry point, starts all monitors |

### How to Run
```bash
cd SafeTrack/server
pip install -r requirements.txt
python main.py
```

---

## Pending ⏳

### Setup Steps (one-time)
1. Get `serviceAccountKey.json` from Firebase Console →
   Project Settings → Service Accounts → Generate new private key
2. Fill in `DATABASE_URL` in `config.py`
3. Place `serviceAccountKey.json` in `SafeTrack/server/`
4. Run `pip install -r requirements.txt`
5. Run `python main.py`

### Testing
- Test deviation alert end-to-end (ESP32 → RTDB → server → FCM → app)
- Test behavior alerts (late, absent, anomaly)
- Test silence alert (turn off ESP32 for 15+ min during school hours)
- Test offline pending notifications (app offline → server fires → app reconnects)
- Test dedup (app and server both detect same event → only 1 notification)
- Test `deviceEnabled = false` guard (disable device in MyChildrenScreen → no alerts)
- Test multiple parent accounts (server monitors all UIDs simultaneously)

---

## Notification Types

| Type | Trigger | Detected by | Title | Screen on tap |
|---|---|---|---|---|
| `sos` | SOS button pressed | App RTDB listener (local notif) + Server RTDB listener (alertLogs + FCM) | 🆘 SOS — {name} | LiveLocationsScreen |
| `deviation` | Off registered route | Server (RTDB listener) | ⚠️ {name} Off Route | LiveLocationsScreen |
| `late` | Late to school | Server (cron 5 min) | ⏰ Late Arrival — {name} | AlertScreen |
| `absent` | No school GPS today | Server (cron 5 min) | 📋 Possible Absence — {name} | AlertScreen |
| `anomaly` | Movement at odd hours | Server (cron 5 min) | ⚠️ Unusual Activity — {name} | AlertScreen |
| `silent` | Device not transmitting 15+ min | Server (cron 5 min) | 📡 Device Silent — {name} | AlertScreen |

---

## Guard Rules (all monitors)

| Guard | deviation | behavior | silence |
|---|---|---|---|
| `deviceEnabled == false` | ✅ Skip | ✅ Skip | ✅ Skip |
| `locationType != 'gps'` | ✅ Skip | ✅ Skip | ❌ N/A |
| `sos == true` | ✅ Skip | ✅ Skip | ✅ Skip |
| Outside school hours | ✅ Skip | ✅ Skip | ✅ Skip |
| Cooldown not expired | ✅ Skip | ✅ Skip | ✅ Skip |

---

## Deduplication Strategy

| Type | Method | RTDB path |
|---|---|---|
| `deviation` | Shared cooldown timestamp (5 min) | `serverCooldowns/{uid}/{code}/{routeId}/lastDeviationAlert` |
| `late` | Check if fired today via alertLogs | `alertLogs/{uid}/{code}` |
| `absent` | Check if fired today via alertLogs | `alertLogs/{uid}/{code}` |
| `anomaly` | Check if fired today via alertLogs | `alertLogs/{uid}/{code}` |
| `silent` | Re-alert cooldown (30 min) | `serverCooldowns/{uid}/{code}/lastSilentAlert` |
| `sos` | No dedup — firmware controls timing | — |

---

## Silence Monitor Thresholds

| Setting | Value | Reason |
|---|---|---|
| Silence threshold | 15 minutes | ESP32 transmits every 2 min — 15 min = 7 missed transmissions |
| Re-alert cooldown | 30 minutes | Avoids spamming parent if device stays silent |
| Cron interval | 5 minutes | Same as behavior monitor |

---

## Folder Structure

```
SafeTrack/
├── mobile/                          ← Flutter app
│   └── lib/
│       ├── main.dart
│       ├── screens/
│       │   ├── alerts_screen.dart
│       │   ├── dashboard_screen.dart
│       │   ├── live_location_screen.dart
│       │   └── ...
│       └── services/
│           ├── auth_service.dart
│           ├── background_monitor_service.dart
│           ├── behavior_monitor_service.dart
│           ├── gemini_service.dart
│           ├── haversine_service.dart
│           ├── notification_service.dart
│           └── path_monitor_service.dart
└── server/                          ← Python backend
    ├── main.py
    ├── config.py
    ├── requirements.txt
    ├── serviceAccountKey.json        ← gitignored
    ├── services/
    │   ├── logger.py
    │   ├── deviation_monitor.py
    │   ├── behavior_monitor.py
    │   └── silence_monitor.py
    └── utils/
        ├── haversine.py
        └── fcm_sender.py
```

---

## Thesis Context
- School: PHT timezone (Asia/Manila, UTC+8)
- School commute scenario: 06:20–07:15
- Test devices: DEVICE1234 (Juan), DEVICE5678 (Maria), DEVICE9999 (Carlos/SOS)
- Target: reliable real-time safety monitoring for students during commute to school
- Server: parent's laptop (physical machine, always-on during school hours)