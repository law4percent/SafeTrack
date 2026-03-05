# SafeTrack ESP32-C3 Firmware — Flow Diagrams v4.4

> **Firmware Version:** 4.4 (GPRS-Resilient Build)
> **Key changes from v4.2:** SOS retry queue, non-blocking GPRS check, honest LED feedback, GPRS guards

---

## 1. Boot / Setup Flow

```mermaid
flowchart TD
    A([Power ON]) --> B[Serial Monitor 115200]
    B --> C[GPIO Init\nRED=8 OUT · GRN=3 OUT\nSOS_BTN=2 INPUT_PULLUP]
    C --> D[I2C Init\nSDA=6 · SCL=7]
    D --> E[initMAX17043\nQuick-start via Wire]
    E --> F[readBattery\nSOC register 0x04\nbatteryPct = 0–100%]
    F --> G[UART1 Start\nRX=20 · TX=21 · 115200]
    G --> H[modem.restart\nAT+CRESET]
    H --> I{Modem OK?}
    I -- No --> J[⚠️ Log warning\nContinue anyway]
    I -- Yes --> K
    J --> K[modem.enableGPS\nAT+CGPS=1]
    K --> L[connectNetwork]

    L --> L1{isGprsConnected?}
    L1 -- Yes --> L5[Already connected]
    L1 -- No --> L2[waitForNetwork\n30s timeout]
    L2 --> L3{Registered?}
    L3 -- No --> L4[❌ Timeout\nReturn — no GPRS]
    L3 -- Yes --> L4b[gprsConnect APN]
    L4b --> L5

    L4 --> M[authenticateDevice]
    L5 --> M

    M --> M1[HTTP GET\nrealDevices.json]
    M1 --> M2{200 OK?}
    M2 -- No --> FAIL[❌ Empty response]
    M2 -- Yes --> M3[Parse JSON\nLoop entries]
    M3 --> M4{deviceCode\nmatches?}
    M4 -- No --> M3
    M4 -- Yes --> M5{actionOwnerID\nexists?}
    M5 -- No --> FAIL
    M5 -- Yes --> M6[userUid = actionOwnerID\ndeviceUid = entry key]

    FAIL --> HALT[❌ Not Authorized\nBlink RED forever\nHALT]
    M6 --> OK[✅ isAuthorized = true\nGREEN ×3 blink]
    OK --> LOOP([Enter Main Loop])
```

---

## 2. Main Loop — Full Cycle

> Every iteration ≈ 10ms. SOS checked every iteration. Firebase update every 30s.

```mermaid
flowchart TD
    LOOP([loop start]) --> A{isAuthorized?}
    A -- No --> A1[blinkRed · delay 1s · return]
    A1 --> LOOP

    A -- Yes --> B[handleSOS\ncalled every ~10ms]
    B --> C{now − lastUpdateMs\n≥ 30000ms?}
    C -- No --> D[delay 10ms]
    D --> LOOP

    C -- Yes --> E[lastUpdateMs = now]
    E --> F[readBattery\nI2C MAX17043\nalways works — no GPRS needed]
    F --> G{isGprsConnected?}
    G -- No --> H[connectNetwork\ntry to recover GPRS\nmax 30s wait]
    H --> I
    G -- Yes --> I[readGPS\nAT+CGPSINFO via TinyGSM\nalways works — satellite]

    I --> I1{lat≠0 AND lon≠0?}
    I1 -- Yes --> I2[gpsValid = true\nUpdate gpsLat gpsLon gpsAlt\nSave to lastLat lastLon lastAlt]
    I1 -- No --> I3[gpsValid = false\nUse cached lastLat lastLon]
    I2 --> J
    I3 --> J

    J[trySendPendingSOS\ncheck RAM queue first] --> K

    K[sendLocationLog\nreturns bool logOk] --> L[sendDeviceStatus]

    L --> M{logOk == true?}
    M -- Yes --> N[GREEN blink ×2\n✅ cycle success]
    M -- No --> O[No green blink\nsilent — GPRS issue]
    N --> D
    O --> D
```

---

## 3. GPRS State Machine

> This is the connectivity spectrum — not just on/off.

