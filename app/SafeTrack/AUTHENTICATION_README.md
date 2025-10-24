# Authentication System - SafeTrack

## Overview
SafeTrack uses Firebase Authentication with Realtime Database (RTDB) for user management. The system is designed exclusively for **parent users** who monitor their children's devices.

## Key Features

### ✅ Implemented Features

#### Sign-Up
- ✅ Email/Password registration
- ✅ Name collection
- ✅ Phone number collection (for SMS notifications)
- ✅ Auto-logout after registration (forces login)

#### Log-In
- ✅ Email + Password authentication
- ✅ Password reset via email
- ✅ Show/Hide password toggle
- ✅ Form validation

#### User Management
- ✅ Single role: "parent" only (no role-based access complexity)
- ✅ User data stored in RTDB
- ✅ Linked devices management
- ✅ Profile updates (name, phone)

## Architecture

### Authentication Flow

```
┌─────────────┐
│ Login Screen│
└──────┬──────┘
       │
       ├──(New User)──→ Sign-Up Screen ──→ Register ──→ Auto Logout ──→ Login
       │                                       │
       └──(Existing)──→ Login ────────────────┘
                          │
                          ▼
                   Dashboard Screen
```

### Database Structure (RTDB)

```json
{
  "users": {
    "{userId}": {
      "name": "John Doe",
      "email": "john@example.com",
      "phone": "+639171234567",
      "role": "parent",
      "createdAt": 1234567890
    }
  },
  "linkedDevices": {
    "{userId}": {
      "devices": {
        "{deviceId}": {
          "deviceName": "iPhone 12",
          "childName": "Sarah",
          "addedAt": 1234567890,
          "status": "active"
        }
      }
    }
  }
}
```

## File Structure

```
lib/
├── auth_service.dart          # Authentication & RTDB operations
├── login_screen.dart          # Login UI with password reset
├── signup_screen.dart         # Sign-up UI with phone field
├── dashboard_screen.dart      # Post-login screen
└── main.dart                  # App entry point with RTDB init
```

## Usage Examples

### Sign Up New User

```dart
import 'package:provider/provider.dart';
import 'auth_service.dart';

// In your widget
final authService = Provider.of<AuthService>(context, listen: false);

await authService.signUpWithEmail(
  name: 'John Doe',
  email: 'john@example.com',
  phone: '+639171234567',
  password: 'securePassword123',
);
```

### Log In

```dart
await authService.signInWithEmail(
  'john@example.com',
  'securePassword123',
);
```

### Password Reset

```dart
await authService.resetPassword('john@example.com');
// Email sent to user with reset link
```

### Get User Data

```dart
final userData = await authService.getUserData();
print('Name: ${userData?['name']}');
print('Email: ${userData?['email']}');
print('Phone: ${userData?['phone']}');
```

### Manage Linked Devices

```dart
// Add device
await authService.addLinkedDevice(
  deviceId: 'device_123',
  deviceName: 'iPhone 12',
  childName: 'Sarah',
);

// Get all devices
final devices = await authService.getLinkedDevices();

// Remove device
await authService.removeLinkedDevice('device_123');
```

### Update Profile

```dart
await authService.updateUserProfile(
  name: 'John Updated',
  phone: '+639179999999',
);
```

## Security

### Firebase Security Rules
Security rules are defined in [`FIREBASE_RTDB_RULES.md`](FIREBASE_RTDB_RULES.md).

**Key Security Features:**
- ✅ Users can only access their own data
- ✅ Authentication required for all operations
- ✅ Data validation enforced at database level
- ✅ Role locked to "parent" only

### Password Requirements
- Minimum 6 characters
- Enforced by Firebase Authentication

### Phone Number Validation
- Minimum 10 characters
- Format: `+63XXXXXXXXXX` or `09XXXXXXXXX`

## UI Screenshots

### Login Screen
- Email input field
- Password input field with show/hide toggle
- "Forgot Password?" button
- "Sign Up" link

### Sign-Up Screen
- Name input field
- Email input field
- **Phone number input field** (NEW)
- Password input field with show/hide toggle
- Show password checkbox

### Password Reset Dialog
- Email input field
- Send reset link button
- Success/Error feedback

## Testing

### Manual Testing Checklist

```bash
# Run the app
cd app/SafeTrack
flutter run
```

