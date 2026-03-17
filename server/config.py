# SafeTrack/server/config.py
#
# Central configuration for all server monitors.
# Edit values here — never hardcode them in monitor files.

import pytz

# ── Timezone ──────────────────────────────────────────────────────────────────
TIMEZONE = pytz.timezone("Asia/Manila")  # PHT (UTC+8)

# ── Firebase ──────────────────────────────────────────────────────────────────
# Path to your Firebase service account key.
# Download from: Firebase Console → Project Settings → Service Accounts
SERVICE_ACCOUNT_PATH = "serviceAccountKey.json"

# Your Firebase Realtime Database URL.
# Format: https://<project-id>-default-rtdb.firebaseio.com
DATABASE_URL = "https://safetrack-76a0c-default-rtdb.asia-southeast1.firebasedatabase.app/"

# ── Deviation monitor ─────────────────────────────────────────────────────────
# Cooldown between deviation alerts for the same device + route.
DEVIATION_COOLDOWN_MINUTES = 5

# ── Silence monitor ───────────────────────────────────────────────────────────
# How long a device must be silent before firing a 'silent' alert.
SILENCE_THRESHOLD_MINUTES = 15

# How long before re-alerting if the device stays silent.
SILENCE_REALER_COOLDOWN_MINUTES = 30

# ── Behavior monitor ──────────────────────────────────────────────────────────
# Cron interval for behavior + silence checks (minutes).
BEHAVIOR_CRON_INTERVAL_MINUTES = 5

# Grace period after schoolTimeIn before firing a 'late' alert.
LATE_GRACE_PERIOD_MINUTES = 15

# Maximum device logs to fetch per device per check.
BEHAVIOR_LOG_LIMIT = 200

# Hour (24h) after which movement is considered anomalous.
ANOMALY_NIGHT_HOUR = 22   # 22:00

# Hour (24h) before which movement is considered anomalous.
ANOMALY_EARLY_HOUR = 5    # 05:00

# ── RTDB paths ────────────────────────────────────────────────────────────────
# Read paths
PATH_LINKED_DEVICES   = "linkedDevices"
PATH_DEVICE_LOGS      = "deviceLogs"
PATH_DEVICE_PATHS     = "devicePaths"
PATH_USERS            = "users"

# Write paths
PATH_ALERT_LOGS       = "alertLogs"
PATH_SERVER_COOLDOWNS = "serverCooldowns"