```mermaid
flowchart LR
    S1(["STATE 1\nFull Connection\nisGprsConnected=true\nHTTP 200/201"])
    S2(["STATE 2\nWeak Signal\nisGprsConnected=true\nHTTP timeout/fail"])
    S3(["STATE 3\nGPRS Dropped\nisGprsConnected=false\nCan re-register"])
    S4(["STATE 4\nNo Internet\nisGprsConnected=false\nNo tower reachable"])

    S1 -- signal weakens --> S2
    S2 -- signal lost --> S3
    S3 -- no tower at all --> S4
    S4 -- tower found --> S3
    S3 -- re-registers --> S2
    S2 -- signal strong --> S1

    subgraph outcomes["What happens in each state"]
        O1["STATE 1 ✅\nAll data sent normally\nGreen blink ×2"]
        O2["STATE 2 ⚠️\nGuard passes — HTTP tried\nMay timeout → Red blink\nSOS queued if fails\nRetries next cycle"]
        O3["STATE 3 ⚠️\nFix 4 guard exits instantly\nconnectNetwork() called\nData skipped this cycle\nSOS queued in RAM"]
        O4["STATE 4 ❌\nFix 4 guard exits instantly\nData lost this cycle\nSOS queued — retried 30s\nDevice never hangs"]
    end

    S1 --- O1
    S2 --- O2
    S3 --- O3
    S4 --- O4
```

---

## 4. sendLocationLog — With GPRS Guard

```mermaid
flowchart TD
    A([sendLocationLog called]) --> B{isGprsConnected?}
    B -- No --> C[⚠️ Log: skipped\nreturn FALSE instantly\nno HTTP attempt]
    B -- Yes --> D[Pick coordinates\ngpsValid? → current lat lon alt\nelse → lastLat lastLon lastAlt]
    D --> E[Build JSON payload\nlatitude · longitude · altitude\nspeed · accuracy · locationType\nsos · batteryLevel\ntimestamp .sv · lastUpdate .sv]
    E --> F[AT+HTTPINIT\nAT+HTTPPARA URL\nAT+HTTPDATA payload\nAT+HTTPACTION=1 POST]
    F --> G{HTTP 200 or 201?}
    G -- Yes --> H[✅ return TRUE\ndeviceLogs push OK]
    G -- No --> I[❌ blinkRed ×3\nreturn FALSE]
```

---

## 5. sendDeviceStatus — With GPRS Guard

```mermaid
flowchart TD
    A([sendDeviceStatus called]) --> B{isGprsConnected?}
    B -- No --> C[⚠️ Log: skipped\nreturn instantly]
    B -- Yes --> D[Build JSON payload\nbatteryLevel · sos\nlastLocation lat lon alt\nlastUpdate .sv]
    D --> E[POST + ?x-http-method-override=PATCH\nlinkedDevices/uid/devices\n/DEVICE1234/deviceStatus.json]
    E --> F{HTTP 200 or 201?}
    F -- Yes --> G[✅ deviceStatus PATCH OK]
    F -- No --> H[❌ blinkRed ×2]
```

---

## 6. SOS Handler — Full Flow with GPRS Resilience

> Called every ~10ms. Non-blocking. Uses millis() only — no delay().

