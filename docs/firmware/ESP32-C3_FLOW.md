# SafeTrack ESP32-C3 Firmware — Flow Diagrams v4.4

> **Firmware Version:** 4.4 (GPRS-Resilient Build)
> **Key changes from v4.2:** SOS retry queue, non-blocking GPRS check, honest LED feedback, GPRS guards

---

## 1. Boot / Setup Flow

```mermaid
flowchart TD
    A([Power ON]) --> B[Serial Monitor 115200]
    B --> C[GPIO Init<br/>RED=8 OUT · GRN=3 OUT<br/>SOS_BTN=2 INPUT_PULLUP]
    C --> D[I2C Init<br/>SDA=6 · SCL=7]
    D --> E[initMAX17043<br/>Quick-start via Wire]
    E --> F[readBattery<br/>SOC register 0x04<br/>batteryPct = 0–100%]
    F --> G[UART1 Start<br/>RX=20 · TX=21 · 115200]
    G --> H[modem.restart<br/>AT+CRESET]
    H --> I{Modem OK?}
    I -- No --> J[⚠️ Log warning<br/>Continue anyway]
    I -- Yes --> K
    J --> K[modem.enableGPS<br/>AT+CGPS=1]
    K --> L[connectNetwork]

    L --> L1{isGprsConnected?}
    L1 -- Yes --> L5[Already connected]
    L1 -- No --> L2[waitForNetwork<br/>30s timeout]
    L2 --> L3{Registered?}
    L3 -- No --> L4[❌ Timeout<br/>Return — no GPRS]
    L3 -- Yes --> L4b[gprsConnect APN]
    L4b --> L5

    L4 --> M[authenticateDevice]
    L5 --> M

    M --> M1[HTTP GET<br/>realDevices.json]
    M1 --> M2{200 OK?}
    M2 -- No --> FAIL[❌ Empty response]
    M2 -- Yes --> M3[Parse JSON<br/>Loop entries]
    M3 --> M4{deviceCode<br/>matches?}
    M4 -- No --> M3
    M4 -- Yes --> M5{actionOwnerID<br/>exists?}
    M5 -- No --> FAIL
    M5 -- Yes --> M6[userUid = actionOwnerID<br/>deviceUid = entry key]

    FAIL --> HALT[❌ Not Authorized<br/>Blink RED forever<br/>HALT]
    M6 --> OK[✅ isAuthorized = true<br/>GREEN ×3 blink]
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

    A -- Yes --> B[handleSOS<br/>called every ~10ms]
    B --> C{now − lastUpdateMs<br/>≥ 30000ms?}
    C -- No --> D[delay 10ms]
    D --> LOOP

    C -- Yes --> E[lastUpdateMs = now]
    E --> F[readBattery<br/>I2C MAX17043<br/>always works — no GPRS needed]
    F --> G{isGprsConnected?}
    G -- No --> H[connectNetwork<br/>try to recover GPRS<br/>max 30s wait]
    H --> I
    G -- Yes --> I[readGPS<br/>AT+CGPSINFO via TinyGSM<br/>always works — satellite]

    I --> I1{lat≠0 AND lon≠0?}
    I1 -- Yes --> I2[gpsValid = true<br/>Update gpsLat gpsLon gpsAlt<br/>Save to lastLat lastLon lastAlt]
    I1 -- No --> I3[gpsValid = false<br/>Use cached lastLat lastLon]
    I2 --> J
    I3 --> J

    J[trySendPendingSOS<br/>check RAM queue first] --> K

    K[sendLocationLog<br/>returns bool logOk] --> L[sendDeviceStatus]

    L --> M{logOk == true?}
    M -- Yes --> N[GREEN blink ×2<br/>✅ cycle success]
    M -- No --> O[No green blink<br/>silent — GPRS issue]
    N --> D
    O --> D
```

---

## 3. GPRS State Machine

> This is the connectivity spectrum — not just on/off.

