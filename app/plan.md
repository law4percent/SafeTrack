# SafeTrack — Project Plan & Goal
> Last updated: March 14, 2026

---

## Project Overview

**SafeTrack** is an IoT-based student safety tracking system built as a thesis project.
It consists of three components:

| Component | Stack | Status |
|---|---|---|
| Child device | ESP32-C3 + SIM7600 (GPRS) + GPS | ✅ Complete (firmware v4.4) |
| Mobile app | Flutter + Firebase RTDB | 🔄 In progress |
| Backend server | Node.js / Python on VPS (planned) | ⏳ Pending |

---

## Completed ✅

### Firmware (ESP32-C3 v4.4)
- GPS + GPRS data transmission to Firebase RTDB
- Flat field schema: `latitude`, `longitude`, `altitude`, `speed`, `accuracy`, `locationType`, `batteryLevel`, `sos`, `timestamp`, `lastUpdate`
- SOS retry queue (offline SOS stored, auto-sent when reconnected)
- GPRS resilience: non-blocking checks, honest LED feedback
- Authentication via `realDevices/{uid}` → `actionOwnerID`

### Flutter App — Core
- Firebase Auth (login/signup)
- Dashboard with real-time child status cards (battery, GPS, online status, SOS)
- Live Location screen with embedded OpenStreetMap + full-screen map
- Route registration screen (tap-to-drop waypoints, Haversine deviation)
- My Children screen (link/unlink/edit devices, school schedule fields)
- Activity Log screen (per-device location history)
- Ask AI screen (Gemini AI with Firebase context, model switcher, RAG knowledge base)
- Settings screen

### Flutter App — Services
- `path_monitor_service.dart` — real-time Haversine deviation detection
  - GPS-only filter (skips cached logs)
  - SOS guard (no deviation alerts during emergency)
  - School hours guard (no alerts outside schedule)
  - Dual dedup (key + timestamp)
  - Per-route cooldown
  - Writes to `alertLogs/{uid}/{deviceCode}/{pushId}`
- `behavior_monitor_service.dart` — late/absent/anomaly detection
  - GPS-only + SOS-exclusion filter
  - RTDB-backed cooldown (`_notYetFiredToday`) — isolate-safe
  - `limitToLast(200)` on log fetch
  - Parallel device checks via `Future.wait`
- `notification_service.dart` — 3 channels (deviation, SOS, behavior)
  - Per-route cooldown keys
  - `cancelAllForDevice()` covers all 3 types
  - Consistent `deviceCode` payload across all notifications
- `background_monitor_service.dart` — workmanager 15-min periodic task
  - Calls both `PathMonitorService` AND `BehaviorMonitorService`
  - Sign-out cleanup documented
- `alert_screen.dart` — displays all alert types with filter chips
  - Live childName substitution (handles renames)

### RTDB Schema (validated 24/24 against firmware)
- `deviceLogs/{uid}/{deviceCode}/{pushId}` — flat firmware fields
- `deviceStatus/{uid}/{deviceCode}` — nested lastLocation for dashboard
- `linkedDevices/{uid}/devices/{deviceCode}` — app metadata
- `devicePaths/{uid}/{deviceCode}/{routeId}` — waypoints
- `alertLogs/{uid}/{deviceCode}/{pushId}` — all alert types
- `realDevices/{deviceCode}` — auth lookup

---

## Pending Implementation 🔄

### 1. FCM Integration (app side)
**What:** Firebase Cloud Messaging — allows the future server to push notifications
directly to the parent's phone, bypassing Android battery restrictions.

**Why needed:** Current `workmanager` background tasks are unreliable (Android Doze,
OEM battery killers, 15-min minimum interval). Server-sent FCM pushes bypass all of this.

**Files affected:** `main.dart`, `notification_service.dart`

**What needs to be done:**
- Add `firebase_messaging: ^15.0.0` to `pubspec.yaml`
- Register FCM background handler in `main.dart` (top-level, `@pragma('vm:entry-point')`)
- Save FCM token to `users/{uid}/fcmToken` in RTDB on login + on token refresh
- Add `FirebaseMessaging.onMessage` listener (foreground message display)
- Add `FirebaseMessaging.onMessageOpenedApp` listener (background tap)
- Add `getInitialMessage()` in `AuthWrapper.initState` (killed-state tap)
- Add `showFromFcm(RemoteMessage)` method to `notification_service.dart`

**RTDB path added:** `users/{uid}/fcmToken`

---

### 2. Server (VM/VPS)
**What:** A Node.js or Python service running 24/7 on a small VPS (DigitalOcean,
Railway, Render, etc.) using Firebase Admin SDK + FCM.

**Why needed:** Provides reliable, always-on monitoring independent of the parent's
phone state. Addresses the fundamental unreliability of workmanager.

**Responsibilities:**
- **Real-time deviation detection** — Admin SDK listens to `deviceLogs` → Haversine
  check → FCM push to parent if deviation detected
