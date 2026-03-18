# SafeTrack — Architecture Pros & Cons
> Version 1.0 (Server-Primary Architecture)
> Last updated: March 17, 2026

---

## What Changed from the Original Design

The original design relied entirely on the Flutter app for monitoring — using
`workmanager` background tasks running every 15 minutes on the parent's phone.

The new design moves all active monitoring to a always-on Python server running
on the parent's laptop. The app becomes a displayer only — it receives FCM pushes
from the server and shows alerts to the parent.

---

## Pros ✅

### 1. Reliable Notifications
The server runs continuously on the laptop, independent of Android battery
optimization, Doze mode, or OEM battery killers. Alerts fire on time, every time —
not subject to the 15-minute minimum interval that `workmanager` imposes.

### 2. Faster Detection
The deviation monitor uses a real-time RTDB listener. It reacts to every new GPS
log entry as it arrives — typically within seconds of the ESP32 transmission.
The old workmanager approach could miss events that happened between 15-minute windows.

### 3. Silent Alert Type (New)
The server introduces a new alert type — `silent` — that detects when a device
stops transmitting for 15+ minutes during school hours. This was impossible with
the app-only design because detecting silence requires an always-on process.
Possible causes: battery died, device confiscated, firmware crash, GPRS lost signal.

### 4. App Battery Savings
With monitoring moved to the server, the app no longer runs `workmanager` background
tasks. The parent's phone does less background work, which reduces battery drain.

### 5. Clean Separation of Concerns
- **Server** = monitor and informer (does the thinking)
- **App** = displayer (shows the results)
- **Firebase RTDB** = single source of truth (shared state)

This separation makes the system easier to debug — if an alert fires incorrectly,
you know to look at the server logs. If a notification doesn't show, you look at the app.

### 6. Centralized Logging
The server uses a rotating file logger (`logger.py`) with separate log files per
type (`error.log`, `info.log`, `debug.log`, etc.). Every monitor action, alert fired,
and FCM send is logged with timestamp and source file. Debugging is straightforward
because all server activity is visible in the terminal and in the log files.

### 7. Scales to Multiple Parents and Devices
The server reads the entire `linkedDevices` tree — not just one account. It monitors
all parents and all their devices simultaneously, routing each FCM push to the correct
parent's phone. Adding a new parent account requires no server changes.

### 8. Offline Resilience for the App
Firebase RTDB persistence is enabled on the app. If the parent's phone goes offline,
all alerts written to `alertLogs` by the server are queued and synced the moment the
phone reconnects. FCM also queues up to 100 pending pushes for offline delivery.
No alerts are lost.

### 9. RTDB-Backed Deduplication
Cooldown keys are stored in Firebase RTDB (`serverCooldowns`), not in memory.
This means the server can restart without losing cooldown state — no duplicate
alerts after a crash or reboot.

---

## Cons ⚠️

### 1. Laptop Must Be On
The server only works when the parent's laptop is powered on and connected to the
internet. If the laptop is off, closed, or asleep, no behavior, silence, or deviation
alerts will fire (except SOS, which the app still detects locally).

**Mitigation:** SOS detection is kept in the app as a deliberate safety exception —
it fires immediately even when the server is off. For a thesis demo scenario where
the server is always on during school hours, this is acceptable.

### 2. Not a True 24/7 Production Server
A laptop is not the same as a cloud VPS. It can sleep, restart after updates, lose
power, or be closed. A production system would use a VPS (e.g. DigitalOcean, Railway)
for guaranteed uptime.

**Mitigation:** For a thesis project with controlled demo conditions, the laptop is
sufficient. Migrating to a VPS later requires no code changes — only the deployment
environment changes.

### 3. Single Point of Failure
If the server crashes or the laptop loses internet, all server-side monitoring stops.
The app has no fallback detection (by design — Option A).

**Mitigation:** The server has error handling that catches per-device failures without
crashing the process. A single bad device or RTDB error does not take down the server.
The `_shutdown` event handles clean restarts via Ctrl+C.

### 4. Requires Python Environment Setup
The server requires Python, `firebase-admin`, `pytz`, and a `serviceAccountKey.json`
file. This is a one-time setup step but adds friction compared to a purely app-based
solution.

**Mitigation:** The setup is documented in `plan.md` and takes under 5 minutes.

### 5. FCM Token Dependency
The server needs the parent's FCM token (stored in `users/{uid}/fcmToken`) to send
push notifications. If the parent reinstalls the app or clears app data, the FCM
token changes. The app re-saves the token on login and on `onTokenRefresh`, so this
is self-healing — but there is a brief window where the token may be stale.

**Mitigation:** The `onTokenRefresh` listener in `main.dart` updates the token
automatically whenever FCM rotates it.

### 6. No Real-Time Behavior Alerts
Behavior checks (`late`, `absent`, `anomaly`) run on a 5-minute cron interval —
not in real time. An event that happens at minute 1 of a cron window may not be
detected until minute 5.

**Mitigation:** For school commute scenarios, a 5-minute delay on late/absent
detection is acceptable. SOS and deviation are real-time.

### 7. School Hours Dependency
All server monitors skip checks outside of school hours. If `schoolTimeIn` and
`schoolTimeOut` are not set for a device in My Children, that device gets no
behavior or silence monitoring.

**Mitigation:** The app enforces schedule entry during device linking. Devices
without a schedule are skipped with a clear reason logged.

---

## Summary Table

| Factor | Old Design (App-only) | New Design (Server-primary) |
|---|---|---|
| Detection reliability | ⚠️ Unreliable (Doze, OEM limits) | ✅ Reliable (always-on server) |
| Detection speed | ⚠️ Up to 15 min delay | ✅ Real-time (deviation), 5 min (behavior) |
| Silent device detection | ❌ Not possible | ✅ Yes (`silence_monitor.py`) |
| App battery usage | ⚠️ Higher (background tasks) | ✅ Lower (no background monitoring) |
| SOS reliability | ✅ App detects immediately | ✅ Same (app still detects SOS locally) |
| Offline alert history | ✅ RTDB persistence | ✅ RTDB persistence (unchanged) |
| Laptop required | ✅ No | ⚠️ Yes (server must be running) |
| Setup complexity | ✅ Simple (app only) | ⚠️ Slightly more (Python server setup) |
| Multiple accounts | ✅ Yes (per-user) | ✅ Yes (server monitors all accounts) |
| Production-ready | ⚠️ No (workmanager unreliable) | ⚠️ Not yet (laptop ≠ VPS) |
| Thesis demo suitability | ⚠️ Risky (may miss alerts) | ✅ Good (controlled environment) |