```mermaid
flowchart LR
    S1(["STATE 1<br/>Full Connection<br/>isGprsConnected=true<br/>HTTP 200/201"])
    S2(["STATE 2<br/>Weak Signal<br/>isGprsConnected=true<br/>HTTP timeout/fail"])
    S3(["STATE 3<br/>GPRS Dropped<br/>isGprsConnected=false<br/>Can re-register"])
    S4(["STATE 4<br/>No Internet<br/>isGprsConnected=false<br/>No tower reachable"])

    S1 -- signal weakens --> S2
    S2 -- signal lost --> S3
    S3 -- no tower at all --> S4
    S4 -- tower found --> S3
    S3 -- re-registers --> S2
    S2 -- signal strong --> S1

    subgraph outcomes["What happens in each state"]
        O1["STATE 1 ✅<br/>All data sent normally<br/>Green blink ×2"]
        O2["STATE 2 ⚠️<br/>Guard passes — HTTP tried<br/>May timeout → Red blink<br/>SOS queued if fails<br/>Retries next cycle"]
        O3["STATE 3 ⚠️<br/>Fix 4 guard exits instantly<br/>connectNetwork() called<br/>Data skipped this cycle<br/>SOS queued in RAM"]
        O4["STATE 4 ❌<br/>Fix 4 guard exits instantly<br/>Data lost this cycle<br/>SOS queued — retried 30s<br/>Device never hangs"]
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
    B -- No --> C[⚠️ Log: skipped<br/>return FALSE instantly<br/>no HTTP attempt]
    B -- Yes --> D[Pick coordinates<br/>gpsValid? → current lat lon alt<br/>else → lastLat lastLon lastAlt]
    D --> E[Build JSON payload<br/>latitude · longitude · altitude<br/>speed · accuracy · locationType<br/>sos · batteryLevel<br/>timestamp .sv · lastUpdate .sv]
    E --> F[AT+HTTPINIT<br/>AT+HTTPPARA URL<br/>AT+HTTPDATA payload<br/>AT+HTTPACTION=1 POST]
    F --> G{HTTP 200 or 201?}
    G -- Yes --> H[✅ return TRUE<br/>deviceLogs push OK]
    G -- No --> I[❌ blinkRed ×3<br/>return FALSE]
```

---

## 5. sendDeviceStatus — With GPRS Guard

```mermaid
flowchart TD
    A([sendDeviceStatus called]) --> B{isGprsConnected?}
    B -- No --> C[⚠️ Log: skipped<br/>return instantly]
    B -- Yes --> D[Build JSON payload<br/>batteryLevel · sos<br/>lastLocation lat lon alt<br/>lastUpdate .sv]
    D --> E[POST + ?x-http-method-override=PATCH<br/>linkedDevices/uid/devices<br/>/DEVICE1234/deviceStatus.json]
    E --> F{HTTP 200 or 201?}
    F -- Yes --> G[✅ deviceStatus PATCH OK]
    F -- No --> H[❌ blinkRed ×2]
```

---

## 6. SOS Handler — Full Flow with GPRS Resilience

> Called every ~10ms. Non-blocking. Uses millis() only — no delay().

