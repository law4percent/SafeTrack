# SafeTrack — Notification Types Reference
> Last updated: March 17, 2026

---

## Overview

SafeTrack uses 6 alert types across 3 notification channels.
Each alert type is written to `alertLogs/{uid}/{deviceCode}/{pushId}` in RTDB
and delivered to the parent via local notification (app-side) or FCM push (server-side).

---

## Notification Channels

| Channel ID | Name | Importance | Used By |
|---|---|---|---|
| `safetrack_sos` | SOS Alerts | MAX | `sos` |
| `safetrack_deviation` | Route Deviation Alerts | HIGH | `deviation` |
| `safetrack_behavior` | Behavior Alerts | HIGH | `late`, `absent`, `anomaly`, `silent` |

---

## Alert Types

### 🆘 `sos`
| Field | Value |
|---|---|
| **Trigger** | Child presses SOS button on ESP32 device |
| **Detected by** | Firmware writes `sos: true` to RTDB → app foreground listener |
| **Channel** | `safetrack_sos` |
| **Notification title** | 🆘 SOS — {childName} |
| **Notification body** | Emergency alert triggered! Tap to view location. |
| **Screen on tap** | `LiveLocationsScreen` |
| **Priority** | CRITICAL — full screen intent on Android |
| **RTDB written by** | `path_monitor_service.dart` (app) |

---

### ⚠️ `deviation`
| Field | Value |
|---|---|
| **Trigger** | Child strays beyond threshold meters from registered route |
| **Detected by** | App `path_monitor_service` (foreground + workmanager) OR Server RTDB listener |
| **Channel** | `safetrack_deviation` |
| **Notification title** | ⚠️ {childName} Off Route |
| **Notification body** | {distance}m from "{routeName}" — Tap to view location |
| **Screen on tap** | `LiveLocationsScreen` |
| **Priority** | HIGH |
| **RTDB written by** | `path_monitor_service.dart` (app) / `deviation_monitor.py` (server) |
| **Extra RTDB fields** | `distanceMeters`, `routeName` |

---

### ⏰ `late`
| Field | Value |
|---|---|
| **Trigger** | Child has not reached school by expected arrival time |
| **Detected by** | App `behavior_monitor_service` (workmanager) OR Server cron every 5 min |
| **Channel** | `safetrack_behavior` |
| **Notification title** | ⏰ Late Arrival — {childName} |
| **Notification body** | Custom message based on schedule |
| **Screen on tap** | `AlertScreen` |
| **Priority** | HIGH |
| **RTDB written by** | `behavior_monitor_service.dart` (app) / `behavior_monitor.py` (server) |

---

### 📋 `absent`
| Field | Value |
|---|---|
| **Trigger** | No movement detected near school at all during school hours |
| **Detected by** | App `behavior_monitor_service` (workmanager) OR Server cron every 5 min |
| **Channel** | `safetrack_behavior` |
| **Notification title** | 📋 Possible Absence — {childName} |
| **Notification body** | Custom message based on schedule |
| **Screen on tap** | `AlertScreen` |
| **Priority** | HIGH |
| **RTDB written by** | `behavior_monitor_service.dart` (app) / `behavior_monitor.py` (server) |

---

### ⚠️ `anomaly`
| Field | Value |
|---|---|
| **Trigger** | Unusual location pattern detected outside normal schedule |
| **Detected by** | App `behavior_monitor_service` (workmanager) OR Server cron every 5 min |
| **Channel** | `safetrack_behavior` |
| **Notification title** | ⚠️ Unusual Activity — {childName} |
| **Notification body** | Custom message based on detected pattern |
| **Screen on tap** | `AlertScreen` |
| **Priority** | HIGH |
| **RTDB written by** | `behavior_monitor_service.dart` (app) / `behavior_monitor.py` (server) |

---

### 📡 `silent`
| Field | Value |
|---|---|
| **Trigger** | Device has not sent any data for X minutes during school hours |
| **Detected by** | Server cron every 5 min only (app cannot detect this — it needs an always-on process) |
| **Channel** | `safetrack_behavior` |
| **Notification title** | 📡 Device Silent — {childName} |
| **Notification body** | {childName}'s device has stopped responding. Please check on your child. |
| **Screen on tap** | `AlertScreen` |
| **Priority** | HIGH |
| **RTDB written by** | `silence_monitor.py` (server only) |
| **Threshold** | `now - lastUpdate > 10 minutes` during school hours |
| **Possible causes** | Battery died, device confiscated, firmware crash, GPRS lost connectivity |

---

## Tap Routing Summary

| Type | Screen |
|---|---|
| `sos` | `LiveLocationsScreen` — parent needs to see live location immediately |
| `deviation` | `LiveLocationsScreen` — parent needs to see where child is now |
| `late` | `AlertScreen` — parent needs context and alert history |
| `absent` | `AlertScreen` — parent needs context and alert history |
| `anomaly` | `AlertScreen` — parent needs context and alert history |
| `silent` | `AlertScreen` — device is not transmitting, map has no new data to show |

---

## RTDB Alert Log Schema

```
alertLogs/{uid}/{deviceCode}/{pushId}
  ├── type          : 'sos' | 'deviation' | 'late' | 'absent' | 'anomaly' | 'silent'
  ├── childName     : string
  ├── message       : string
  ├── timestamp     : number (ms since epoch)
  ├── distanceMeters: number?   (deviation only)
  └── routeName     : string?   (deviation only)
```

---

## Detection Source Summary

| Type | App (foreground) | App (workmanager 15min) | Server (always-on) |
|---|---|---|---|
| `sos` | ✅ | ✅ | ✅ |
| `deviation` | ✅ | ✅ | ✅ |
| `late` | ❌ | ✅ | ✅ |
| `absent` | ❌ | ✅ | ✅ |
| `anomaly` | ❌ | ✅ | ✅ |
| `silent` | ❌ | ❌ | ✅ only |