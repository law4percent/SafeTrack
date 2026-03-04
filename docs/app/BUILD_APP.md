# Building SafeTrack Flutter App to APK

This guide walks you through converting the SafeTrack Flutter project into an installable Android APK file.

---

## Prerequisites

Make sure the following are installed and configured on your machine before building.

### Required Tools

| Tool | Version | Download |
|---|---|---|
| Flutter SDK | ≥ 3.x | https://flutter.dev/docs/get-started/install |
| Android Studio | Latest | https://developer.android.com/studio |
| Android SDK | API 21+ | Via Android Studio |
| Java JDK | 17 (recommended) | Bundled with Android Studio |

### Verify Your Setup

Run the following command to check that everything is properly installed:

```bash
flutter doctor
```

All items should show a green checkmark. If any issues appear, resolve them before proceeding.

---

## Step 1: Clone & Set Up the Project

```bash
git clone https://github.com/your-username/safetrack.git
cd safetrack/app/SafeTrack
```

Install all Flutter dependencies:

```bash
flutter pub get
```

---

## Step 2: Configure Environment Variables

Create a `.env` file in the root of the Flutter project (same level as `pubspec.yaml`):

```
GEMINI_API_KEY=your_gemini_api_key_here
```

Make sure `.env` is listed under `assets` in your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - .env
```

---

## Step 3: Add Firebase Configuration

Place your `google-services.json` file inside:

```
android/app/google-services.json
```

This file is obtained from your Firebase Console under **Project Settings → Your Apps → Android App**.

---

## Step 4: (Optional) Configure App Signing for Release

For a **debug APK**, signing is handled automatically — skip this step.

For a **release APK**, you need a keystore file.

### Generate a Keystore

```bash
keytool -genkey -v -keystore safetrack-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias safetrack
```

Follow the prompts to set a password and fill in your details. Store the `.jks` file somewhere safe — do not commit it to version control.

### Create a Key Properties File

Create `android/key.properties` with the following contents:

```
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=safetrack
storeFile=../safetrack-release.jks
```

### Reference It in `android/app/build.gradle`

Add the following near the top of the file (before the `android` block):

```gradle
def keyProperties = new Properties()
def keyPropertiesFile = rootProject.file('key.properties')
if (keyPropertiesFile.exists()) {
    keyProperties.load(new FileInputStream(keyPropertiesFile))
}
```

Then update the `buildTypes` block:

```gradle
signingConfigs {
    release {
        keyAlias keyProperties['keyAlias']
        keyPassword keyProperties['keyPassword']
        storeFile keyProperties['storeFile'] ? file(keyProperties['storeFile']) : null
        storePassword keyProperties['storePassword']
    }
}

buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

---

## Step 5: Build the APK

### Debug APK (for testing)

```bash
flutter build apk --debug
```

### Release APK (for distribution)

```bash
flutter build apk --release
```

### Split APKs by ABI (smaller file sizes, recommended)

```bash
flutter build apk --split-per-abi
```

This generates separate APKs optimized for different processor architectures:
- `app-armeabi-v7a-release.apk` — older 32-bit Android devices
- `app-arm64-v8a-release.apk` — modern 64-bit Android devices (most common)
- `app-x86_64-release.apk` — emulators and x86 devices

---

## Step 6: Locate the APK

After a successful build, the APK files are located at:

**Single APK:**
```
build/app/outputs/flutter-apk/app-release.apk
```

**Split APKs:**
```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
```

---

## Step 7: Install the APK on a Device

### Via USB (Android Debug Bridge)

Connect your Android device via USB with USB debugging enabled, then run:

```bash
flutter install
```

Or manually using ADB:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Manual Transfer

Copy the APK file to your Android device via USB, Google Drive, or any file transfer method. On the device, open the APK file and tap **Install**. You may need to enable **Install from Unknown Sources** in your device settings under **Settings → Security**.

---

## Troubleshooting

**`flutter doctor` shows missing Android SDK**
→ Open Android Studio → SDK Manager → install the required SDK platform and build tools.

**Build fails with `google-services.json` error**
→ Ensure the file is placed at `android/app/google-services.json` and matches your Firebase package name.

**`.env` file not found at runtime**
→ Confirm `.env` is listed under `assets` in `pubspec.yaml` and run `flutter pub get` again.

**`Keystore file not found` on release build**
→ Double-check the `storeFile` path in `key.properties` is correct relative to the `android/` directory.

**APK installs but crashes on launch**
→ Run `flutter logs` or check `adb logcat` to view runtime errors.

---

## Quick Reference

| Command | Description |
|---|---|
| `flutter pub get` | Install dependencies |
| `flutter doctor` | Check environment setup |
| `flutter build apk --debug` | Build debug APK |
| `flutter build apk --release` | Build release APK |
| `flutter build apk --split-per-abi` | Build split APKs by architecture |
| `flutter install` | Install APK directly to connected device |
| `adb install <path-to-apk>` | Install APK via ADB |