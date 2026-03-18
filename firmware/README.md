# SafeTrack — ESP32-C3 Super Mini Tracker Firmware

> **Version:** 4.4 (GPRS-resilient Build) | **Platform:** ESP32-C3 Super Mini | **Framework:** Arduino (C/C++)

---

## Overview

This directory contains the firmware for the SafeTrack IoT tracker device — the hardware component carried by the child. The firmware runs on an **ESP32-C3 Super Mini** microcontroller and is responsible for:

- Reading GPS coordinates from the **SIM7600E-H1C** module
- Reading battery percentage from the **MAX17043** fuel gauge
- Detecting SOS button press events
- Transmitting all data to **Firebase Realtime Database** via 4G LTE cellular

The device operates fully autonomously. Once powered on and authorized, it requires no interaction — it silently sends location and status updates every 2 minutes until powered off.

---

## Hardware Bill of Materials

| Component | Model | Role |
|---|---|---|
| Microcontroller | ESP32-C3 Super Mini | Main firmware execution, GPIO, I2C, UART |
| Cellular + GPS Module | SIM7600E-H1C | 4G LTE data transmission + GPS receiver |
| Battery Fuel Gauge | MAX17043 | Accurate battery percentage via I2C |
| Battery Charger | TP4056 | Single-cell LiPo charging with protection |
| Boost Converter | MT3608 | Steps 3.7V LiPo up to 5V for SIM module |
| Battery | LiFePO4 3.7V 2000mAh | Primary power source (~8–12hr operation) |
| Push Button | Momentary tactile | SOS emergency trigger |
| LEDs | Red + Green | Status indicators |

---

## Pin Configuration

| Signal | GPIO | Direction | Connected To |
|---|---|---|---|
| UART RX | GPIO 4 | Input | SIM7600E-H1C TX |
| UART TX | GPIO 5 | Output | SIM7600E-H1C RX |
| I2C SDA | GPIO 6 | Bidirectional | MAX17043 SDA |
| I2C SCL | GPIO 7 | Output | MAX17043 SCL |
| SOS Button | GPIO 2 | Input (PULLUP) | Push button → GND |
| Red LED | GPIO 8 | Output | LED → GND |
| Green LED | GPIO 3 | Output | LED → GND |

> **Note:** The ESP32-C3 Super Mini has a different GPIO layout than the original ESP32. GPIOs 17, 21, 22, 26, 27 from the original ESP32 do not exist on the C3. This firmware is specifically configured for the C3 Super Mini pinout.

---

## Firmware Architecture

### Boot Sequence (`setup()`)

1. Initialize Serial Monitor at 115200 baud
2. Configure GPIO pins (LED outputs, SOS button input with pull-up)
3. Initialize I2C bus and MAX17043 fuel gauge (quick-start command)
4. Start UART1 for SIM7600E-H1C communication (RX=4, TX=5)
5. Restart modem via TinyGSM (`modem.restart()`)
6. Connect to Globe 4G network via GPRS (APN: `http.globe.com.ph`)
7. **Authenticate device** — read `realDevices` node from Firebase, match `DEVICE_CODE` constant to `deviceCode` field, extract `actionOwnerID` as `userUid`
8. If authorized: 3 green blinks → enable GPS and wait up to 60 seconds for a first fix (red blinks while waiting)
9. If GPS fix acquired: log coordinates and enter main loop
10. If no fix within 60 seconds: log warning and enter main loop anyway (will retry each update cycle)
11. If not authorized: continuous red blink → halt

### Main Loop (`loop()`)

The loop runs approximately every 10ms. Two things happen:

**Every iteration (~10ms):**
- `handleSOS()` is called to poll the SOS button state non-blocking

**Every 2 minutes:**
- Read battery percentage from MAX17043
- Reconnect GPRS if dropped
- Attempt to resend any queued SOS (see SOS Retry Queue below)
- Read GPS via `modem.getGPS()` with up to 3 attempts, 2 seconds apart
- Call `sendLocationLog()` — POST to `deviceLogs` (push entry)
- Call `sendDeviceStatus()` — PATCH to `linkedDevices/.../deviceStatus`
- Blink green LED ×2 on success

