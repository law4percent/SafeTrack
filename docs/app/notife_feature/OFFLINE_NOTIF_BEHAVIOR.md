# SafeTrack — Offline Notification Behavior
> Last updated: March 18, 2026

---

## Overview

SafeTrack uses two independent recovery mechanisms to ensure no alerts are
lost when the parent's phone goes offline. These work automatically with no
code changes required.

```
Phone goes offline
  └── Server keeps running on laptop
        ├── Writes alerts to Firebase RTDB     ← Mechanism 1
        └── Sends FCM pushes to Google servers  ← Mechanism 2

Phone comes back online
  ├── RTDB syncs → AlertScreen shows full history  ✅
  └── FCM delivers queued pushes → notifications appear ✅
```

---

## Mechanism 1 — Firebase RTDB Offline Persistence

The app has RTDB offline persistence enabled in `main.dart`:

```dart
database.setPersistenceEnabled(true);
database.setPersistenceCacheSizeBytes(10000000); // 10MB local cache
```

**What this means:**
- The RTDB client caches all data locally on the phone
- While offline, the cache keeps the last known state of `alertLogs`
- When the phone reconnects, RTDB syncs the full `alertLogs` tree instantly
- `AlertScreen` reads directly from RTDB — it always shows the complete
  alert history regardless of what FCM did or did not deliver

**This is the source of truth.** Even if every FCM notification is dropped,
the parent can open `AlertScreen` and see every alert the server ever wrote.

---

## Mechanism 2 — FCM Message Queue

Firebase Cloud Messaging stores undelivered messages on Google's servers
when the target device is offline.

**What this means:**
- Server sends FCM push → Google stores it if phone is unreachable
- When the phone reconnects to the internet, FCM delivers all queued pushes
- No code changes needed — this is built into FCM

**Storage limits:**
- FCM stores pending messages for up to **4 weeks**
- FCM delivers up to **100 pending messages** per device on reconnect
- Beyond 100 messages, oldest ones are dropped — but RTDB still has everything

---

## Full Scenario Walkthrough

```
07:30  Phone goes offline (airplane mode or no internet)
       Server is still running on laptop

07:45  Server detects late alert for Juan
         → writes alertLogs/uid/DEVICE1234/{id}  ← stored in RTDB ✅
         → sends FCM push → Google stores it     ← queued ✅

08:00  Server detects silent alert for Juan
         → writes alertLogs ✅
         → FCM queued ✅

08:30  Server detects absent alert for Juan
         → writes alertLogs ✅
         → FCM queued ✅

11:00  Parent turns phone internet back on

11:00  RTDB syncs immediately
         → alertLogs has all 3 entries
         → AlertScreen shows: late, silent, absent ✅

11:00  FCM delivers 3 queued pushes
         → Parent receives 3 notifications ✅
         → Tapping each routes to correct screen ✅
```

---

## Delivery Matrix

| Scenario | Notifications delivered? | AlertScreen history? |
|---|---|---|
| Phone offline, server running, < 100 alerts, < 4 weeks | ✅ All delivered on reconnect | ✅ Always complete |
| Phone offline, server running, > 100 alerts | ⚠️ Only latest 100 FCM pushes | ✅ Always complete |
| Phone offline, server also off | ❌ No new alerts generated | ✅ Past alerts still cached |
| Phone killed (no background), server running | ✅ FCM delivers on reconnect | ✅ Always complete |
| Phone offline, reconnects via mobile data | ✅ Delivered | ✅ Always complete |
| Phone offline, reconnects via WiFi | ✅ Delivered | ✅ Always complete |

---

## FCM Collapse Key Behavior

If the server sends multiple alerts of the **same type** for the same device
while the phone is offline, FCM may collapse them into one notification.

**Example:**
```
Server sends 3 'silent' alerts for DEVICE1234 while phone is offline
  → FCM may deliver only 1 'silent' notification on reconnect
  → But alertLogs has all 3 entries ✅
  → AlertScreen shows all 3 ✅
```

This only affects the **notification count** — never the alert history.
The parent may see fewer notification banners than expected, but
`AlertScreen` always shows the complete record.

---

## Requirements for Pending Delivery to Work

| Requirement | Notes |
|---|---|
| Server must have been running when alert fired | If server was off, no alert was generated |
| Phone must reconnect to internet | WiFi or mobile data — either works |
| FCM token must be valid | Re-saved automatically on every login |
| App must be installed | FCM token is tied to the app installation |
| Reconnect within 4 weeks | FCM drops messages older than 4 weeks |

---

## What the Parent Should Do After Being Offline

1. **Reconnect to internet** — WiFi or mobile data
2. **Wait a few seconds** — FCM delivers queued pushes automatically
3. **Check notification tray** — all pending alerts will appear
4. **Open AlertScreen** — tap the bell icon to see the complete alert history
   with timestamps, even if some FCM notifications were collapsed or dropped

---

## Summary

SafeTrack never loses an alert as long as the server was running when the
event occurred. The RTDB is the permanent record. FCM is the doorbell.
Even if the doorbell misses a ring, the record is always there.

```
RTDB alertLogs  ← permanent record, always complete
FCM pushes      ← doorbell, best-effort, up to 100 pending
AlertScreen     ← reads RTDB directly, always shows full history
```