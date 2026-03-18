# SafeTrack — Notification Types Technical Reference
> Last updated: March 17, 2026

---

## Overview

The server decides the alert type. It never guesses — each monitor is hardcoded
to produce exactly one type string based on what it detected. The type string
travels from the server all the way to the parent's phone and determines which
screen opens when the notification is tapped.

---

## How the Type Travels

```
Server detects event
  → hardcodes type string (e.g. "deviation")
  → writes to alertLogs: { type: "deviation", ... }   ← AlertScreen reads this
  → sends FCM: { "type": "deviation", "deviceCode": "..." }
      ↓
Parent's phone receives FCM
      ↓
  App FOREGROUND
    → onMessage → showFromFcm()
    → reads message.data['type']
    → shows local notification with payload "deviation:DEVICE1234"
    → user taps → _onNotificationTapped parses payload
    → pendingNav.value = PendingNav("DEVICE1234", "deviation")
    → _navigateForType("deviation") → LiveLocationsScreen ✅

  App BACKGROUND / KILLED
    → FCM shows notification directly (no app involvement)
    → user taps → onMessageOpenedApp or getInitialMessage fires
    → _routeFcmMessage reads message.data['type']
    → _navigateForType("deviation") → LiveLocationsScreen ✅
```

---

## Alert Types — Full Reference

---

### 🆘 `sos`

| Field | Value |
|---|---|
| **Monitor** | `sos_monitor.py` |
| **Detection method** | Real-time RTDB listener |
| **Identifier** | `deviceStatus/sos` transitions `false → true` |
| **Cooldown** | None — every SOS fires immediately |
| **School hours guard** | None — SOS can happen anytime |
| **Requires registered path** | No |
| **Channel** | `safetrack_sos` |
| **Screen on tap** | `LiveLocationsScreen` |

**How it fires:**
```
Firmware: user holds SOS button 3s
  → writes sos: true to deviceStatus
  → sos_monitor._on_sos_event() detects false → true transition
  → type hardcoded as "sos"
  → writes alertLogs + sends FCM immediately
```

---

### ⚠️ `deviation`

| Field | Value |
|---|---|
| **Monitor** | `deviation_monitor.py` |
| **Detection method** | Real-time RTDB listener |
| **Identifier** | Haversine distance > route `deviationThresholdMeters` |
| **Cooldown** | 5 min per device per route (RTDB-backed) |
| **School hours guard** | Yes — skips outside schedule |
| **Requires registered path** | **Yes — no path = no deviation alert** |
| **Channel** | `safetrack_deviation` |
| **Screen on tap** | `LiveLocationsScreen` |

**How it fires:**
```
Firmware sends GPS log (locationType: "gps")
  → deviation_monitor reads new log entry
  → loads all active routes for this device
  → runs distance_to_path() against each route
  → if distance > threshold → deviation confirmed
  → type hardcoded as "deviation"
  → writes alertLogs + sends FCM
```

**No registered path behavior:** If the device has no routes registered,
`_load_active_routes()` returns an empty list. The check loop does not run.
No deviation alert fires. See Section: "No Registered Path" below.

**Multiple active routes behavior:** The monitor checks ALL active routes
on every GPS log. Each route is evaluated independently with its own
cooldown key. See Section: "Multiple Registered Paths" below.

---

### ⏰ `late`

| Field | Value |
|---|---|
| **Monitor** | `behavior_monitor.py` |
| **Detection method** | Cron every 5 minutes |
| **Identifier** | First school-hour GPS ping is after `schoolTimeIn + 15 min grace` |
| **Cooldown** | Once per day per device (checked via `alertLogs`) |
| **School hours guard** | Yes |
| **Requires registered path** | No |
| **Channel** | `safetrack_behavior` |
| **Screen on tap** | `AlertScreen` |

**How it fires:**
```
Cron fires
  → fetches last 200 logs for device, filters to today + GPS-only + no SOS
  → school_hour_gps_logs is not empty
  → first ping timestamp > grace_end (schoolTimeIn + 15 min)
  → _not_yet_fired_today("late") == True
  → type hardcoded as "late"
  → writes alertLogs + sends FCM
```

---

### 📋 `absent`

| Field | Value |
|---|---|
| **Monitor** | `behavior_monitor.py` |
| **Detection method** | Cron every 5 minutes |
| **Identifier** | Zero GPS pings during school hours after grace period |
| **Cooldown** | Once per day per device (checked via `alertLogs`) |
| **School hours guard** | Yes |
| **Requires registered path** | No |
| **Channel** | `safetrack_behavior` |
| **Screen on tap** | `AlertScreen` |

**How it fires:**
```
Cron fires
  → fetches last 200 logs, filters to today + GPS-only + no SOS
  → school_hour_gps_logs is empty
  → now > grace_end AND now < schoolTimeOut
  → _not_yet_fired_today("absent") == True
  → type hardcoded as "absent"
  → writes alertLogs + sends FCM
```

---

### ⚠️ `anomaly`

| Field | Value |
|---|---|
| **Monitor** | `behavior_monitor.py` |
| **Detection method** | Cron every 5 minutes |
| **Identifier** | GPS ping with timestamp hour >= 22 or < 5 |
| **Cooldown** | Once per day per device (checked via `alertLogs`) |
| **School hours guard** | No — anomaly specifically checks outside school hours |
| **Requires registered path** | No |
| **Channel** | `safetrack_behavior` |
| **Screen on tap** | `AlertScreen` |