```mermaid
flowchart TD
    SOS([handleSOS called]) --> AC{sosActive AND<br/>now−sosActivatedAt<br/>≥ 60000ms?}
    AC -- Yes --> AC1[sosActive = false<br/>LED OFF<br/>Auto-cancelled]
    AC -- No --> BTN
    AC1 --> BTN

    BTN[digitalRead GPIO2] --> P{Button LOW?<br/>held down}

    P -- YES --> Q{sosHolding<br/>already?}
    Q -- No --> Q1[sosHolding = true<br/>sosPressStart = now<br/>Log: hold for 3s...]
    Q -- Yes --> R
    Q1 --> R

    R{sosActive<br/>already?}
    R -- Yes --> LED
    R -- No --> S{now−sosPressStart<br/>≥ 3000ms?}
    S -- No --> LED
    S -- Yes --> T[sosActive = true<br/>sosActivatedAt = now<br/>flashSOS LED Morse S·O·S]

    T --> U{isGprsConnected?}

    U -- YES GPRS UP --> V[sendLocationLog<br/>returns sent bool]
    V --> V2[sendDeviceStatus]
    V2 --> W{sent == true?}
    W -- Yes --> W1[✅ SOS delivered<br/>sosPending.valid stays false]
    W -- No --> X[⚠️ HTTP failed<br/>Queue SOS in RAM<br/>sosPending.valid = true<br/>sosPending.lat lon alt battery<br/>sosPending.queuedAt = now]

    U -- NO GPRS DOWN --> Y[⚠️ No GPRS<br/>Queue immediately<br/>sosPending.valid = true<br/>sosPending.lat lon alt battery<br/>sosPending.queuedAt = now<br/>No blocking HTTP attempt]

    W1 --> LED
    X --> LED
    Y --> LED

    P -- NO released --> Z{sosHolding<br/>was true?}
    Z -- No --> LED
    Z -- Yes --> Z1{sosActive?}
    Z1 -- No --> Z2[Log: released early<br/>held X.Xs need 3s]
    Z1 -- Yes --> Z3[SOS active<br/>no change]
    Z2 --> Z4[sosHolding = false]
    Z3 --> Z4
    Z4 --> LED

    LED{sosActive?}
    LED -- Yes --> LED1[Toggle RED<br/>now/500 % 2<br/>1Hz blink]
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
    C --> D{age ≥ 300000ms<br/>5 minutes TTL?}
    D -- Yes --> E[sosPending.valid = false<br/>Log: TTL expired — discarded]
    E --> RET

    D -- No --> F{isGprsConnected?}
    F -- No --> G[Log: still no GPRS<br/>age Xs — wait next cycle]
    G --> RET

    F -- Yes --> H[Build retry payload<br/>using stored sosPending values<br/>latitude · longitude · altitude<br/>sos=true · batteryLevel<br/>locationType=cached · accuracy=30m<br/>timestamp .sv · lastUpdate .sv]
    H --> I[HTTP POST<br/>deviceLogs/uid/DEVICE1234.json]
    I --> J{HTTP 200/201?}

    J -- Yes --> K[✅ SOS delivered!<br/>sosPending.valid = false<br/>Queue cleared<br/>sendDeviceStatus to update sos flag]
    J -- No --> L[❌ Retry failed<br/>sosPending.valid stays true<br/>will retry next 30s cycle]
    K --> RET
    L --> RET
```

---

## 8. What Keeps Working Without Internet

```mermaid
flowchart LR
    subgraph always["✅ Always Works — No Internet Needed"]
        A1[GPS Satellite<br/>modem.getGPS<br/>Satellite receiver<br/>independent of 4G]
        A2[Battery Reading<br/>MAX17043 I2C<br/>Wire.requestFrom<br/>no network involved]
        A3[SOS Button<br/>digitalRead GPIO2<br/>every 10ms<br/>pure hardware]
        A4[SOS LED<br/>digitalWrite RED_PIN<br/>pure hardware]
        A5[30s Cycle Timer<br/>millis internal clock<br/>always running]
        A6[Serial Monitor<br/>USB serial<br/>always works]
    end

    subgraph needs["❌ Needs Internet — Stops Without GPRS"]
        B1[deviceLogs POST<br/>needs Firebase REST<br/>via 4G LTE]
        B2[deviceStatus PATCH<br/>needs Firebase REST<br/>via 4G LTE]
        B3[SOS immediate push<br/>queued in RAM<br/>delivered when back]
        B4[App online status<br/>no timestamp update<br/>shows Offline after 5min]
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
        L1[🔴 RED continuous<br/>blink forever] --> M1[Not authorized<br/>Check Firebase realDevices]
        L2[🟢 GREEN ×3 blink] --> M2[Authorized<br/>Ready to track]
    end

    subgraph normal["Normal Operation"]
        L3[🟢 GREEN ×2<br/>every 30s] --> M3[deviceLogs POST success<br/>FIX 3 — only blinks if data sent]
        L4[No blink after 30s] --> M4[GPRS issue this cycle<br/>FIX 3 — silent on failure]
        L5[🔴 RED ×3] --> M5[deviceLogs POST failed<br/>HTTP error or timeout]
        L6[🔴 RED ×2] --> M6[deviceStatus PATCH failed]
    end

    subgraph sos["SOS State"]
        L7[🔴 RED Morse S·O·S<br/>rapid pattern] --> M7[SOS just activated<br/>flashSOS called]
        L8[🔴 RED slow 1Hz blink] --> M8[SOS active<br/>60s window running]
        L9[RED goes OFF] --> M9[SOS auto-cancelled<br/>60s elapsed]
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