```mermaid
flowchart TD
    SOS([handleSOS called]) --> AC{sosActive AND\nnow−sosActivatedAt\n≥ 60000ms?}
    AC -- Yes --> AC1[sosActive = false\nLED OFF\nAuto-cancelled]
    AC -- No --> BTN
    AC1 --> BTN

    BTN[digitalRead GPIO2] --> P{Button LOW?\nheld down}

    P -- YES --> Q{sosHolding\nalready?}
    Q -- No --> Q1[sosHolding = true\nsosPressStart = now\nLog: hold for 3s...]
    Q -- Yes --> R
    Q1 --> R

    R{sosActive\nalready?}
    R -- Yes --> LED
    R -- No --> S{now−sosPressStart\n≥ 3000ms?}
    S -- No --> LED
    S -- Yes --> T[sosActive = true\nsosActivatedAt = now\nflashSOS LED Morse S·O·S]

    T --> U{isGprsConnected?}

    U -- YES GPRS UP --> V[sendLocationLog\nreturns sent bool]
    V --> V2[sendDeviceStatus]
    V2 --> W{sent == true?}
    W -- Yes --> W1[✅ SOS delivered\nsosPending.valid stays false]
    W -- No --> X[⚠️ HTTP failed\nQueue SOS in RAM\nsosPending.valid = true\nsosPending.lat lon alt battery\nsosPending.queuedAt = now]

    U -- NO GPRS DOWN --> Y[⚠️ No GPRS\nQueue immediately\nsosPending.valid = true\nsosPending.lat lon alt battery\nsosPending.queuedAt = now\nNo blocking HTTP attempt]

    W1 --> LED
    X --> LED
    Y --> LED

    P -- NO released --> Z{sosHolding\nwas true?}
    Z -- No --> LED
    Z -- Yes --> Z1{sosActive?}
    Z1 -- No --> Z2[Log: released early\nheld X.Xs need 3s]
    Z1 -- Yes --> Z3[SOS active\nno change]
    Z2 --> Z4[sosHolding = false]
    Z3 --> Z4
    Z4 --> LED

    LED{sosActive?}
    LED -- Yes --> LED1[Toggle RED\nnow/500 % 2\n1Hz blink]
    LED -- No --> LED2[RED off]
    LED1 --> RET([return])
    LED2 --> RET
```

---

## 7. trySendPendingSOS — Retry Queue

> Called at the start of every 30s update cycle.

```mermaid
flowchart TD
    A([trySendPendingSOS called]) --> B{sosPending.valid?}
    B -- No --> RET([return — nothing queued])

    B -- Yes --> C[age = now − sosPending.queuedAt]
    C --> D{age ≥ 300000ms\n5 minutes TTL?}
    D -- Yes --> E[sosPending.valid = false\nLog: TTL expired — discarded]
    E --> RET

    D -- No --> F{isGprsConnected?}
    F -- No --> G[Log: still no GPRS\nage Xs — wait next cycle]
    G --> RET

    F -- Yes --> H[Build retry payload\nusing stored sosPending values\nlatitude · longitude · altitude\nsos=true · batteryLevel\nlocationType=cached · accuracy=30m\ntimestamp .sv · lastUpdate .sv]
    H --> I[HTTP POST\ndeviceLogs/uid/DEVICE1234.json]
    I --> J{HTTP 200/201?}

    J -- Yes --> K[✅ SOS delivered!\nsosPending.valid = false\nQueue cleared\nsendDeviceStatus to update sos flag]
    J -- No --> L[❌ Retry failed\nsosPending.valid stays true\nwill retry next 30s cycle]
    K --> RET
    L --> RET
```

---

## 8. What Keeps Working Without Internet

```mermaid
flowchart LR
    subgraph always["✅ Always Works — No Internet Needed"]
        A1[GPS Satellite\nmodem.getGPS\nSatellite receiver\nindependent of 4G]
        A2[Battery Reading\nMAX17043 I2C\nWire.requestFrom\nno network involved]
        A3[SOS Button\ndigitalRead GPIO2\nevery 10ms\npure hardware]
        A4[SOS LED\ndigitalWrite RED_PIN\npure hardware]
        A5[30s Cycle Timer\nmillis internal clock\nalways running]
        A6[Serial Monitor\nUSB serial\nalways works]
    end

    subgraph needs["❌ Needs Internet — Stops Without GPRS"]
        B1[deviceLogs POST\nneeds Firebase REST\nvia 4G LTE]
        B2[deviceStatus PATCH\nneeds Firebase REST\nvia 4G LTE]
        B3[SOS immediate push\nqueued in RAM\ndelivered when back]
        B4[App online status\nno timestamp update\nshows Offline after 5min]
    end
```

---

## 9. Full End-to-End Data Flow — v4.4