**How it fires:**
```
Cron fires
  → fetches last 200 logs, filters to today + GPS-only + no SOS
  → checks all today_logs (not just school-hour logs)
  → finds entry with hour >= 22 OR hour < 5
  → _not_yet_fired_today("anomaly") == True
  → type hardcoded as "anomaly"
  → writes alertLogs + sends FCM
```

---

### 📡 `silent`

| Field | Value |
|---|---|
| **Monitor** | `silence_monitor.py` |
| **Detection method** | Cron every 5 minutes |
| **Identifier** | `now - deviceStatus/lastUpdate > 15 minutes` during school hours |
| **Cooldown** | Re-alerts every 30 min while device stays silent (RTDB-backed) |
| **School hours guard** | Yes |
| **Requires registered path** | No |
| **Channel** | `safetrack_behavior` |
| **Screen on tap** | `AlertScreen` |

**How it fires:**
```
Cron fires
  → reads deviceStatus/lastUpdate for device
  → calculates silence_ms = now_ms - lastUpdate_ms
  → silence_ms > 900000 (15 min in ms)
  → _is_realer_cooldown_active() == False
  → type hardcoded as "silent"
  → writes alertLogs + sends FCM
  → sets 30-min re-alert cooldown in RTDB
```

---

## No Registered Path

**Question: What happens if the device has no registered route?**

| Alert type | Behavior |
|---|---|
| `sos` | ✅ Fires normally — does not need a path |
| `deviation` | ❌ Never fires — no routes to check against |
| `late` | ✅ Fires normally — based on schedule only |
| `absent` | ✅ Fires normally — based on schedule only |
| `anomaly` | ✅ Fires normally — based on time of day only |
| `silent` | ✅ Fires normally — based on lastUpdate only |

**Deviation specifically:**

```python
# deviation_monitor.py — _process_log()
routes = _load_active_routes(self.uid, self.device_code)
if not routes:
    return   # ← exits silently, no alert, no error
```

`_load_active_routes()` returns an empty list when:
- No routes have been registered for this device
- All registered routes have `isActive: false` (paused)
- All routes have fewer than 2 waypoints (invalid)

In all three cases the deviation check is simply skipped — no crash,
no false alert, no log entry. The parent will not receive a deviation
notification until at least one valid active route exists.

**Practical implication:**
A device with no registered path still receives SOS, late, absent,
anomaly, and silent alerts. Only deviation monitoring is inactive.

---

## Multiple Registered Paths

**Question: What if one device has multiple active routes?**

The deviation monitor checks **all active routes on every GPS log entry.**
Each route is evaluated independently.

```
Device: DEVICE1234 (Juan)
Active routes:
  - route_A: "Home to School"    threshold: 50m
  - route_B: "Shortcut via Park" threshold: 30m
  - route_C: "Afternoon Route"   threshold: 50m  ← paused (isActive: false)

GPS log arrives
  → _load_active_routes() returns [route_A, route_B]  (route_C skipped)
  → distance_to_path(position, route_A.waypoints) = 85m → 85 > 50 → DEVIATION
  → distance_to_path(position, route_B.waypoints) = 20m → 20 < 30 → safe
```

**Result:** Only `route_A` fires an alert. `route_B` does not.

---

### Independent Cooldowns Per Route

Each route has its own cooldown key in RTDB:

```
serverCooldowns/{uid}/{deviceCode}/{routeId}/lastDeviationAlert
```

This means:

```
Juan deviates from route_A at 07:10
  → route_A cooldown set → no route_A alert until 07:15

Juan deviates from route_B at 07:11
  → route_B has its own cooldown → fires immediately ✅
  → does NOT inherit route_A's cooldown
```

Two routes can both alert independently within the same 5-minute window
if the child is off both routes simultaneously.

---

### Alert Per Route, Not Per Device

| Scenario | Alerts fired |
|---|---|
| Off route_A only | 1 alert (deviation from route_A) |
| Off route_B only | 1 alert (deviation from route_B) |
| Off both route_A and route_B simultaneously | 2 alerts (one per route) |
| Off route_A, cooldown active | 0 alerts (suppressed) |
| route_C paused | 0 alerts (skipped by server) |

**Parent receives separate notifications** for each route deviation, each
with its own route name in the message:

```
⚠️ Juan Off Route
"Juan is 85m away from the registered route "Home to School"..."

⚠️ Juan Off Route
"Juan is 45m away from the registered route "Shortcut via Park"..."
```

---

## Tap Routing Summary

| Type | Screen opened |
|---|---|
| `sos` | `LiveLocationsScreen` |
| `deviation` | `LiveLocationsScreen` |
| `late` | `AlertScreen` |
| `absent` | `AlertScreen` |
| `anomaly` | `AlertScreen` |
| `silent` | `AlertScreen` |

SOS and deviation open the live map because the parent's first instinct
is to see where the child is right now.

Late, absent, anomaly, and silent open the alert history because the
parent needs context — not just a map pin.

---

## Detection Source Per Type

| Type | App (foreground RTDB) | App (workmanager) | Server (real-time) | Server (cron) |
|---|---|---|---|---|
| `sos` | ✅ local notif only | ❌ | ✅ alertLogs + FCM | ❌ |
| `deviation` | ❌ | ❌ | ✅ | ❌ |
| `late` | ❌ | ❌ | ❌ | ✅ |
| `absent` | ❌ | ❌ | ❌ | ✅ |
| `anomaly` | ❌ | ❌ | ❌ | ✅ |
| `silent` | ❌ | ❌ | ❌ | ✅ |