### SOS Detection

The SOS handler uses a **non-blocking hold detection** pattern:
- Button must be held for a continuous **3 seconds** before SOS activates
- This prevents accidental triggers from brief bumps
- When hold threshold is reached: `sosActive = true`, LED flashes Morse S·O·S, and Firebase is updated **immediately** (out-of-cycle push)
- SOS **auto-cancels after 60 seconds** without any button interaction
- While SOS is active, the red LED blinks at 1Hz to provide visual confirmation

### SOS Retry Queue

If a GPRS connection is unavailable when SOS is triggered, the SOS payload is saved to a `SosPending` struct in memory and retried at the start of each subsequent update cycle. The retry window is **5 minutes (300,000ms)**. If GPRS is not restored within that window, the queued SOS is discarded and a warning is logged to Serial.

This ensures SOS alerts are delivered even if the network drops momentarily at the moment of activation.

---

## Firebase Data Flow

The firmware writes to **two separate paths** in Firebase Realtime Database:

### 1. `deviceLogs/{userUid}/{deviceCode}/{pushId}`

Written via HTTP **POST** — Firebase generates a unique push ID for each entry, creating a permanent history log. The Flutter app reads this as an ordered time series for live map display, movement history, and AI context queries.

```json
{
  "latitude": 10.31672,
  "longitude": 123.89071,
  "altitude": 15.2,
  "speed": 0.5,
  "accuracy": 5.0,
  "locationType": "gps",
  "sos": false,
  "batteryLevel": 87,
  "timestamp": { ".sv": "timestamp" },
  "lastUpdate": { ".sv": "timestamp" }
}
```

> **Note:** `batteryLevel` and `lastUpdate` are now included in every `deviceLogs` entry, in addition to `deviceStatus`.

### 2. `linkedDevices/{userUid}/devices/{deviceCode}/deviceStatus`

Written via HTTP **POST with `?x-http-method-override=PATCH`** — Firebase treats this as a PATCH operation, merging/overwriting the flat fields at this exact node without creating push-ID children. This is the "latest snapshot" the Flutter dashboard reads for battery level, SOS status, and last known location.

```json
{
  "batteryLevel": 87,
  "sos": false,
  "lastLocation": {
    "latitude": 10.31672,
    "longitude": 123.89071,
    "altitude": 15.2
  },
  "lastUpdate": { ".sv": "timestamp" }
}
```

> **Why PATCH override?** The SIM7600E-H1C AT command set does not support HTTP PUT or PATCH natively. Firebase REST API accepts `?x-http-method-override=PATCH` as a query parameter to simulate PATCH behaviour from a standard POST request.

### Authentication Path Read

```
realDevices/{deviceUid}/deviceCode      → matched against DEVICE_CODE constant
realDevices/{deviceUid}/actionOwnerID   → stored as userUid for all subsequent writes
```

---

## Dependencies

Install these libraries in Arduino IDE or PlatformIO before compiling:

| Library | Version | Purpose |
|---|---|---|
| TinyGSM | ≥ 0.11.x | SIM7600 modem abstraction (GPRS, GPS) |
| ArduinoJson | ≥ 6.x | JSON serialization for Firebase payloads |
| Wire (built-in) | — | I2C communication with MAX17043 |
| HardwareSerial (built-in) | — | UART1 for SIM7600E-H1C |

### Arduino IDE Board Setup

1. In Arduino IDE: **File → Preferences → Additional Board Manager URLs**
2. Add: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
3. **Tools → Board Manager** → search "esp32" → install **esp32 by Espressif Systems**
4. Select board: **ESP32C3 Dev Module**
5. Set Upload Speed: **115200**
6. Set CPU Frequency: **160MHz**

---

## Configuration

Open `safetrack_firmware.ino` and change these two constants before flashing:

```cpp
// Line 57 — must match the deviceCode in Firebase realDevices node
const String DEVICE_CODE = "DEVICE1234";

// Line 53–54 — must match your Firebase project URL
const String FIREBASE_URL =
    "https://your-project-default-rtdb.region.firebasedatabase.app";
```

