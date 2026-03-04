# SafeTrack Tracker Device — Setup & User Guide

**For Parents of Elementary School Students**

---

## What Is the SafeTrack Device?

The SafeTrack device is a small GPS tracker your child carries to school. It automatically sends your child's location to your SafeTrack app every 30 seconds using a Globe SIM card and 4G cellular data. You do not need to configure the device daily — once it is set up and assigned to your account, it works automatically every time you power it on.

---

## What's Inside the Box

| Item | Description |
|---|---|
| SafeTrack Tracker | The main device your child will carry |
| USB Charging Cable | Micro-USB or USB-C depending on your unit |
| Device Code Card | A card with your unique **Device Code** (e.g. `DEVICE1234`) |

> **Important:** Keep your Device Code card safe. You will need it to link the device to your app account.

---

## Part 1 — First-Time Setup

### Step 1 — Install the SafeTrack App

1. Download the **SafeTrack** app on your Android phone.
2. Open the app and create an account using your email and password.
3. Log in.

---

### Step 2 — Link the Device to Your Account

1. In the app, go to **My Children** from the bottom navigation bar.
2. Tap the **+** button to add a child.
3. Enter your **child's name** (e.g. Diane).
4. Enter the **Device Code** from your card (e.g. `DEVICE1234`).
5. Tap **Link Device**.

Your child's name will now appear on the Dashboard.

> **Note:** The device must be registered in the system by your school or SafeTrack administrator before this step works. If linking fails, contact your school.

---

### Step 3 — Insert the SIM Card

1. Locate the SIM card slot on the SafeTrack device (on the side or back panel).
2. Insert a **Globe SIM card** with an active mobile data subscription.
   - Any Globe prepaid or postpaid SIM with data works.
   - The device uses approximately **5–15 MB per day** under normal tracking.
3. Press the SIM card until it clicks into place.

> **No Wi-Fi required.** The device uses cellular data (4G LTE) to send location updates — it works anywhere with Globe signal.

---

### Step 4 — Charge the Device Before First Use

1. Connect the charging cable to the device's charging port.
2. Plug the other end into a USB power source (wall adapter or power bank).
3. The LED indicator will show:
   - 🔴 **Red LED solid or slow pulse** — charging in progress
   - 🟢 **Green LED** or LED off — fully charged
4. Allow **2–3 hours** for a full charge from empty.

> **Battery life:** Approximately 8–12 hours of continuous GPS tracking on a full charge. Charge the device every night.

---

### Step 5 — Power On the Device

1. Press and hold the **power button** for 2 seconds until the LEDs respond.
2. Watch the LED sequence during startup:

| LED Behavior | What It Means |
|---|---|
| No light | Device is off or battery is dead |
| 🔴 Red blinking rapidly | Starting up — modem and GPS initializing |
| 🔴 Red blinking continuously | ❌ Device not authorized — see Troubleshooting |
| 🟢 Green blinks 3 times | ✅ Device authorized and ready to track |

3. After the **3 green blinks**, the device is tracking. You should see your child's location appear in the app within **1–2 minutes**.

---

### Step 6 — Confirm Tracking in the App

1. Open the SafeTrack app on your phone.
2. On the Dashboard, check your child's card:
   - **Green dot** = device is online and sending updates
   - **Battery percentage** = current charge level of the device
3. Tap **📍 Location** to open the live map and confirm the location is showing correctly.

---

## Part 2 — Daily Use

### Powering On Each Morning

1. Press and hold the power button for 2 seconds.
2. Wait for the **3 green blinks** — this means the device is authorized and connected.
3. Hand the device to your child.

> The device automatically connects to Globe cellular data and begins sending GPS updates every 30 seconds. No further action is needed.

---

### Powering Off

Press and hold the power button for 3 seconds until the LEDs turn off.

Power off the device when:
- Your child has arrived safely at home
- The device is charging overnight
- The device will not be used for an extended period

---

### Charging Daily Routine

| Time | Action |
|---|---|
| After school (afternoon) | Power off device, connect charger |
| Overnight | Leave connected to charger |
| Morning | Disconnect charger, power on, hand to child |

---

### What Your Child Needs to Know

Your child only needs to know **one thing**: how to use the SOS button in an emergency.

**Tell your child:**
> "If you are in danger or need help, press and hold the red button for 3 seconds until the light flashes rapidly. This will immediately send an emergency alert to me."

The child does **not** need to unlock anything, open any app, or have a phone. The SOS button works as long as the device is powered on and has cellular signal.

---

## Part 3 — Using the SOS Button

### What the SOS Button Does

The SOS button is the **large push button** on the device. When held for 3 seconds:
1. The red LED flashes a rapid Morse code pattern (S·O·S)
2. An emergency alert is immediately sent to Firebase
3. Your SafeTrack app receives a high-priority push notification
4. The Dashboard shows a red SOS banner on your child's card
5. The SOS remains active for **60 seconds**, then automatically resets

