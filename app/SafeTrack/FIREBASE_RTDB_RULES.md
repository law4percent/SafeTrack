# Firebase Realtime Database Security Rules

## Overview
This document outlines the security rules for SafeTrack's Firebase Realtime Database. The database structure focuses on parent users with linked devices (child devices).

## Database Structure

```
safetrack-rtdb/
├── users/
│   └── {userId}/
│       ├── name: string
│       ├── email: string
│       ├── phone: string
│       ├── createdAt: timestamp
│       └── role: "parent"
│
└── linkedDevices/
    └── {userId}/
        └── devices/
            └── {deviceId}/
                ├── deviceName: string
                ├── childName: string
                ├── addedAt: timestamp
                └── status: "active" | "inactive"
```

## Security Rules

Copy and paste these rules into your Firebase Realtime Database Rules section:

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid",
        ".validate": "newData.hasChildren(['name', 'email', 'phone', 'createdAt', 'role'])",
        "name": {
          ".validate": "newData.isString() && newData.val().length > 0"
        },
        "email": {
          ".validate": "newData.isString() && newData.val().matches(/^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$/i)"
        },
        "phone": {
          ".validate": "newData.isString() && newData.val().length >= 10"
        },
        "role": {
          ".validate": "newData.val() === 'parent'"
        }
      }
    },
    "linkedDevices": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid",
        "devices": {
          "$deviceId": {
            ".validate": "newData.hasChildren(['deviceName', 'childName', 'addedAt', 'status'])",
            "deviceName": {
              ".validate": "newData.isString() && newData.val().length > 0"
            },
            "childName": {
              ".validate": "newData.isString()"
            },
            "status": {
              ".validate": "newData.val() === 'active' || newData.val() === 'inactive'"
            }
          }
        }
      }
    }
  }
}
```

## Rule Explanations

### Users Collection
- **Read/Write Access**: Only authenticated users can read/write their own data (`$uid === auth.uid`)
- **Required Fields**: name, email, phone, createdAt, role
- **Validation**:
  - `name`: Must be a non-empty string
  - `email`: Must match email pattern
  - `phone`: Must be at least 10 characters
  - `role`: Must be exactly "parent" (role-based access removed, only parents use this app)

### Linked Devices Collection
- **Read/Write Access**: Only authenticated users can access their own linked devices
- **Required Fields**: deviceName, childName, addedAt, status
- **Validation**:
  - `deviceName`: Must be a non-empty string
  - `childName`: Must be a string
  - `status`: Must be either "active" or "inactive"

## Implementation Steps

1. **Go to Firebase Console**
   - Navigate to https://console.firebase.google.com
   - Select your project: `safetrack-76a0c`

2. **Access Realtime Database**
   - Click on "Realtime Database" in the left sidebar
   - Click on the "Rules" tab

3. **Update Rules**
   - Replace existing rules with the rules provided above
   - Click "Publish"

4. **Test Rules**
   - Use the Rules Playground to test read/write operations
   - Ensure authenticated users can only access their own data

## Key Security Features

✅ **User Isolation**: Each user can only access their own data  
✅ **Authentication Required**: All operations require Firebase Authentication  
✅ **Data Validation**: Enforces correct data types and formats  
✅ **Role Enforcement**: Only "parent" role is allowed (no child or admin roles)  
✅ **Device Management**: Parents can manage their linked devices securely  

## Migration Notes

### Changes from Previous Structure
1. **Removed Firestore**: All data now stored in RTDB for better real-time performance
2. **Removed Role-Based Access**: Only parent role exists, simplified security model
3. **Added Phone Number**: Required field for SMS notifications
4. **Linked Devices**: Replaces old "childDeviceCodes" array with structured device objects

### Data Migration (if needed)
If you have existing Firestore data, you'll need to:
1. Export data from Firestore `parents` collection
2. Transform data to match RTDB structure
3. Import to RTDB `users` and `linkedDevices` nodes

## Testing Checklist

- [ ] Parent can sign up with name, email, phone, password
- [ ] Parent can log in with email and password
- [ ] Parent can reset password via email
- [ ] Parent can view their own user data
- [ ] Parent can update their profile (name, phone)
- [ ] Parent can add linked devices
- [ ] Parent can view linked devices
- [ ] Parent can remove linked devices
- [ ] Parent CANNOT access other users' data
- [ ] Unauthenticated users CANNOT read/write any data

## Future Enhancements

- [ ] Add device location tracking nodes
- [ ] Add activity logs per device
- [ ] Add notification preferences per parent
- [ ] Add geofencing rules per device
- [ ] Add emergency contacts per parent