The APN is pre-configured for Globe Philippines:
```cpp
const char APN[] = "http.globe.com.ph";
```
Change this if using a different carrier. Common APNs:

| Carrier | APN |
|---|---|
| Globe | `http.globe.com.ph` |
| Smart | `internet` |
| DITO | `internet.dito.ph` |

---

## LED Status Reference

| Pattern | Meaning |
|---|---|
| 🔴 Red continuous blink on startup | Not authorized — device not registered in Firebase |
| 🔴 Red blink every 3s (after auth) | Waiting for GPS fix at startup |
| 🟢 Green ×3 blink on startup | Authorized — ready to track |
| 🟢 Green ×2 blink every 2 min | Update cycle successful |
| 🔴 Red ×3 blink | `deviceLogs` POST failed |
| 🔴 Red ×2 blink | `deviceStatus` PATCH failed |
| 🔴 Red 1Hz slow blink | SOS active (60-second window) |
| 🔴 Red Morse S·O·S | SOS just activated — immediate push sent |

---

## How GPS Works

The SIM7600E-H1C has a built-in GPS receiver. TinyGSM wraps the `AT+CGPSINFO` command into `modem.getGPS()`. The firmware:

1. **At startup:** waits up to 60 seconds for an initial GPS fix, blinking red every 3 seconds while waiting
2. **Each update cycle:** calls `modem.getGPS(&lat, &lon, &alt, &spd, &hdg)` up to **3 times** with a 2-second delay between attempts
3. Validates the result — if `lat == 0 && lon == 0`, the fix is invalid
4. If valid: updates current and cached (`lastLat`, `lastLon`, `lastAlt`) values
5. If invalid after all attempts: uses cached values and sets `locationType = "cached"` with `accuracy = 50.0`

**GPS cold start** (device just powered on outdoors) typically takes 30–90 seconds to get a first fix. Keep the device in open sky for best results.

**GPS accuracy field** in the payload is estimated:
- `5.0m` when GPS fix is valid
- `30.0m` when using cached location in an SOS retry payload
- `50.0m` when using cached location in a regular update

---

## Power Budget (Estimated)

| Component | Current Draw |
|---|---|
| ESP32-C3 active | ~20mA |
| SIM7600E-H1C (4G active) | ~300–500mA peak, ~50mA idle |
| MAX17043 | ~50µA |
| LEDs | ~10mA each when on |
| **Estimated average** | **~80–120mA sustained** |

With a 2000mAh battery and MT3608 boost efficiency ~85%:
- **Effective capacity:** ~1700mAh at 5V equivalent
- **Estimated runtime:** 8–12 hours depending on cellular activity

---

## Known Limitations

- **No RTC clock** — device timestamp relies on Firebase server-side `{".sv":"timestamp"}`. The device itself does not know the current time.
- **No persistent offline buffering** — only the most recent SOS event is queued in memory for retry. If the device is power-cycled while a SOS is queued, it is lost. Regular location updates that fail while GPRS is down are not retried.
- **SOS retry TTL** — queued SOS alerts are discarded after 5 minutes if GPRS is not restored.
- **GPS indoors** — satellite signal may not penetrate thick concrete. Cached location is used as fallback.
- **SOS blocks for ~2.75s** — the Morse LED pattern in `flashSOS()` uses `delay()` and blocks the loop. The Firebase push fires immediately after it completes.
- **String heap fragmentation** — URL construction uses Arduino `String` concatenation. On ESP32-C3 with 400KB SRAM this is not a practical problem but could cause instability after very long runtimes (12+ hours continuous).

---

## File Structure

```
ESP32_code/
└── safetrack_firmware/
    └── safetrack_firmware.ino   ← Main firmware file (all-in-one)
```

---

## Acknowledgments

- **TinyGSM** library by Volodymyr Shymanskyy — modem abstraction
- **ArduinoJson** by Benoît Blanchon — JSON serialization
- **Espressif Systems** — ESP32-C3 Arduino core
- **SIMCom** — SIM7600E-H1C AT command documentation
- **Maxim Integrated** (now Analog Devices) — MAX17043 datasheet