```mermaid
sequenceDiagram
    participant BTN as SOS Button
    participant ESP as ESP32-C3
    participant GSM as SIM7600E-H1C
    participant FB as Firebase RTDB
    participant APP as Flutter App
    participant AI as Gemini AI

    Note over ESP: Every 30 seconds — normal cycle
    ESP->>ESP: readBattery via I2C MAX17043
    ESP->>GSM: AT+CGPSINFO
    GSM-->>ESP: lat, lon, alt, speed
    ESP->>ESP: trySendPendingSOS — check queue
    ESP->>GSM: isGprsConnected?
    GSM-->>ESP: true/false

    alt GPRS connected
        ESP->>GSM: POST deviceLogs JSON
        GSM->>FB: latitude longitude speed sos batteryLevel timestamp lastUpdate
        FB-->>APP: onValue → live map updates
        ESP->>GSM: POST+PATCH deviceStatus
        GSM->>FB: batteryLevel sos lastLocation lastUpdate
        FB-->>APP: onValue → dashboard card updates
        ESP->>ESP: GREEN blink ×2
    else GPRS down
        ESP->>ESP: Fix 4 guard → skip HTTP instantly
        ESP->>ESP: No green blink — silent cycle
    end

    Note over BTN: Child holds button 3 seconds
    BTN->>ESP: GPIO2 LOW for ≥ 3000ms
    ESP->>ESP: sosActive = true
    ESP->>ESP: flashSOS Morse LED ~2.75s

    alt GPRS up at SOS moment
        ESP->>GSM: POST deviceLogs sos=true
        GSM->>FB: Emergency entry pushed
        FB-->>APP: SOS notification triggered
        ESP->>GSM: PATCH deviceStatus sos=true
        GSM->>FB: deviceStatus.sos = true
        FB-->>APP: Dashboard SOS banner shown
    else GPRS down at SOS moment
        ESP->>ESP: Fix 2 — queue in RAM instantly
        ESP->>ESP: sosPending.valid = true
        Note over ESP: No blocking — returns immediately
        Note over ESP: Next 30s cycle — trySendPendingSOS
        ESP->>GSM: GPRS recovered? POST queued SOS
        GSM->>FB: Delayed SOS entry with locationType=cached
        FB-->>APP: Late SOS notification delivered
    end

    Note over APP: Parent asks AI assistant
    APP->>FB: Read deviceLogs + deviceStatus
    FB-->>APP: Location history + battery + SOS state
    APP->>AI: Firebase context + parent question
    AI-->>APP: Response + follow-up question
```

---

## 10. LED Indicator Reference — v4.4

```mermaid
flowchart LR
    subgraph boot["Startup"]
        L1[🔴 RED continuous\nblink forever] --> M1[Not authorized\nCheck Firebase realDevices]
        L2[🟢 GREEN ×3 blink] --> M2[Authorized\nReady to track]
    end

    subgraph normal["Normal Operation"]
        L3[🟢 GREEN ×2\nevery 30s] --> M3[deviceLogs POST success\nFIX 3 — only blinks if data sent]
        L4[No blink after 30s] --> M4[GPRS issue this cycle\nFIX 3 — silent on failure]
        L5[🔴 RED ×3] --> M5[deviceLogs POST failed\nHTTP error or timeout]
        L6[🔴 RED ×2] --> M6[deviceStatus PATCH failed]
    end

    subgraph sos["SOS State"]
        L7[🔴 RED Morse S·O·S\nrapid pattern] --> M7[SOS just activated\nflashSOS called]
        L8[🔴 RED slow 1Hz blink] --> M8[SOS active\n60s window running]
        L9[RED goes OFF] --> M9[SOS auto-cancelled\n60s elapsed]
    end
```

---

## 11. SOS Retry Queue — State Machine

```mermaid
stateDiagram-v2
    [*] --> Empty : Power on

    Empty --> Queued : SOS triggered\nGPRS down OR HTTP failed
    Queued --> Delivering : GPRS recovered\ntrySendPendingSOS called
    Delivering --> Empty : HTTP 200/201\nSOS delivered ✅
    Delivering --> Queued : HTTP failed\nRetry next 30s cycle
    Queued --> Expired : age > 5 minutes\nTTL exceeded
    Expired --> Empty : sosPending.valid = false

    note right of Queued
        sosPending struct
        valid = true
        lat, lon, alt stored
        battery stored
        queuedAt timestamp
        Size = 24 bytes RAM only
    end note

    note right of Empty
        sosPending.valid = false
        No RAM held
        No retry attempts
    end note
```