**Test Cases:**
- [ ] Sign up with valid data (name, email, phone, password)
- [ ] Sign up with invalid email (should show error)
- [ ] Sign up with short password (< 6 chars, should show error)
- [ ] Sign up with short phone (< 10 chars, should show error)
- [ ] Verify auto-logout after sign-up
- [ ] Log in with correct credentials
- [ ] Log in with wrong password (should show error)
- [ ] Click "Forgot Password" and enter email
- [ ] Verify password reset email is sent
- [ ] View user data in Firebase Console (RTDB → users)
- [ ] Verify linkedDevices node is created

### Firebase Console Verification

1. Go to Firebase Console
2. Select project: `safetrack-76a0c`
3. Navigate to Realtime Database
4. Check nodes:
   - `users/{userId}` should contain: name, email, phone, role, createdAt
   - `linkedDevices/{userId}/devices` should be empty object `{}`

## Migration Notes

This is a **major refactor** from the previous Firestore-based system.

### What Changed?
- ❌ Removed Firestore dependency for user data
- ❌ Removed role-based access (parent/child roles)
- ❌ Removed `childDeviceCodes` array
- ✅ Added RTDB for user data
- ✅ Added phone number field
- ✅ Added structured device management
- ✅ Added password reset functionality

### Migration Guide
See [`MIGRATION_GUIDE.md`](MIGRATION_GUIDE.md) for detailed migration steps.

## Dependencies

```yaml
dependencies:
  firebase_core: ^4.1.1
  firebase_auth: ^6.1.0
  firebase_database: ^12.0.2  # RTDB
  provider: ^6.1.5+1           # State management
```

**Removed:**
- `cloud_firestore` (no longer needed for user data)

**Note:** Firestore can still be used for other features like activity logs, but user authentication data is now in RTDB.

## API Reference

### AuthService Methods

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `signUpWithEmail` | name, email, phone, password | `Future<void>` | Register new parent user |
| `signInWithEmail` | email, password | `Future<User?>` | Log in existing user |
| `signOut` | - | `Future<void>` | Log out current user |
| `resetPassword` | email | `Future<void>` | Send password reset email |
| `changePassword` | currentPassword, newPassword | `Future<void>` | Change user password |
| `getUserData` | - | `Future<Map?>` | Get current user data |
| `getLinkedDevices` | - | `Future<List>` | Get all linked devices |
| `addLinkedDevice` | deviceId, deviceName, childName | `Future<void>` | Add new device |
| `removeLinkedDevice` | deviceId | `Future<void>` | Remove device |
| `updateUserProfile` | name, phone | `Future<void>` | Update user profile |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `currentUser` | `User?` | Current Firebase user |
| `userStream` | `Stream<User?>` | Stream of auth state changes |

## Troubleshooting

### Common Errors

#### "Permission denied" in RTDB
**Cause:** Security rules not published or incorrect  
**Solution:** Apply rules from `FIREBASE_RTDB_RULES.md`

#### "User not found" on login
**Cause:** User doesn't exist or wrong credentials  
**Solution:** Verify email/password or sign up new account

#### Phone validation fails
**Cause:** Phone number too short  
**Solution:** Use format `+63XXXXXXXXXX` (minimum 10 chars)

#### Auto-logout after sign-up not working
**Cause:** `signOut()` not called after registration  
**Solution:** Check `signup_screen.dart` line 46

## Future Enhancements

- [ ] Email verification (send verification email on sign-up)
- [ ] Phone number verification (SMS OTP)
- [ ] Social login (Google, Facebook) - Optional
- [ ] Biometric authentication (Face ID, Fingerprint)
- [ ] Multi-factor authentication (2FA)
- [ ] Account deletion feature
- [ ] Profile picture upload

## Support

For issues or questions:
1. Check [`MIGRATION_GUIDE.md`](MIGRATION_GUIDE.md)
2. Review [`FIREBASE_RTDB_RULES.md`](FIREBASE_RTDB_RULES.md)
3. Verify Firebase Console settings
4. Check Flutter logs: `flutter logs`

## Version History

### v2.0.0 (Current)
- ✅ Migrated to RTDB
- ✅ Added phone number field
- ✅ Removed role-based access
- ✅ Added password reset
- ✅ Added device management

### v1.0.0 (Previous)
- Used Firestore for user data
- Had parent/child role system
- No phone number field
- Basic email/password auth
