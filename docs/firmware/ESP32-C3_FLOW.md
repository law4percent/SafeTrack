# SafeTrack ESP32-C3 Firmware — Flow Diagrams

> **Firmware Version:** 4.2 | **Hardware:** ESP32-C3 Super Mini + SIM7600E-H1C

---

## 1. Boot / Setup Flow

```mermaid
flowchart TD
    A([Power ON]) --> B[Serial Monitor begin 115200]
    B --> C[Init GPIO\nRED_PIN=8 OUT\nGRN_PIN=3 OUT\nSOS_BTN=2 INPUT_PULLUP]
    C --> D[Init I2C\nSDA=6 SCL=7]
    D --> E[initMAX17043\nQuick-start command\nvia Wire I2C]
    E --> F[readBattery\nRead SOC register 0x04\nReturn batteryPct %]
    F --> G[Start UART1\nRX=20 TX=21\n115200 baud]
    G --> H[modem.restart\nAT+CRESET]
    H --> I{Modem OK?}
    I -- No --> J[⚠️ Log warning\nContinue anyway]
    I -- Yes --> K[modem.enableGPS\nAT+CGPS=1]
    J --> K
    K --> L[connectNetwork]

    L --> L1{GPRS already\nconnected?}
    L1 -- Yes --> L4
    L1 -- No --> L2[modem.waitForNetwork\n30s timeout]
    L2 --> L3{Network\nregistered?}
    L3 -- No --> L_fail[❌ Log timeout\nReturn — no GPRS]
    L3 -- Yes --> L4[modem.gprsConnect\nAPN: http.globe.com.ph]
    L4 --> L5{GPRS\nconnected?}
    L5 -- No --> L_fail2[❌ Log failure]
    L5 -- Yes --> L6[✅ Log IP address]

    L6 --> M[authenticateDevice]
    L_fail --> M
    L_fail2 --> M

    M --> M1[HTTP GET\nrealDevices.json]
    M1 --> M2{Response\n200 OK?}
    M2 -- No --> M_fail[❌ Empty response]
    M2 -- Yes --> M3[Parse JSON\nloop all entries]
    M3 --> M4{deviceCode\nmatches\nDEVICE_CODE?}
    M4 -- No --> M3
    M4 -- Yes --> M5{actionOwnerID\npresent and\nnot null?}
    M5 -- No --> M_fail
    M5 -- Yes --> M6[Set userUid\nSet deviceUid\nReturn true]

    M_fail --> AUTH_FAIL[❌ Not authorized\nBlink RED forever\nHALT]
    M6 --> AUTH_OK[✅ isAuthorized = true\nBlink GREEN ×3]
    AUTH_OK --> LOOP([Enter loop])
```

---

## 2. Main Loop Flow

```mermaid
flowchart TD
    LOOP([loop start]) --> A{isAuthorized?}
    A -- No --> A1[blinkRed\ndelay 1s\nreturn]
    A1 --> LOOP

    A -- Yes --> B[handleSOS\ncalled every iteration\n~10ms cycle]
    B --> C{now - lastUpdateMs\n>= 30000ms?}
    C -- No --> D[delay 10ms]
    D --> LOOP

    C -- Yes --> E[lastUpdateMs = now]
    E --> F[readBattery\nbatteryPct updated]
    F --> G{modem.isGprs\nConnected?}
    G -- No --> H[connectNetwork\nreconnect GPRS]
    H --> I
    G -- Yes --> I[readGPS]

    I --> I1[modem.getGPS\nAT+CGPSINFO via TinyGSM]
    I1 --> I2{lat != 0\nAND lon != 0?}
    I2 -- Yes --> I3[Update gpsLat gpsLon\ngpsAlt gpsSpeed\nSave to lastLat lastLon lastAlt\ngpsValid = true]
    I2 -- No --> I4[gpsValid = false\nUse cached lastLat lastLon]

    I3 --> J[sendLocationLog]
    I4 --> J

    J --> J1[Build JSON payload\nlatitude longitude altitude\nspeed accuracy locationType\nsos timestamp .sv]
    J1 --> J2[HTTP POST\ndeviceLogs/userUid/DEVICE1234.json]
    J2 --> J3{HTTP 200\nor 201?}
    J3 -- Yes --> J4[✅ deviceLogs push OK]
    J3 -- No --> J5[❌ blinkRed ×3]

    J4 --> K[sendDeviceStatus]
    J5 --> K

    K --> K1[Build JSON payload\nbatteryLevel sos\nlastLocation lastUpdate .sv]
    K1 --> K2[HTTP POST\nlinkedDevices/uid/devices\n/DEVICE1234/deviceStatus.json\n?x-http-method-override=PATCH]
    K2 --> K3{HTTP 200\nor 201?}
    K3 -- Yes --> K4[✅ deviceStatus PATCH OK]
    K3 -- No --> K5[❌ blinkRed ×2]

    K4 --> L[blinkGreen ×2]
    K5 --> L
    L --> D
```

