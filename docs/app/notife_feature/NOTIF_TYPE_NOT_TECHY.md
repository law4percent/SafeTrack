# SafeTrack — Notifications Guide
### What each alert means and what to do about it

---

## How SafeTrack Notifies You

SafeTrack watches your child's device around the clock. When something needs your attention, it sends a notification to your phone. Every notification has a **type** — this tells you exactly what happened and where to look in the app.

There are **6 types of notifications** SafeTrack can send you.

---

## 🆘 SOS — Emergency Alert

**What it means:**
Your child pressed and held the SOS button on their device for 3 seconds. This is the most urgent alert SafeTrack can send.

**When you get this:**
Any time of day — SafeTrack never ignores an SOS, even outside school hours.

**What happens when you tap the notification:**
The app opens directly to the **live map** so you can see exactly where your child is right now.

**What you should do:**
1. Check the map for your child's current location.
2. Try calling your child directly.
3. Contact the school to verify their whereabouts.
4. If you cannot reach them, contact local authorities.

> ⚠️ Every SOS alert fires immediately — there is no delay or cooldown.

---

## ⚠️ Off Route — Deviation Alert

**What it means:**
Your child's device has moved too far away from their registered travel route — for example, the path from home to school that you set up in the app.

**When you get this:**
Only during school hours, and only if you have registered a travel route for your child's device. If no route is set up, this alert will never fire.

**What happens when you tap the notification:**
The app opens directly to the **live map** so you can see where your child currently is and how far they are from their route.

**What you should do:**
1. Check the map — your child may have simply taken a different road.
2. Call your child or their companion to confirm they are safe.
3. If you registered multiple routes, SafeTrack checks all of them and will only alert you for routes your child has actually moved away from.

> 💡 You will receive a separate notification for each route your child deviates from. For example, if you registered two routes and your child strays from both, you will get two alerts — one for each.

> ⏱️ Once this alert fires, it will not fire again for the same route for 5 minutes to avoid repeated pings.

---

## ⏰ Late — Late Arrival Alert

**What it means:**
Your child has GPS activity during school hours, but their first recorded location arrived more than 15 minutes after their scheduled school time-in. In short — SafeTrack noticed your child was late.

**When you get this:**
Once per day, during school hours only.

**What happens when you tap the notification:**
The app opens to the **Alerts screen** where you can review the timeline.

**What you should do:**
1. Check the Alerts screen for the exact time of their first recorded ping.
2. Contact your child or the school to confirm they arrived safely.

> 💡 SafeTrack uses the school schedule you configured in the app. Make sure your child's Time In is set correctly for this alert to work properly.

---

## 📋 Absent — No School Activity Alert

**What it means:**
SafeTrack checked for GPS activity during school hours and found nothing. Your child's device did not record any location updates during the school day after the 15-minute grace period.

**When you get this:**
Once per day, during school hours only — but only after the grace period has passed.

**What happens when you tap the notification:**
The app opens to the **Alerts screen**.

**What you should do:**
1. Check whether the device is powered on and has signal.
2. Contact the school directly to confirm your child's attendance.
3. If the device is off or out of signal, this alert may be a false alarm — check with your child when they get home.

> 💡 This alert fires when there are **zero** GPS readings during school hours. A device with no mobile signal or a dead battery will also trigger this.

---

## ⚠️ Anomaly — Unusual Activity Alert

**What it means:**
SafeTrack detected GPS activity at an unusual hour — specifically between **10 PM and 5 AM**. Your child's device recorded a location update in the middle of the night.

**When you get this:**
Once per day, any time — this alert specifically watches outside of school hours.

**What happens when you tap the notification:**
The app opens to the **Alerts screen**.

**What you should do:**
1. Check the Alerts screen to see the exact time and location of the unusual ping.
2. This could mean the device was left on and moved, or that your child was genuinely out late.
3. Talk to your child to understand the context.

> 💡 This alert is meant to flag genuinely unusual movement — not school hours activity.

---

## 📡 Device Silent — No Updates Alert

**What it means:**
Your child's device has not sent any location updates for more than **15 minutes** during school hours. SafeTrack lost contact with the device.

**When you get this:**
During school hours only. If the device stays silent, SafeTrack will remind you again every **30 minutes**.

**What happens when you tap the notification:**
The app opens to the **Alerts screen**.

**What you should do:**
1. **Check if the device is powered on** — look for the green LED blinking every 30 seconds.
2. **Check the SIM card** — make sure it has an active mobile data balance.
3. **Check the signal area** — if your child is in a building with poor reception, the device may temporarily lose connection.
4. The last known location before the silence is still visible in the app.

> ⏱️ You will receive this reminder every 30 minutes for as long as the device stays silent during school hours.

---

## Quick Reference

| Alert | What triggered it | When it fires | Tap opens |
|---|---|---|---|
| 🆘 SOS | Child pressed SOS button | Any time | Live Map |
| ⚠️ Off Route | Child moved away from registered route | School hours only | Live Map |
| ⏰ Late | Child arrived after grace period | School hours, once/day | Alerts Screen |
| 📋 Absent | No GPS activity during school hours | School hours, once/day | Alerts Screen |
| ⚠️ Anomaly | GPS activity between 10 PM – 5 AM | Any time, once/day | Alerts Screen |
| 📡 Device Silent | No updates for 15+ minutes | School hours, every 30 min | Alerts Screen |

---

## Important Notes for Parents

**SOS and Off Route** open the live map because you need to see where your child is *right now*.

**Late, Absent, Anomaly, and Device Silent** open the Alerts screen because you need context — not just a map pin.

**Deviation alerts require a registered route.** If you have not set up a travel route for your child's device in the app, you will never receive an Off Route alert. All other alerts work without a registered route.

**School hours matter.** Most alerts respect your child's configured school schedule. Make sure the Time In and Time Out are set correctly in the app for the best results.