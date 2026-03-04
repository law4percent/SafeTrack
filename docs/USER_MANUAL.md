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

Welcome to **SafeTrack** — a child safety monitoring system designed to give parents peace of mind during their child's school commute and throughout the school day.

SafeTrack works through two components working together:

- **The SafeTrack Device** — a small, custom-built tracker your child carries. It automatically sends their GPS location to your phone in real time.
- **The SafeTrack App** — installed on your smartphone, it shows your child's location on a live map, alerts you if they go off-route, and lets you ask an AI assistant safety questions.

**You do not need any technical knowledge to use this app.** This manual will walk you through everything step by step.

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

> **Tip:** If you forget your password, tap **Forgot Password?** and a reset link will be sent to your email.

### 2.3 Linking Your Child's Device

Before you can track your child, you need to link their SafeTrack device to your account.

1. From the Dashboard, tap **My Children**.
2. Tap the **+** button (Add Child).
3. Enter:
   - Your child's **name**
   - The **Device Code** printed on the back of the SafeTrack device
4. Tap **Link Device**.
5. Once linked, your child's name will appear in the list.

> **Important:** Each device has a unique code. Make sure to enter it exactly as printed, including any letters and numbers.

---

## 3. Dashboard

The Dashboard is your home screen. It gives you a quick overview of all your linked children.

### What You'll See

- **Child Card** — one card per linked child, showing:
  - Child's name
  - Online / Offline status (green = online, red = offline)
  - Battery level
  - Last known location update time
  - SOS status indicator

### Dashboard Actions

| Button | What It Does |
|---|---|
| 📍 Location | Opens the live map for that child |
| 🛣️ Routes | Opens the route manager for that child |
| 🤖 Ask AI | Opens the AI assistant with context for that child |

### SOS Alert on Dashboard