---

## 3. SOS Handler Flow

> Called on **every loop iteration** (~every 10ms). Non-blocking — uses `millis()` only, no `delay()`.

```mermaid
flowchart TD
    SOS([handleSOS called]) --> A{sosActive AND\nnow - sosActivatedAt\n>= 60000ms?}
    A -- Yes --> A1[sosActive = false\nLED OFF\nAuto-cancelled]
    A -- No --> B
    A1 --> B

    B[Read GPIO2\ndigitalRead SOS_BTN] --> C{Button\nstate LOW?\npulled up}

    C -- YES button held --> D{sosHolding\nalready true?}
    D -- No --> D1[sosHolding = true\nsosPressStart = now\nLog: keep holding...]
    D -- Yes --> E
    D1 --> E

    E{sosActive already\ntrue?}
    E -- Yes --> F[Skip activation\nalready active]
    E -- No --> G{now - sosPressStart\n>= 3000ms?}
    G -- No --> H[Still counting...\nno action yet]
    G -- Yes --> I[sosActive = true\nsosActivatedAt = now\nLog: SOS ACTIVATED]
    I --> I1[flashSOS\nMorse S·O·S on RED LED\n~2.75s blocking]
    I1 --> I2[sendLocationLog\nImmediate push with sos=true]
    I2 --> I3[sendDeviceStatus\nImmediate PATCH with sos=true]

    C -- NO button released --> J{sosHolding\nwas true?}
    J -- No --> K[No action]
    J -- Yes --> J1{sosActive?}
    J1 -- No --> J2[Log: released early\nheld X.Xs need 3s]
    J1 -- Yes --> J3[SOS stays active\nno change]
    J2 --> J4[sosHolding = false]
    J3 --> J4

    F --> LED
    H --> LED
    I3 --> LED
    K --> LED
    J4 --> LED

    LED{sosActive?}
    LED -- Yes --> LED1[Blink RED\nnow/500 % 2 == 0\n1Hz toggle]
    LED -- No --> LED2[RED stays OFF\nunless blinkRed called]
    LED1 --> RET([return])
    LED2 --> RET
```

---

## 4. Firebase Write Flow

```mermaid
flowchart LR
    subgraph ESP32["ESP32-C3 Super Mini"]
        A[GPS Fix\nLat Lon Alt Speed] --> C
        B[Battery %\nfrom MAX17043] --> C
        S[SOS Flag\nfrom handleSOS] --> C
        C[Build JSON Payload]
    end

    subgraph HTTP["SIM7600E-H1C — 4G LTE"]
        C --> D1[AT+HTTPINIT\nAT+HTTPPARA URL\nAT+HTTPDATA\nAT+HTTPACTION=1]
    end

    subgraph Firebase["Firebase RTDB"]
        D1 -->|POST — push ID| E1["deviceLogs/
        {userUid}/DEVICE1234/
        {-pushId}
        ──────────────
        latitude
        longitude
        altitude
        speed
        accuracy
        locationType
        sos
        timestamp"]

        D1 -->|POST + PATCH override| E2["linkedDevices/
        {userUid}/devices/DEVICE1234/
        deviceStatus
        ──────────────
        batteryLevel
        sos
        lastLocation
        lastUpdate"]
    end

    subgraph Flutter["Flutter Parent App"]
        E1 -->|onValue stream| F1[Live Map\nRoute Deviation\nAI Context]
        E2 -->|onValue stream| F2[Dashboard Card\nBattery %\nSOS Alert]
    end
```

