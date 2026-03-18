# SafeTrack Server

The always-on Python monitoring backend for the SafeTrack student safety system.

---

## What It Does

The server is the **sole monitor and informer** in the SafeTrack system. It watches
all linked student devices in real time and sends push notifications to the parent's
phone when something needs attention.

The Flutter app is the **displayer only** — it receives notifications from the server
and shows alert history to the parent. It performs no active monitoring.

```
ESP32 Device → Firebase RTDB → Server → FCM → Parent's Phone → App
```

---

## Alert Types

| Type | Detection | Frequency |
|---|---|---|
| `sos` | Child presses emergency button | Real-time, immediate |
| `deviation` | Child moves off registered route | Real-time, 5-min cooldown |
| `late` | No GPS near school after grace period | Cron every 5 min, once per day |
| `absent` | Zero GPS activity during school hours | Cron every 5 min, once per day |
| `anomaly` | Movement after 22:00 or before 05:00 | Cron every 5 min, once per day |
| `silent` | Device stops transmitting for 15+ min | Cron every 5 min, re-alerts every 30 min |

---

## Requirements

- Python 3.10 or higher
- A Firebase project with Realtime Database enabled
- `serviceAccountKey.json` from Firebase Console
- Internet connection (outbound only — no open ports required)

---

## Setup

**1. Get your Firebase service account key**

Go to Firebase Console → Project Settings → Service Accounts →
Generate new private key → save as `serviceAccountKey.json` in this folder.

**2. Set your database URL in `config.py`**

```python
DATABASE_URL = "https://<your-project-id>-default-rtdb.firebaseio.com"
```

**3. Install dependencies**

```bash
pip install -r requirements.txt
```

**4. Run the server**

```bash
python main.py
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
Attaches one RTDB listener per device watching
`deviceLogs/{uid}/{code}`. On each new GPS entry it runs a Haversine
calculation against all active registered routes. If the child is beyond
the deviation threshold, it fires an alert with a 5-minute cooldown per
device per route. Cooldown is stored in RTDB so it survives server restarts.

### Cron Monitors (every 5 minutes)

**`behavior_monitor.py`**
Fetches the last 200 device logs scoped to today for each enabled device.
Checks three conditions against the device's school schedule:
- **Late** — first GPS ping during school hours was after grace period
- **Absent** — no GPS pings during school hours after grace period
- **Anomaly** — GPS movement detected after 22:00 or before 05:00

Uses `alertLogs` as the dedup source — checks if the alert type has already
fired today before writing a new one.

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
[2026-03-17 07:05:01.123] [INFO] [main.py:45] Server is running
[2026-03-17 07:05:02.456] [INFO] [deviation_monitor.py:88] Deviation: Juan 85m from Morning Route
[2026-03-17 07:05:02.789] [INFO] [fcm_sender.py:62] FCM sent to uid_parent_A
[2026-03-17 07:10:01.001] [INFO] [behavior_monitor.py:112] late alert fired for Maria
[2026-03-17 07:15:00.333] [ERROR] [main.py:78] Silence check error: connection timeout
```

All console output is color-coded by log type for easy reading during development.

---

## Multiple Parents and Devices

The server monitors **all parent accounts and all their devices simultaneously**.
It reads the entire `linkedDevices` tree on startup and attaches listeners or
runs checks for every enabled device it finds. FCM pushes are routed to each
parent's own FCM token — notifications never cross between accounts.

When a parent enables or disables a device in the app, the server detects the
change in real time and starts or stops that device's listeners automatically.

---

## Stopping the Server

Press `Ctrl+C` or send `SIGTERM`. The server shuts down cleanly — all threads
stop and a final log entry is written.

---

## Configuration Reference (`config.py`)

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

- `serviceAccountKey.json` grants full Firebase Admin access. Never commit it to git.
- Add `serviceAccountKey.json` to `.gitignore` immediately.
- The server only needs outbound internet access — no open ports or public IP required.
- All Firebase reads and writes are scoped to the minimum needed paths.
