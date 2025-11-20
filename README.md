# 🛡️ SafeTrack - Student Safety Monitoring System

A comprehensive Flutter-based child safety monitoring application that provides real-time location tracking, SOS alerts, and parent-child device management.

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Firebase Setup](#-firebase-setup)
- [Environment Configuration](#-environment-configuration)
- [Running the App](#-running-the-app)
- [APK Convertion](#-apk-convertion)
- [Project Structure](#-project-structure)
- [Documentation](#-documentation)
- [Troubleshooting](#-troubleshooting)

## ✨ Features

- 🔐 **Secure Authentication**: Email/Password, Google Sign-In, Facebook Login
- 📍 **Real-Time Location Tracking**: Live GPS tracking of linked devices
- 🚨 **SOS Alerts**: Emergency notifications from child devices
- 👨‍👩‍👧 **Device Management**: Link and manage multiple child devices
- 🏫 **Location Detection**: Automatic school/home arrival notifications
- 📊 **Activity Logs**: Track location history and device activity
- 🗺️ **Interactive Maps**: View multiple devices on map with routes
- 🔋 **Battery Monitoring**: Real-time battery status for all devices
- 🤖 **AI Assistant**: Ask AI feature for safety recommendations

## 🛠️ Prerequisites

Before you begin, ensure you have the following installed:

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (^3.9.2)
- [Dart SDK](https://dart.dev/get-dart)
- [Android Studio](https://developer.android.com/studio) or [Xcode](https://developer.apple.com/xcode/) (for iOS)
- [Git](https://git-scm.com/)
- [Firebase CLI](https://firebase.google.com/docs/cli) (optional)

## 📥 Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/SafeTrack.git
   cd SafeTrack
   ```

2. **Navigate to the Flutter project**
   ```bash
   cd app/SafeTrack
   ```

3. **Install dependencies**
   ```bash
   flutter pub get
   ```

4. **Verify Flutter installation**
   ```bash
   flutter doctor
   ```

## 🔥 Firebase Setup

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use existing: `safetrack-76a0c`
3. Enable the following services:
   - **Authentication**: Email/Password, Google, Facebook
   - **Firestore Database**: For user data storage
   - **Realtime Database**: For live location tracking

### 2. Configure Firebase for Android

1. Add Android app in Firebase Console
2. Download `google-services.json`
3. Place it in `android/app/google-services.json` (Already configured ✅)

### 3. Configure Firebase for iOS (Optional)

1. Add iOS app in Firebase Console
2. Download `GoogleService-Info.plist`
3. Place it in `ios/Runner/GoogleService-Info.plist`

### 4. Realtime Database Security Rules

Set up security rules in Firebase Console:

```json
{
  "rules": {
    ".read": "auth != null",
    ".write": "auth != null",
    "children": {
      "$childId": {
        ".read": "auth != null",
        ".write": "auth != null && (
          !data.exists() || 
          data.child('parentId').val() == auth.uid || 
          !data.child('parentId').exists()
        )"
      }
    }
  }
}
```

## ⚙️ Environment Configuration

### Using .env File (Recommended)

1. **Copy the example file**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your Firebase credentials**
   ```bash
   # Your actual Firebase credentials from firebase.txt
   FIREBASE_API_KEY=AIzaSyD-IB0POwzBhaVzNhDnFG-JewzSm9qS3Es
   FIREBASE_AUTH_DOMAIN=safetrack-76a0c.firebaseapp.com
   FIREBASE_PROJECT_ID=safetrack-76a0c
   # ... etc
   ```

3. **⚠️ IMPORTANT**: Never commit `.env` to Git! It's already in `.gitignore`

### Manual Configuration

Firebase credentials are already configured in:
- [`lib/firebase_options.dart`](app/SafeTrack/lib/firebase_options.dart) ✅
- [`android/app/google-services.json`](app/SafeTrack/android/app/google-services.json) ✅

## 🚀 Running the App

### On Android Emulator

1. **List available emulators**
   ```bash
   flutter emulators
   ```

2. **Launch emulator**
   ```bash
   flutter emulators --launch <emulator_id>
   # Example: flutter emulators --launch Medium_Phone
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

### On Physical Device

1. **Enable USB Debugging** on your Android device
2. **Connect via USB**
3. **Verify connection**
   ```bash
   flutter devices
   ```
4. **Run the app**
   ```bash
   flutter run
   ```
5. **Run in debug mode with hot reload**
   ```bash
   flutter run -d <device_id>
   ```

### On iOS (macOS only)

```bash
cd ios
pod install
cd ..
flutter run
```

## 🏗️ APK Convertion

**Run Command**
```bash
flutter build apk --release
```

**Will generate**
```bash
build/app/outputs/flutter-apk/app-release.apk
```

## 📁 Project Structure

```
SafeTrack/
├── app/
│   ├── docs/                          # Documentation files
│   │   ├── PROJECT_REVIEW_FOR_NEW_DEVELOPER.md
│   │   ├── FLUTTER_VS_REACT_NATIVE_GUIDE.md
│   │   └── QUICK_START_GUIDE.md
│   └── SafeTrack/                     # Main Flutter project
│       ├── lib/
│       │   ├── main.dart              # App entry point
│       │   ├── firebase_options.dart  # Firebase config
│       │   ├── auth_service.dart      # Authentication logic
│       │   ├── screens/               # App screens
│       │   └── widgets/               # Reusable widgets
│       ├── android/                   # Android platform code
│       ├── ios/                       # iOS platform code
│       └── pubspec.yaml               # Dependencies
├── .env.example                       # Environment template
├── .gitignore                         # Git ignore rules
└── README.md                          # This file
```

## 📚 Documentation

- **[Project Review for New Developers](app/docs/PROJECT_REVIEW_FOR_NEW_DEVELOPER.md)** - Comprehensive guide for React Native developers
- **[Flutter vs React Native Guide](app/docs/FLUTTER_VS_REACT_NATIVE_GUIDE.md)** - Comparison and migration guide
- **[Quick Start Guide](app/docs/QUICK_START_GUIDE.md)** - Quick setup instructions

## 🔧 Troubleshooting

### Common Issues

1. **Emulator fails to start**
   ```bash
   flutter clean
   flutter pub get
   # Try launching from Android Studio instead
   ```

2. **Firebase initialization fails**
   - Ensure Firebase project is set up correctly
   - Check `firebase_options.dart` has correct credentials
   - Verify `google-services.json` is in the correct location

3. **Build errors**
   ```bash
   cd android
   ./gradlew clean
   cd ..
   flutter clean
   flutter pub get
   ```

4. **Location permission issues**
   - Ensure location permissions are granted in device settings
   - Check `AndroidManifest.xml` has required permissions

### Getting Help

- Check the [Flutter Documentation](https://flutter.dev/docs)
- Review the [Firebase Documentation](https://firebase.google.com/docs)
- Read the project guides in `app/docs/`

## 🔒 Security Best Practices

### Never Commit These Files to Git:

- ✅ `.env` (actual credentials)
- ✅ `firebase.txt`
- ✅ `google-services.json`
- ✅ `GoogleService-Info.plist`
- ✅ `firebase_options.dart`
- ✅ `*.keystore` / `*.jks`

### Always Commit These Files:

- ✅ `.env.example` (template without real values)
- ✅ `.gitignore` (to protect secrets)
- ✅ `README.md` (documentation)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 👥 Authors

- **Previous Developer** - Initial work
- **Current Team** - Maintenance and new features

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Firebase for backend services
- OpenStreetMap/Mapbox for map services

---

**Project Status**: ✅ Ready for Development

**Last Updated**: October 23, 2025

**Firebase Project**: safetrack-76a0c

**Flutter Version**: SDK ^3.9.2

---

For more detailed information, please refer to the documentation in the `app/docs/` directory.