---

## 5. Device Authentication Flow

```mermaid
flowchart TD
    A([authenticateDevice called]) --> B[HTTP GET\nfirebaseURL/realDevices.json]
    B --> C{HTTP 200?}
    C -- No --> FAIL([return false])
    C -- Yes --> D[Read response body\nAT+HTTPREAD=0,4096]
    D --> E[Extract JSON\nbetween first { and last }]
    E --> F{JSON parse\nsuccessful?}
    F -- No --> FAIL
    F -- Yes --> G[Loop each entry\nin realDevices object]
    G --> H{Has key\ndeviceCode?}
    H -- No --> G
    H -- Yes --> I{deviceCode ==\nDEVICE_CODE\nconstant?}
    I -- No --> G
    I -- Yes --> J{Has key\nactionOwnerID?}
    J -- No --> FAIL
    J -- Yes --> K{actionOwnerID\nnot empty\nnot null?}
    K -- No --> FAIL
    K -- Yes --> L[deviceUid = entry key\nuserUid = actionOwnerID]
    L --> SUCCESS([return true])
```

---

## 6. LED Status Code Reference

```mermaid
flowchart LR
    subgraph Startup
        A1[🔴 RED blinking\ncontinuously] --> B1[Device not authorized\nCheck Firebase realDevices]
        A2[🟢 GREEN ×3 blink] --> B2[Authorized successfully\nReady to track]
    end

    subgraph Normal Operation
        C1[🟢 GREEN ×2 blink\nevery 30s] --> D1[Update cycle complete\nFire base push OK]
        C2[🔴 RED ×3 blink] --> D2[deviceLogs POST failed\nCheck GPRS signal]
        C3[🔴 RED ×2 blink] --> D3[deviceStatus PATCH failed\nCheck GPRS signal]
    end

    subgraph SOS
        E1[🔴 RED slow blink\n1Hz toggle] --> F1[SOS is ACTIVE\nEmergency in progress]
        E2[🔴 RED Morse S·O·S\nfast pattern] --> F2[SOS just activated\nImmediate push triggered]
    end
```

---

## 7. Data Flow Summary

```mermaid
sequenceDiagram
    participant BTN as SOS Button
    participant ESP as ESP32-C3
    participant GSM as SIM7600E-H1C
    participant FB as Firebase RTDB
    participant APP as Flutter App
    participant AI as Gemini AI

    Note over ESP: Every 30 seconds
    ESP->>GSM: AT+CGPSINFO
    GSM-->>ESP: lat, lon, alt, speed
    ESP->>GSM: Wire I2C MAX17043
    GSM-->>ESP: battery %
    ESP->>GSM: AT+HTTPACTION=1 POST deviceLogs
    GSM->>FB: { lat, lon, alt, speed, sos, timestamp }
    FB-->>APP: onValue stream → live map update
    ESP->>GSM: AT+HTTPACTION=1 POST deviceStatus + PATCH
    GSM->>FB: { batteryLevel, sos, lastLocation }
    FB-->>APP: onValue stream → dashboard card update

    Note over BTN: Parent/child holds 3s
    BTN->>ESP: GPIO2 LOW for >= 3000ms
    ESP->>ESP: sosActive = true\nflashSOS LED
    ESP->>GSM: Immediate POST deviceLogs sos=true
    GSM->>FB: Emergency entry pushed
    FB-->>APP: SOS notification triggered
    ESP->>GSM: Immediate PATCH deviceStatus sos=true
    GSM->>FB: deviceStatus.sos = true
    FB-->>APP: Dashboard SOS banner shown

    Note over APP: Parent asks AI
    APP->>FB: Read deviceLogs + deviceStatus
    FB-->>APP: Real-time context data
    APP->>AI: Context + question → Gemini API
    AI-->>APP: Response with follow-up question
```