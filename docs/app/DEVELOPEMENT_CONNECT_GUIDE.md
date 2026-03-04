# Flutter Development Instructions

## 🚀 Run Flutter App in Android Emulator

### 🧩 Step 1: List Available Emulators

```bash
flutter emulators
```

This shows all your installed Android Virtual Devices (AVDs).

### 🧩 Step 2: Launch Emulator

```bash
flutter emulators --launch <emulator_id>
```

Example:

```bash
flutter emulators --launch Medium_Phone
```

### 🧩 Step 3: Run Your App

```bash
flutter run
```

This will automatically detect the running emulator and install the app.

---

## 📱 Run Flutter App on Physical Android Phone

### 🧩 Step 1: Enable Developer Options on Phone

1. Go to **Settings** → **About Phone** → **Build Number**
2. Tap **7 times** to enable Developer Mode
3. Go back to **Settings** → **Developer Options** → Enable **USB Debugging**

### 🧩 Step 2: Connect Phone via USB

- Use your USB cable and wait for your PC to recognize the device.
- Allow USB debugging permission when prompted on the phone.

### 🧩 Step 3: Verify Connection

```bash
flutter devices
```

You should see your phone listed (e.g., `Redmi Note 12 (mobile)`).

### 🧩 Step 4: Run the App

```bash
flutter run
```

---

## 🌐 Optional: Run Over Wi-Fi (Wireless Debugging, Android 11+)

If you prefer wireless testing (like Expo Go), follow this:

```bash
adb pair <device_ip_address>:<pairing_port>
adb connect <device_ip_address>:<connection_port>
flutter devices
flutter run
```

🔸 **Note:** Make sure your PC and phone are connected to the same Wi-Fi network.