- **Behavior checks** — cron every 5 min: late/absent/anomaly against school schedule
- **Heartbeat / device silence monitor** ← NEW FEATURE (your idea)
  - For each enabled device, checks `max(lastUpdate)` from `deviceLogs`
  - If `now - lastUpdate > threshold` (e.g. 10 min) during school hours → alert
  - Detects: battery died, device confiscated, firmware crash, lost connectivity
  - Alert type: `'silent'` written to `alertLogs` + FCM push

**RTDB paths read:** `deviceLogs`, `devicePaths`, `linkedDevices`, `users/{uid}/fcmToken`
**RTDB paths written:** `alertLogs`

**New alert type to add to `alert_screen.dart`:**
- Filter chip: `'silent'` → "Device Silent"
- Icon: `Icons.wifi_off` or `Icons.sensors_off`, color: `Colors.deepPurple`

---

### 3. `notification_service.dart` — `showFromFcm()` method
**What:** When the server sends a FCM push and the app is in the foreground, FCM
does not show a notification automatically. This method translates an incoming
`RemoteMessage` into a local notification using the existing channels.

**Signature:**
```dart
Future<void> showFromFcm(RemoteMessage message) async {
  // Read message.data['type'] → route to correct channel
  // 'sos' → showSosAlert channel
  // 'deviation' → deviation channel
  // 'late'|'absent'|'anomaly'|'silent' → behavior channel
}
```

---

### 4. `alert_screen.dart` — `'silent'` filter chip
**What:** Add the "Device Silent" alert type from the server's heartbeat monitor.

**Change:** Add one new `_filterChip` entry and one new case in `_alertConfig()`.

---

## Implementation Order

```
1. pubspec.yaml          → add firebase_messaging
2. notification_service  → add showFromFcm()
3. main.dart             → FCM token save + background handler + message listeners
4. alert_screen          → add 'silent' filter chip
5. Server                → Node.js/Python service (separate repo)
```

Steps 1–4 are app-side and can be done now.
Step 5 is the server and follows after steps 1–4 are tested.

---

## File Inventory (current outputs)

| File | Status |
|---|---|
| `main.dart` | 🔄 FCM sections ready but needs `firebase_messaging` in pubspec |
| `dashboard_screen.dart` | ✅ Fixed (firmware field alignment, SOS chain, parallel queries) |
| `activity_log_screen.dart` | ✅ Fixed (firmware fields, limitToLast(50)) |
| `alert_screen.dart` | ✅ Fixed — needs `'silent'` chip added |
| `live_location_screen.dart` | ✅ |
| `path_monitor_service.dart` | ✅ Fixed (all guards, per-route cooldown, .get() cache) |
| `notification_service.dart` | ✅ Fixed — needs `showFromFcm()` added |
| `behavior_monitor_service.dart` | ✅ Fixed (RTDB cooldown, parallel checks, limitToLast) |
| `background_monitor_service.dart` | ✅ Fixed (runChecks() wired) |
| `gemini_service.dart` | ✅ (school context, alertLogs, human timestamps, model switcher) |
| `ask_ai_screen.dart` | ✅ (model picker, Firebase context) |
| `my_children_screen.dart` | ✅ (school time pickers, route registration) |
| `route_registration_screen.dart` | ✅ |
| `haversine_service.dart` | ✅ |
| `AndroidManifest.xml` | ✅ (all permissions including USE_FULL_SCREEN_INTENT) |
| `rtdb_test_data.json` | ✅ (24/24 validated against firmware v4.4) |
| `safetrack_firmware.ino` | ✅ (v4.4) |

---

## Architecture Diagram

```
ESP32-C3 (child device)
  │  GPRS → Firebase RTDB
  ▼
Firebase RTDB
  ├── deviceLogs/{uid}/{code}/{pushId}   ← firmware writes (flat fields)
  ├── deviceStatus/{uid}/{code}          ← firmware writes (nested lastLocation)
  ├── linkedDevices/{uid}/devices/{code} ← app writes (metadata, schedule)
  ├── devicePaths/{uid}/{code}/{route}   ← app writes (waypoints)
  ├── alertLogs/{uid}/{code}/{pushId}    ← services write, alert_screen reads
  ├── realDevices/{code}                 ← auth lookup
  └── users/{uid}/fcmToken               ← app writes (pending FCM step)

Flutter App (parent phone)
  ├── Foreground listeners (path_monitor, dashboard SOS)
  ├── Background (workmanager → path_monitor + behavior_monitor)
  └── FCM receiver (pending) → showFromFcm → local notification

Server / VM (planned)
  ├── RTDB Admin listener → deviation → FCM push
  ├── Cron 5min → behavior checks → FCM push
  └── Cron 5min → heartbeat / device silence → FCM push
```

---

## Thesis Context
- School: PHT timezone, school commute scenario (06:20–07:15)
- Test devices: DEVICE1234 (Juan), DEVICE5678 (Maria), DEVICE9999 (Carlos/SOS)
- Target: reliable real-time safety monitoring for students during commute to school