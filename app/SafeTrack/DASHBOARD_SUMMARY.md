# Dashboard Screen Summary

## Overview
The dashboard is the main screen parents see after logging in. It provides real-time monitoring of children's safety status.

## File Structure

### Before (Redundant)
```
lib/screens/
├── dashboard_screen.dart    # Just a wrapper with navigation
└── dashboard_home.dart       # Actual dashboard content
```

### After (Merged) ✅
```
lib/screens/
└── dashboard_screen.dart    # Complete dashboard (navigation + content)
```

## What Was Changed

**Merged Files:**
- ✅ Combined `dashboard_screen.dart` + `dashboard_home.dart` into single `dashboard_screen.dart`
- ✅ Deleted redundant `dashboard_home.dart`
- ✅ No functionality changes - just file consolidation

## Dashboard Features

### 1. Bottom Navigation (4 Tabs)
1. **Dashboard** (Home) - Main monitoring view
2. **Live Tracking** - Real-time location tracking
3. **My Children** - Device management
4. **Settings** - App settings

### 2. Dashboard Home Content

#### Monitoring Status Card
- Shows overall safety status of all children
- **Status Types:**
  - 🔴 **Emergency** - SOS active on any device
  - 🟠 **No Devices** - No children linked yet
  - 🟢 **All Safe** - All children online and safe
  - 🟠 **Some Offline** - Some devices offline
  - 🔵 **Monitoring** - General status

#### My Children Section
- **Empty State:** Shows "No children linked yet" message
- **With Devices:** Displays list/grid of child cards

**Child Card Features:**
- Child name, grade, section
- Avatar (clickable for full-screen view)
- Online/Offline status
- Battery level
- SOS emergency indicator
- Safe/Emergency chip

#### AI Behavioral Insights
- Shows AI-generated insights based on children's status
- Emergency alerts highlighted in red

#### Quick Actions Grid
- Shortcuts to common features
- Defined in `widgets/quick_actions_grid.dart`

## Data Sources

### Firestore (Child Information)
- Collection: `parents/{userId}`
- Fields: `childDeviceCodes[]`, `name`, `email`

- Collection: `children/{deviceCode}`
- Fields: `name`, `grade`, `section`, `avatarUrl`

### Realtime Database (Real-time Status)
- Path: `children/{deviceCode}`
- Fields: `sosActive`, `isOnline`, `batteryLevel`

## Authentication Flow

```
Login Screen
    ↓
[AuthService.signInWithEmail()]
    ↓
main.dart (AuthWrapper)
    ↓
StreamBuilder<User?>
    ↓
DashboardScreen ✅ (You are here)
```

## Responsive Design

The dashboard adapts to different screen sizes:

- **Desktop** (> 1024px): Grid layout, larger fonts
- **Tablet** (600-1024px): Mixed layout, medium fonts
- **Mobile** (< 600px): List layout, smaller fonts

## Import Dependencies

```dart
// Core Flutter
import 'package:flutter/material.dart';

// Firebase
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

// State Management
import 'package:provider/provider.dart';

// Local
import '../services/auth_service.dart';
import '../widgets/quick_actions_grid.dart';
import 'live_tracking_screen.dart';
import 'my_children_screen.dart';
import 'settings_screen.dart';

// System
import 'dart:io'; // For avatar image handling
```

## Key Classes

### 1. DashboardScreen (StatefulWidget)
- Main container with bottom navigation
- Manages tab switching
- Contains AppBar with logo and title

### 2. DashboardHome (StatelessWidget)
- First tab content
- Fetches parent data from Firestore
- Passes child device codes to DashboardContent

### 3. DashboardContent (StatelessWidget)
- Renders all dashboard sections
- Monitors children status
- Responsive layout logic

### 4. ChildCard (StatelessWidget)
- Displays individual child information
- Combines Firestore + RTDB data
- Shows real-time status updates

## Firebase Configuration

```dart
// RTDB URL for Asia Southeast region
const String firebaseRtdbUrl = 
  'https://protectid-f04a3-default-rtdb.asia-southeast1.firebasedatabase.app';

final FirebaseDatabase rtdbInstance = FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL: firebaseRtdbUrl,
);
```

## Real-time Monitoring

The dashboard uses **StreamBuilders** for live updates:

1. **Parent Data Stream** (Firestore)
   ```dart
   FirebaseFirestore.instance
     .collection('parents')
     .doc(user.uid)
     .snapshots()
   ```

2. **Children Status Stream** (RTDB)
   ```dart
   rtdbInstance
     .ref('children/$deviceCode')
     .onValue
   ```

3. **Combined Status Stream**
   ```dart
   _getAllChildrenStatus() // Fetches all children's status
   ```

## Emergency Handling

When SOS is activated:
- 🔴 Red border on child card
- 🔴 Red background
- ⚠️ Warning icon overlay
- 🔴 "EMERGENCY" chip
- 🔴 Emergency alerts in status sections

## No Modifications Policy

As per your request, the dashboard functionality was **NOT modified** - only file organization was changed:

✅ Merged two files into one
✅ Updated imports
❌ No logic changes
❌ No UI changes
❌ No feature additions/removals

## Testing Checklist

After authentication, verify:
- [ ] Dashboard loads successfully
- [ ] Bottom navigation works (4 tabs)
- [ ] Monitoring status shows correct state
- [ ] Child cards display properly (if devices linked)
- [ ] Real-time updates work (online/offline status)
- [ ] AI insights display correctly
- [ ] Quick actions grid appears
- [ ] Emergency indicators work (if SOS active)

## File Size
- **Line Count:** 852 lines
- **Includes:** Navigation + Dashboard content + Child cards

## Related Files
- [`lib/widgets/quick_actions_grid.dart`](../lib/widgets/quick_actions_grid.dart) - Quick actions
- [`lib/services/auth_service.dart`](../lib/services/auth_service.dart) - Authentication
- [`lib/main.dart`](../lib/main.dart) - App entry point with AuthWrapper
