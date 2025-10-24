# Migration Guide: Firestore to Realtime Database

## Overview
This guide explains the migration from Firestore to Firebase Realtime Database (RTDB) for the SafeTrack authentication system.

## Why This Change?

### Before (Firestore-based)
- ❌ Role-based access with parent/child roles (unnecessary complexity)
- ❌ Used Firestore for user data (overkill for simple structure)
- ❌ No phone number field (needed for SMS notifications)
- ❌ Array-based device codes (hard to query and manage)

### After (RTDB-based)
- ✅ Single "parent" role (only parents use this app)
- ✅ RTDB for real-time data sync (faster, cheaper)
- ✅ Phone number field included (for SMS notifications)
- ✅ Structured device objects (easier to manage)

## Breaking Changes

### 1. Authentication Service Changes

#### Old Method (Removed)
```dart
Future<Map<String, dynamic>?> getParentData()
```

#### New Method
```dart
Future<Map<String, dynamic>?> getUserData()
```

#### Old Sign-Up (No Phone)
```dart
await authService.signUpWithEmail(
  name: name,
  email: email,
  password: password,
);
```

#### New Sign-Up (With Phone)
```dart
await authService.signUpWithEmail(
  name: name,
  email: email,
  phone: phone,  // NEW REQUIRED FIELD
  password: password,
);
```

### 2. Database Structure Changes

#### Old Structure (Firestore)
```
Firestore
└── parents/
    └── {userId}/
        ├── name
        ├── email
        ├── childDeviceCodes: []  // Array
        └── createdAt
```

#### New Structure (RTDB)
```
RTDB
├── users/
│   └── {userId}/
│       ├── name
│       ├── email
│       ├── phone          // NEW
│       ├── role: "parent" // FIXED VALUE
│       └── createdAt
│
└── linkedDevices/         // NEW
    └── {userId}/
        └── devices/
            └── {deviceId}/
                ├── deviceName
                ├── childName
                ├── addedAt
                └── status
```

### 3. New AuthService Methods

```dart
// Get user data from RTDB
Future<Map<String, dynamic>?> getUserData()

// Get all linked devices
Future<List<Map<String, dynamic>>> getLinkedDevices()

// Add a new device
Future<void> addLinkedDevice({
  required String deviceId,
  required String deviceName,
  String? childName,
})

// Remove a device
Future<void> removeLinkedDevice(String deviceId)

// Update user profile
Future<void> updateUserProfile({
  String? name,
  String? phone,
})
```

## Step-by-Step Migration

### Step 1: Update Dependencies (Already Done)
The `pubspec.yaml` already includes:
- `firebase_database: ^12.0.2`
- `firebase_auth: ^6.1.0`

### Step 2: Update Firebase Console

1. **Enable Realtime Database**
   - Go to Firebase Console → Realtime Database
   - Click "Create Database"
   - Choose location (closest to your users)
   - Start in "Locked mode" (we'll add rules next)

2. **Apply Security Rules**
   - Copy rules from `FIREBASE_RTDB_RULES.md`
   - Paste into Rules tab
   - Click "Publish"

3. **Get Database URL**
   - Note the database URL (e.g., `https://safetrack-76a0c-default-rtdb.firebaseio.com/`)
   - This is automatically used by `FirebaseDatabase.instance`

### Step 3: Update Code (Already Done)

✅ [`auth_service.dart`](lib/auth_service.dart) - Migrated to RTDB
✅ [`signup_screen.dart`](lib/signup_screen.dart) - Added phone field
✅ [`login_screen.dart`](lib/login_screen.dart) - Added password reset
✅ [`main.dart`](lib/main.dart) - Added RTDB initialization

### Step 4: Test Authentication Flow

Run these tests to verify everything works:

```bash
# Run the app
cd app/SafeTrack
flutter run
```

**Test Checklist:**
- [ ] Sign up new user with name, email, phone, password
- [ ] Verify user data appears in RTDB under `users/{uid}`
- [ ] Verify `linkedDevices/{uid}` is created with empty devices
- [ ] Log out
- [ ] Log in with same credentials
- [ ] Test "Forgot Password" feature
- [ ] Verify password reset email is sent
- [ ] Update user profile (optional test)
- [ ] Add/remove linked devices (optional test)

### Step 5: Clean Up Old Firestore Data (Optional)

If you have old test data in Firestore:

1. Go to Firebase Console → Firestore Database
2. Delete the `parents` collection
3. (Optional) Disable Firestore if not used elsewhere

**Note:** You can keep Firestore enabled if you plan to use it for other features (logs, analytics, etc.)

## Code Examples

### Example 1: Sign Up New User

```dart
final authService = Provider.of<AuthService>(context, listen: false);

await authService.signUpWithEmail(
  name: 'John Doe',
  email: 'john@example.com',
  phone: '+639171234567',
  password: 'securePassword123',
);
```

### Example 2: Get User Data

```dart
final authService = Provider.of<AuthService>(context, listen: false);
final userData = await authService.getUserData();

print('Name: ${userData?['name']}');
print('Email: ${userData?['email']}');
print('Phone: ${userData?['phone']}');
```

### Example 3: Manage Linked Devices

```dart
// Add device
await authService.addLinkedDevice(
  deviceId: 'device_123',
  deviceName: 'iPhone 12',
  childName: 'Sarah',
);

// Get all devices
final devices = await authService.getLinkedDevices();
for (var device in devices) {
  print('Device: ${device['deviceName']} - ${device['childName']}');
}

// Remove device
await authService.removeLinkedDevice('device_123');
```

### Example 4: Update Profile

```dart
await authService.updateUserProfile(
  name: 'John Updated',
  phone: '+639179999999',
);
```

## Troubleshooting

### Issue: "Permission denied" errors

**Solution:** Verify RTDB security rules are published correctly.

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    }
  }
}
```

### Issue: Database URL not found

**Solution:** Ensure RTDB is created in Firebase Console and the app is using the correct Firebase project.

### Issue: Phone validation fails

**Solution:** Ensure phone number has at least 10 characters. Format: `+63XXXXXXXXXX` or `09XXXXXXXXX`

### Issue: Sign-up redirects to dashboard immediately

**Solution:** The app now signs out after registration to force login. This is expected behavior.

## Performance Improvements

### RTDB vs Firestore
- ✅ **Faster reads**: RTDB is optimized for real-time data
- ✅ **Lower cost**: RTDB is cheaper for frequent reads/writes
- ✅ **Simpler structure**: Better for simple key-value data
- ✅ **Offline support**: Built-in persistence and offline sync

## Next Steps

After migration is complete:

1. ✅ Test all authentication flows
2. ✅ Verify RTDB security rules
3. ⬜ Implement device location tracking (Phase 2)
4. ⬜ Add SMS notification service (Phase 2)
5. ⬜ Create admin panel for monitoring (Future)

## Rollback Plan (If Needed)

If you need to rollback to Firestore:

1. Revert `auth_service.dart` to use `cloud_firestore`
2. Restore old sign-up method (remove phone parameter)
3. Keep both RTDB and Firestore enabled during transition
4. Gradually migrate users back if necessary

**Note:** It's recommended to keep RTDB for this project as it's better suited for real-time tracking.