If your child presses the emergency button on their device, a **red SOS banner** will appear on their card. You will also receive a push notification. See [Section 8](#8-notifications--alerts) for more details.

---

## 4. Live Location

The Live Location screen shows your child's current position on an interactive map, updated in real time.

### 4.1 Opening Live Location

From the Dashboard, tap the **📍 Location** button on your child's card, or tap **Live Locations** from the bottom navigation bar to see all children at once.

### 4.2 Reading the Map

| Symbol | Meaning |
|---|---|
| 🔵 Blue circle with child icon | Your child's current position |
| 🟢 Green circle with home icon | Start point of a registered route |
| 🔴 Red circle with school icon | End point of a registered route |
| Green dotted line | Your child's registered safe route |

### 4.3 Map Controls

- **Pinch to zoom** — zoom in or out
- **Drag** — pan the map
- **Re-center button** — tap the crosshair icon on the bottom card to snap the map back to your child's position

### 4.4 Full Screen Map

Tap **Full Screen Map** at the bottom of the card to open a larger map view. This view also shows:
- Your child's coordinates (latitude and longitude)
- The registered route with name and deviation threshold
- A live update indicator in the top bar

### 4.5 Online vs. Offline

- **Online (green):** The device sent a location update within the last 5 minutes.
- **Offline (red):** No update received in more than 5 minutes. This may mean the device is powered off, out of cellular range, or has a low battery.

### 4.6 Location Type Badge

A badge next to your child's name shows how their location was determined:
- **GPS** — satellite-based, most accurate (within ~5 meters)
- **Network** — cell tower or Wi-Fi based, moderate accuracy
- **IP** — internet address based, least accurate (city level only)

---

## 5. My Children

This screen manages all your linked devices and children.

### 5.1 Viewing Child Details

Tap any child card to expand details including device code, last known status, and linked routes.

### 5.2 Enabling / Disabling Tracking

Each child card has a toggle switch. Turn it **off** to temporarily pause tracking (for example, during weekends). The device will still function but the app will stop displaying updates.

### 5.3 Unlinking a Device

To remove a child's device from your account:
1. Tap the child's card.
2. Tap **Unlink Device**.
3. Confirm the action.

> **Note:** Unlinking does not delete location history. It only removes the device from your active monitoring list.

---

## 6. Route Registration

Routes let you define the safe path your child should travel — for example, from home to school. If your child goes outside this path, you will receive an alert.

### 6.1 Opening the Route Manager

From the Dashboard or My Children screen, tap the **🛣️ Routes** button on your child's card.

### 6.2 Viewing Existing Routes

The Route List screen shows all routes registered for that child. Each route displays:
- Route name (e.g., "Home to School")
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
5. **Label important waypoints** by tapping a waypoint marker and entering a name (e.g., "Home", "School Gate").
6. **Set the deviation threshold** by tapping the ⚙️ settings icon and adjusting the slider (20m–200m). A smaller value means alerts trigger sooner when your child strays off path.
7. Tap **Save Route** when done.

> **Tip:** Add more waypoints along turns and corners of the route for more accurate monitoring. Straight stretches need fewer waypoints.

### 6.4 Editing a Route

1. From the Route List, tap the **Edit** (pencil) icon on any route.
2. The map editor reopens with existing waypoints loaded.
3. Tap the map to add new waypoints, or long-press an existing marker to remove it.
4. Tap **Update Route** to save changes.

### 6.5 Pausing a Route

Use the toggle switch on any route card to pause monitoring without deleting the route. A paused route will not trigger deviation alerts.

### 6.6 Deleting a Route

Tap the **Delete** (trash) icon on a route card and confirm. This action cannot be undone.

### 6.7 Understanding Deviation Threshold

The deviation threshold is the maximum distance (in meters) your child can be from the registered route before an alert is sent.

| Threshold | Best For |
|---|---|
| 20–30m | Narrow streets, strict paths |
| 50m (default) | Typical school routes |
| 100–200m | Wide areas, rural paths |

---

## 7. AI Assistant

The AI Assistant is a chat interface powered by Google Gemini. It can answer questions about your child's safety using real data from their device.

### 7.1 Opening the AI Assistant

Tap **Ask AI** from the Dashboard or the bottom navigation bar.

### 7.2 What You Can Ask

The AI assistant understands questions in these categories:

**Location & Whereabouts**
- "Where is Diane right now?"
- "Is my child inside the school?"
- "Has my child left the school boundary?"
- "Where did my child go after lunch?"

**Safety & Emergencies**
- "Did my child press the emergency button?"
- "Is there any unusual movement today?"
- "What should I do if I get an emergency alert?"

**Battery & Device Status**
- "What is the battery level of the device?"
- "Is the device running low on battery?"
- "Why is the tracker not showing on the app?"

**Reassurance**
- "Is my child safe right now?"
- "Has there been any unusual activity today?"
- "Can you confirm my child is in school?"

**Child Status**
- "Has my child arrived at school?"
- "What time did my child leave school?"
- "Is my child already inside the campus?"

### 7.3 How the AI Clarifies Broad Questions

If you ask a broad question like **"How is Diane's behavior today?"** or **"Show me my child's movement"**, the AI will ask for clarification first — for example:

> "To give you accurate information, which time period would you like me to check? Yesterday, the past week, or the past month?"

Answer the follow-up, and the AI will then provide a specific response based on your child's actual device data.

### 7.4 School Hours Awareness

The AI is aware that it does not know your child's exact school schedule. If you ask time-sensitive questions outside of typical school hours, the AI may ask you to confirm the expected school hours to avoid giving misleading answers.

### 7.5 Follow-Up Questions

After every response, the AI will suggest a relevant follow-up question. You can tap it or type your own next question.

### 7.6 Suggestion Chips

At the start of a conversation, tap any of the quick suggestion chips to jump straight to common questions without typing.

---

## 8. Notifications & Alerts

SafeTrack sends push notifications to keep you informed even when the app is closed.

### 8.1 Types of Notifications

| Notification | What It Means |
|---|---|
| ⚠️ Route Deviation | Your child has moved more than [threshold] meters from their registered route |
| 🆘 SOS Alert | Your child pressed the emergency button on their device |

### 8.2 Tapping a Notification

Tapping any notification opens the app directly to that child's **Live Location** screen so you can see their current position immediately.

### 8.3 Alert Frequency

- **Route deviation alerts** have a 5-minute cooldown per device. You will not receive repeated alerts every few seconds — only one alert per incident window.
- **SOS alerts** have no cooldown. Every SOS press triggers an immediate notification.

### 8.4 Enabling Notifications

On Android 13 and above, you may need to grant notification permission:
1. Open your phone's **Settings**.
2. Go to **Apps → SafeTrack → Notifications**.
3. Make sure notifications are **Allowed**.

### 8.5 Background Monitoring

SafeTrack continues monitoring your child's route even when the app is closed. A background check runs every 15 minutes automatically. You do not need to keep the app open.

---

## 9. Device & Battery Status

### 9.1 Checking Battery Level

Battery level is shown on each child's Dashboard card and in the AI assistant when asked.

| Battery Level | Status |
|---|---|
| 60–100% | Normal |
| 20–59% | Monitor — consider charging soon |
| Below 20% | Low — device may stop sending updates |

### 9.2 Charging the Device

Connect the SafeTrack device to a USB charging cable via its charging port. The LED indicator on the device will:
- **Red** — charging in progress
- **Blue / Off** — fully charged

Do not expose the device to water or extreme heat while charging.

### 9.3 Device Turned Off or No Signal

If the device shows **Offline** for an extended period:
1. Check that the device is powered on (press and hold the power button).
2. Check that the device is in an area with cellular coverage.
3. Check the battery level — if it was low, it may have shut down.
4. If the issue persists, restart the device.

---

## 10. Troubleshooting

### The map is not showing my child's location.
- Check that the device is **Online** (green status on Dashboard).
- Ensure the device has sufficient battery.
- Check your phone's internet connection.
- Wait up to 60 seconds for the next GPS update.

### I am not receiving deviation alerts.
- Ensure notifications are enabled for SafeTrack in your phone settings.
- Check that the route is set to **Active** (not paused) in the Route List.
- Confirm that the device is Online — offline devices cannot trigger alerts.

### The AI assistant says "No device data available."
- This means no device is currently linked or the device is offline.
- Link a device in My Children and ensure it is powered on.

### The location seems wrong or inaccurate.
- Check the **location type badge**: GPS is most accurate; IP is least accurate.
- Indoors or in areas with tall buildings, GPS accuracy may decrease.
- Wait for the device to get a clear GPS fix (outdoors works best).

### My child's route is not showing on the map.
- Ensure the route is set to **Active** in the Route Manager.
- The route loads when the map opens — try closing and reopening the Live Location screen.

### The app is asking for permission to send notifications.
- Tap **Allow** to enable alerts. Without this, you will not receive deviation or SOS notifications.

---

## 11. Frequently Asked Questions

**Q: How often does the location update?**
The device sends a GPS update approximately every 30–60 seconds when moving, depending on cellular signal quality.

**Q: Can my child's teacher or school see the location?**
No. Only your account can access your child's location. The school is not connected to the SafeTrack system.

**Q: What happens if the device is lost or stolen?**
You can still see the last known location. Unlink the device from your account via My Children to prevent misuse, and contact your school or authorities.

**Q: Does the AI store my conversations?**
Conversations are not stored permanently. Each session starts fresh. The AI accesses only your child's real-time device data to answer questions.

**Q: Can I link more than one child?**
Yes. You can link multiple devices to your account — one per child. Each child appears as a separate card on the Dashboard.

**Q: What is the battery life of the SafeTrack device?**
Under normal use with periodic GPS updates, the LiFePO4 2000mAh battery provides approximately 8–12 hours of continuous operation. Charge the device each night.

**Q: Can I use SafeTrack without internet on my phone?**
You need an internet connection to receive real-time updates. However, the last known location is cached and viewable offline.

**Q: What does the SOS button do exactly?**
When pressed, it immediately sends an emergency flag to your app, triggering a high-priority push notification. The flag is also logged with a timestamp in the system.

---

*For technical support, contact your school administrator or the SafeTrack system provider.*

*SafeTrack — Cebu Technological University – Danao Campus | BS Computer Engineering Thesis Project*