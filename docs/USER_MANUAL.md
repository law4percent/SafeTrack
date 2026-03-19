# SafeTrack User Manual

**Version 1.0**
**For Parents of Elementary School Students**

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Getting Started](#2-getting-started)
3. [Dashboard](#3-dashboard)
4. [Live Location](#4-live-location)
5. [My Children](#5-my-children)
6. [Route Registration](#6-route-registration)
7. [AI Assistant](#7-ai-assistant)
8. [Notifications & Alerts](#8-notifications--alerts)
9. [Device & Battery Status](#9-device--battery-status)
10. [Troubleshooting](#10-troubleshooting)
11. [Frequently Asked Questions](#11-frequently-asked-questions)

---

## 1. Introduction

Welcome to **SafeTrack** — a child safety monitoring system designed to give parents
peace of mind during their child's school commute and throughout the school day.

SafeTrack works through three components working together:

- **The SafeTrack Device** — a small, custom-built tracker your child carries.
  It automatically sends their GPS location every 2 minutes and immediately on
  emergency.
- **The SafeTrack App** — installed on your smartphone, it shows your child's
  location on a live map, displays alerts, and lets you ask an AI assistant
  safety questions.
- **The SafeTrack Server** — a background monitoring program running on a laptop.
  It watches your child's device in real time and sends push notifications directly
  to your phone whenever something needs your attention.

**You do not need any technical knowledge to use this app.** This manual will walk
you through everything step by step.

> **Note:** For alerts to work reliably, the SafeTrack Server must be running on
> the designated laptop during school hours. If the server is off, SOS alerts will
> still work — but route deviation, behavior, and device silence alerts will not fire.

---

## 2. Getting Started

### 2.1 Creating Your Account

1. Open the **SafeTrack** app on your phone.
2. Tap **Sign Up** on the login screen.
3. Enter your **email address** and a **password** (minimum 6 characters).
4. Tap **Create Account**.
5. You will be taken directly to the Dashboard.

### 2.2 Logging In

1. Open the SafeTrack app.
2. Enter your registered **email** and **password**.
3. Tap **Log In**.

> **Tip:** If you forget your password, tap **Forgot Password?** and a reset link
> will be sent to your email.

### 2.3 Linking Your Child's Device

Before you can track your child, you need to link their SafeTrack device to your
account.

1. From the Dashboard, tap **My Children**.
2. Tap the **+ LINK DEVICE** button.
3. Enter:
   - Your child's **name**
   - The **Device Code** printed on the back of the SafeTrack device
   - Year level and section (optional)
   - **School Time In** and **School Time Out** (important — used for alerts)
4. Tap **Link Device**.
5. Once linked, your child's name will appear in the list.

> **Important:** Set your child's school schedule (Time In and Time Out) when
> linking the device. Without a schedule, late arrival, absence, and device
> silence alerts will not fire.

> **Important:** Each device has a unique code. Enter it exactly as printed,
> including all letters and numbers.

---

## 3. Dashboard

The Dashboard is your home screen. It gives you a quick overview of all your
linked children.

### What You'll See

- **Child Card** — one card per linked child, showing:
  - Child's name and photo
  - Online / Offline status (green dot = online, grey = offline)
  - Battery level with color indicator
  - GPS availability
  - Last known coordinates
  - SOS / SAFE status chip

### SOS Alert on Dashboard

If your child presses the emergency button on their device, a **red SOS banner**
will appear on their card immediately and you will receive a push notification.
See [Section 8](#8-notifications--alerts) for more details.

---

## 4. Live Location

The Live Location screen shows your child's current position on an interactive
map, updated in real time.

### 4.1 Opening Live Location

From the Dashboard, tap **Live Locations** from the bottom navigation bar to
see all children at once.

### 4.2 Reading the Map

| Symbol | Meaning |
|---|---|
| 🔵 Blue circle with child icon | Your child's current position |
| 🟢 Green circle | Start point of a registered route |
| 🔴 Red circle | End point of a registered route |
| Green dotted line | Your child's registered safe route |

### 4.3 Map Controls

- **Pinch to zoom** — zoom in or out
- **Drag** — pan the map
- **Re-center button** — tap the crosshair icon to snap the map back to your
  child's position

### 4.4 Full Screen Map

Tap **Full Screen Map** at the bottom of the card to open a larger map view.
This view also shows your child's coordinates and a live update indicator.

### 4.5 Online vs. Offline

- **Online (green):** The device sent a location update within the last 5 minutes.
- **Offline (grey):** No update received in more than 5 minutes. This may mean the
  device is off, out of cellular range, or has a low battery.

> **Tip:** If your child's device shows Offline for more than 15 minutes during
> school hours, you will receive a **Device Silent** alert automatically.

### 4.6 Location Type

The device reports how its location was determined:

- **GPS** — satellite-based, most accurate (within ~5 meters). Used for all
  monitoring and alerts.
- **Cached** — last known GPS position, used when a fresh fix is not available.
  Cached locations are shown but not used for deviation or behavior alerts.

---

## 5. My Children

This screen manages all your linked devices and children.

### 5.1 Enabling / Disabling Tracking

Each child card has a toggle switch at the top. Turn it **off** to temporarily
pause all monitoring for that device — for example, during weekends or holidays.

> **Important:** When a device is disabled, the server stops all monitoring for
> it. You will not receive any alerts (deviation, late, absent, anomaly, or
> device silence) until you re-enable it.

### 5.2 Editing Child Information

Tap the **edit (pencil)** icon on a child's card to update:
- Child's name, year level, section, and photo
- **School Time In** — the expected arrival time at school (e.g., 07:30)
- **School Time Out** — the expected end of school hours (e.g., 17:00)

> **Keep the school schedule accurate.** The server uses these times to decide
> when to check for late arrivals, absences, anomalies, and device silence.

### 5.3 Managing Routes

Tap the **route (road)** icon on a child's card to open the Route Manager for
that child. See [Section 6](#6-route-registration) for details.

### 5.4 Unlinking a Device

Tap the **delete (trash)** icon on a child's card and confirm.

> **Note:** Unlinking does not delete alert history. It only removes the device
> from your active monitoring list.

---

## 6. Route Registration

Routes let you define the safe path your child should travel — for example,
from home to school. If your child goes outside this path, you will receive a
**Route Deviation** alert.

### 6.1 Opening the Route Manager

From My Children, tap the **🛣️ route** icon on your child's card.

### 6.2 Viewing Existing Routes

The Route List screen shows all routes registered for that child. Each route
displays:
- Route name
- Number of waypoints
- Deviation threshold
- Active / Paused toggle

### 6.3 Creating a New Route

1. Tap the **+ Add Route** button (floating button, bottom right).
2. The map editor will open.
3. **Enter a route name** at the top (e.g., "Morning Route").
4. **Tap on the map** to drop waypoints along your child's expected path:
   - The first waypoint is marked **S** (Start) in green
   - The last waypoint is marked **E** (End) in red
   - Middle waypoints are numbered in blue
5. **Set the deviation threshold** by adjusting the slider (20m–200m).
6. Tap **Save Route** when done.

> **Tip:** Add more waypoints along turns and corners for more accurate monitoring.

### 6.4 Understanding Deviation Threshold

| Threshold | Best For |
|---|---|
| 20–30m | Narrow streets, strict paths |
| 50m (default) | Typical school routes |
| 100–200m | Wide areas, rural paths |

### 6.5 Pausing a Route

Use the toggle switch on any route card to pause monitoring without deleting
the route. A paused route will not trigger deviation alerts.

### 6.6 Deleting a Route

Tap the **Delete** icon on a route card and confirm. This cannot be undone.

---

## 7. AI Assistant

The AI Assistant is a chat interface powered by Google Gemini. It can answer
questions about your child's safety using real data from their device.

### 7.1 Opening the AI Assistant

Tap **Ask AI** from the bottom navigation bar.

### 7.2 What You Can Ask

**Location & Whereabouts**
- "Where is Juan right now?"
- "Has my child left school?"
- "Where did my child go this morning?"

**Safety & Emergencies**
- "Did my child press the emergency button today?"
- "Is there any unusual movement today?"
- "What should I do if I get an SOS alert?"

**Battery & Device Status**
- "What is the battery level of Juan's device?"
- "Why is the tracker not showing on the map?"

**Child Status**
- "Has my child arrived at school?"
- "What time did my child's device first appear near school today?"

### 7.3 Suggestion Chips

At the start of a conversation, tap any quick suggestion chip to jump to common
questions without typing.

---

## 8. Notifications & Alerts

SafeTrack sends push notifications to your phone whenever your child needs
attention. Notifications are sent by the SafeTrack Server — they reach your
phone even when the app is completely closed.

### 8.1 Types of Notifications

| Notification | Icon | What It Means |
|---|---|---|
| **SOS Alert** | 🆘 | Your child pressed the emergency button on their device. Requires immediate attention. |
| **Route Deviation** | ⚠️ | Your child has moved more than [threshold] meters from their registered route. |
| **Late Arrival** | ⏰ | Your child's device was not detected near school by the expected arrival time + 15 minutes. |
| **Possible Absence** | 📋 | No GPS activity detected at all during school hours today. Your child may not have gone to school. |
| **Unusual Activity** | ⚠️ | Movement detected at unusual hours (after 10:00 PM or before 5:00 AM). |
| **Device Silent** | 📡 | Your child's device has not sent any data for 15+ minutes during school hours. The device may be off, out of battery, or without signal. |

### 8.2 Viewing All Alerts

Tap the **Alerts** tab (bell icon) in the app to see the full history of all
alerts. You can filter by type:

| Filter | Shows |
|---|---|
| All | Every alert |
| SOS | Emergency button presses |
| Off Route | Route deviation alerts |
| Late | Late arrival alerts |
| Absent | Possible absence alerts |
| Anomaly | Unusual activity alerts |
| Device Silent | Device silence alerts |

### 8.3 Tapping a Notification

| Notification Type | Opens |
|---|---|
| SOS, Route Deviation | Live Location screen — see your child's position immediately |
| Late, Absent, Anomaly, Device Silent | Alerts screen — see the alert details and history |

### 8.4 Alert Frequency

| Type | Frequency |
|---|---|
| SOS | Immediate — no cooldown |
| Route Deviation | Once per 5 minutes per device per route |
| Late, Absent, Anomaly | Once per day per device |
| Device Silent | Once per 30 minutes while device stays silent |

### 8.5 Enabling Notifications

On Android 13 and above, you may need to grant notification permission:
1. Open your phone's **Settings**.
2. Go to **Apps → SafeTrack → Notifications**.
3. Make sure notifications are **Allowed**.

### 8.6 Receiving Alerts When the App is Closed

The SafeTrack Server sends alerts directly to your phone via Firebase Cloud
Messaging (FCM). You will receive notifications even when the app is fully
closed or your phone is locked — as long as your phone has an internet
connection.

### 8.7 Missed Alerts (App Was Offline)

If your phone was temporarily offline when an alert fired:
- FCM will deliver up to 100 pending notifications when your phone reconnects.
- The **Alerts screen** always shows the complete alert history directly from
  the database — no alerts are ever lost.

---

## 9. Device & Battery Status

### 9.1 Checking Battery Level

Battery level is shown on each child's Dashboard card.

| Battery Level | Status |
|---|---|
| 60–100% | Normal (green) |
| 20–59% | Monitor — consider charging soon (orange) |
| Below 20% | Low — device may stop sending updates (red) |

### 9.2 Charging the Device

Connect the SafeTrack device to a USB charging cable via its charging port.
The LED indicator on the device will:
- **Red blinking** — charging or sending GPS data
- **Green blink** — successful data transmission

Do not expose the device to water or extreme heat while charging.

### 9.3 Device Turned Off or No Signal

If the device shows **Offline** for an extended period:
1. Check that the device is powered on.
2. Check that the device is in an area with cellular coverage.
3. Check the battery level — if it was low, it may have shut down.
4. If the device has been silent for 15+ minutes during school hours, you will
   receive a **Device Silent** notification automatically.

---

## 10. Troubleshooting

**The map is not showing my child's location.**
- Check that the device is Online (green status on Dashboard).
- Ensure the device has sufficient battery.
- Check your phone's internet connection.
- Wait up to 2 minutes for the next GPS update.

**I am not receiving deviation alerts.**
- Ensure the SafeTrack Server is running on the designated laptop.
- Ensure notifications are enabled for SafeTrack in your phone settings.
- Check that the route is set to Active (not paused) in the Route List.
- Check that the device is Online — offline devices cannot trigger alerts.

**I am not receiving late/absent/anomaly/device silent alerts.**
- Ensure the SafeTrack Server is running on the designated laptop.
- Check that a school schedule (Time In / Time Out) is set for the device in
  My Children.
- Check that the device is Enabled (toggle is on) in My Children.

**The AI assistant says "No device data available."**
- This means no device is currently linked or the device is offline.
- Link a device in My Children and ensure it is powered on.

**The location seems wrong or inaccurate.**
- If the badge shows "Cached", the device does not have a fresh GPS fix.
- Outdoors with clear sky gives the best GPS accuracy.
- Wait for the device to acquire a new GPS fix.

**My child's route is not showing on the map.**
- Ensure the route is set to Active in the Route Manager.
- Try closing and reopening the Live Location screen.

**I received a Device Silent alert but my child is fine.**
- The device may have temporarily lost cellular signal.
- Check that the device is powered on and has signal.
- Once the device reconnects and starts transmitting again, the alerts will stop.

---

## 11. Frequently Asked Questions

**Q: How often does the location update?**
The device sends a GPS update every 2 minutes during normal operation. During
an SOS emergency, it transmits immediately.

**Q: What happens if the SafeTrack Server laptop is turned off?**
SOS alerts will still work because the app detects them directly. Route
deviation, late arrival, absence, anomaly, and device silence alerts require
the server to be running.

**Q: Can my child's teacher or school see the location?**
No. Only your account can access your child's location.

**Q: What happens if the device is lost or stolen?**
You can still see the last known location in the app. Disable or unlink the
device from My Children to stop monitoring it.

**Q: Does the AI store my conversations?**
Conversations are not stored permanently. Each session starts fresh. The AI
accesses only your child's real-time device data to answer questions.

**Q: Can I link more than one child?**
Yes. You can link multiple devices to your account — one per child. Each child
appears as a separate card on the Dashboard.

**Q: What is the battery life of the SafeTrack device?**
Under normal use with GPS updates every 2 minutes, the LiFePO4 2000mAh battery
provides approximately 8–12 hours of continuous operation. Charge the device
each night.

**Q: Can I use SafeTrack without internet on my phone?**
You need an internet connection to receive real-time updates and notifications.
However, the last known location and all past alerts are cached and viewable
when you reconnect.

**Q: What does the SOS button do exactly?**
When your child holds the button for 3 seconds, it immediately sends an
emergency signal to the server and your app. You will receive a high-priority
push notification. The SOS automatically cancels after 60 seconds or when
the button is held again.

**Q: What does "Device Silent" mean exactly?**
It means your child's device has not sent any GPS data for more than 15 minutes
during school hours. This can happen if the battery died, the device was turned
off, cellular signal was lost for an extended period, or the device was taken
from your child. You will be re-alerted every 30 minutes if the silence continues.

**Q: Why did I get a "Device Silent" alert right after school starts?**
This can happen if the device lost cellular signal temporarily during the commute.
Check if the device comes back online — if it does, it was a brief signal dropout.
If it stays silent, contact your child's school to verify attendance.

---

*For technical support, contact your school administrator or the SafeTrack system provider.*

*SafeTrack — Cebu Technological University – Danao Campus | BS Computer Engineering Thesis Project*