### How to Trigger SOS (for your child)

1. **Press and hold** the button firmly
2. **Keep holding** — a count of 3 seconds is needed
3. The LED will flash rapidly — **this confirms SOS was sent**
4. Release the button

### What You See as a Parent

- Your phone vibrates with a high-priority notification: **"🚨 SOS Alert — [Child Name]"**
- Tapping the notification opens the Live Location map immediately
- The red SOS banner appears on the Dashboard until the 60-second window expires
- The AI assistant will also report SOS status if you ask

### Accidentally Triggered SOS

If the SOS was pressed by mistake:
- It will **automatically cancel after 60 seconds** — no action needed from you
- The device does not call anyone or make noise — it only sends a data alert to your app
- Simply confirm with your child that they are safe

---

## Part 4 — Understanding the LED Indicators

| LED Pattern | Meaning | What To Do |
|---|---|---|
| 🟢 Green blinks ×3 on startup | ✅ Authorized and ready | Nothing — normal startup |
| 🟢 Green blinks ×2 every 30s | ✅ Update sent successfully | Nothing — normal operation |
| 🔴 Red blinks ×3 | ❌ Location update failed | Check cellular signal area |
| 🔴 Red blinks continuously on startup | ❌ Not authorized | Contact school/administrator |
| 🔴 Red slow blink (1 per second) | 🚨 SOS is active | Check on your child |
| 🔴 Red rapid Morse pattern | 🚨 SOS just activated | Check app immediately |
| No LED | Device is off or battery dead | Charge the device |

---

## Part 5 — Battery and Charging

### Checking Battery Level

You do not need to physically check the device. The battery percentage is visible in two places:
1. **Dashboard** — shown on your child's card
2. **AI Assistant** — ask "What is the battery level of the device?"

### Low Battery Warning

When battery drops below 20%:
- The app displays a low battery warning on the Dashboard card
- The AI assistant will mention low battery when reporting device status

### When the Device Runs Out of Battery

- The device will stop sending location updates
- Your child's card will show **Offline** status after 5 minutes of no updates
- The last known location will still be visible on the map

**Always charge the device overnight to avoid this situation.**

---

## Part 6 — Troubleshooting

### Device shows Offline in the app

1. Check that the device is powered on (LEDs should respond).
2. Check that the Globe SIM card is properly inserted.
3. Check that the SIM has an active data balance.
4. Move to an area with better Globe cellular signal.
5. If the red LED blinks continuously at startup, see below.

### Red LED blinks continuously at startup (not authorizing)

This means the device cannot find its registration in the system.

1. Confirm the Device Code was entered correctly in the app (My Children → link device).
2. Ask your school administrator to verify the device is registered in Firebase under `realDevices`.
3. Ensure your account's User ID is set as the `actionOwnerID` for this device.

### Location is showing the wrong area

- Wait 1–2 minutes after power on for the GPS to get a satellite fix outdoors.
- If the child is indoors or in a basement, GPS accuracy decreases. The device will use the last known outdoor location.
- The location type badge in the app shows `gps` (accurate) or `cached` (last known).

### SOS was triggered but I got no notification

1. Check that SafeTrack app notifications are **Allowed** in your phone Settings → Apps → SafeTrack → Notifications.
2. Check that your phone is not in Do Not Disturb mode.
3. Verify your phone has an internet connection.

### Device gets very hot during charging

This is not normal. Disconnect the charger immediately and do not use the device until it cools down. The TP4056 charging circuit has overcharge protection, but using non-standard chargers may cause issues. Use only the provided cable and a standard 5V USB adapter.

---

## Part 7 — Care and Maintenance

- **Keep the device dry.** It is not waterproof. Do not expose to rain or submerge in water.
- **Do not drop the device** on hard surfaces — the SIM card slot and internal components may be damaged.
- **Charge with a standard 5V USB adapter.** Fast chargers exceeding 5V may damage the TP4056 charging circuit.
- **Store in a dry place** when not in use.
- **Clean with a dry cloth only** — do not use liquids or solvents.

---

## Quick Reference Card

> Print this and keep it with the device.

```
SafeTrack Device — Quick Reference
────────────────────────────────────
Device Code   : ________________
Child Name    : ________________
Parent Phone  : ________________

POWER ON      : Hold power button 2 seconds
               Wait for 3 green blinks = READY

POWER OFF     : Hold power button 3 seconds

SOS           : Hold SOS button 3 seconds
               Rapid red LED = SENT

CHARGING      : USB cable to power source
               Red LED = charging
               Green/Off = full

DAILY ROUTINE :
  Morning   → Power on → Give to child
  Afternoon → Power off → Charge overnight
────────────────────────────────────
```