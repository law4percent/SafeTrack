// path: app/SafeTrack/lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'auth/login_screen.dart';

// ── Embedded docs ─────────────────────────────────────────────────────────────
// Content sourced from:
//   USER_MANUAL.md          → _kUserManual
//   NOTIF_TYPES.md +
//   OFFLINE_NOTIFICATIONS.md → _kHowNotificationsWork

const String _kUserManual = '''
# SafeTrack User Manual
**Version 1.0 — For Parents**

---

## 1. Introduction

SafeTrack works through three components:

- **The SafeTrack Device** — carried by your child, sends GPS location every 2 minutes and immediately on emergency.
- **The SafeTrack App** — installed on your phone, shows your child's location, displays alerts, and lets you ask an AI assistant.
- **The SafeTrack Server** — runs on a laptop, watches all devices in real time and sends push notifications to your phone.

> **Note:** For alerts to work reliably, the SafeTrack Server must be running on the designated laptop during school hours. SOS alerts still work even when the server is off.

---

## 2. Getting Started

### Linking Your Child's Device
1. Tap **My Children** from the Dashboard.
2. Tap **+ LINK DEVICE**.
3. Enter your child's name, device code, and school schedule (Time In / Time Out).
4. Tap **Link Device**.

> **Important:** Always set the school schedule when linking. Without it, late, absent, and device silence alerts will not fire.

---

## 3. Dashboard

Shows all linked children with:
- Online / Offline status
- Battery level
- GPS availability
- SOS / SAFE status

If your child presses the SOS button, a **red banner** appears immediately.

---

## 4. Live Location

- Shows your child's real-time position on an interactive map.
- **GPS** location = accurate within ~5 meters.
- **Cached** location = last known GPS position, shown when no fresh fix is available.
- If a device is silent for 15+ minutes during school hours, you will receive a **Device Silent** alert.

---

## 5. My Children

- **Toggle switch** — enable or disable monitoring for a device. Disabling stops ALL alerts for that device.
- **Edit (pencil icon)** — update name, photo, year level, section, and school schedule.
- **Route icon** — manage registered safe routes.
- **Delete icon** — unlink the device from your account.

---

## 6. Route Registration

Routes define the safe path your child should travel. If your child goes beyond the threshold distance from the route, you receive a **Route Deviation** alert.

### Deviation Threshold Guide

| Threshold | Best For |
|---|---|
| 20–30m | Narrow streets |
| 50m (default) | Typical school routes |
| 100–200m | Wide or rural areas |

---

## 7. AI Assistant

Ask the AI about your child's safety using real device data.

**Example questions:**
- "Where is Juan right now?"
- "Has my child arrived at school?"
- "What is the battery level of the device?"
- "Did my child press the emergency button today?"

---

## 8. Notifications & Alerts

| Notification | What It Means |
|---|---|
| 🆘 SOS Alert | Child pressed emergency button |
| ⚠️ Route Deviation | Child is off their registered route |
| ⏰ Late Arrival | First GPS ping was after grace period |
| 📋 Possible Absence | No GPS activity during school hours |
| ⚠️ Unusual Activity | Movement at unusual hours |
| 📡 Device Silent | Device has not transmitted for 15+ min |

### Tapping a Notification

| Type | Opens |
|---|---|
| SOS, Route Deviation | Live Location screen |
| Late, Absent, Anomaly, Device Silent | Alerts screen |

---

## 9. Device & Battery

| Battery | Status |
|---|---|
| 60–100% | Normal |
| 20–59% | Monitor soon |
| Below 20% | Low — may stop sending |

Battery life under normal use: approximately **8–12 hours**.

---

## 10. Troubleshooting

- **Map not showing location** — check device is Online, battery is sufficient, phone has internet.
- **No deviation alerts** — ensure server is running, route is Active, device is Online.
- **No late/absent/silent alerts** — ensure server is running and school schedule is set.
- **Device Silent alert but child is fine** — device lost signal temporarily. Check if it comes back online.
''';

const String _kHowNotificationsWork = '''
# How Notifications Work in SafeTrack

---

## How the Server Identifies Alert Types

The server decides the type. Each monitor is hardcoded to produce exactly
one type string based on what it detected.

```
Monitor                  →  Type produced
────────────────────────────────────────
sos_monitor             →  "sos"
deviation_monitor       →  "deviation"
behavior_monitor        →  "late" | "absent" | "anomaly"
silence_monitor         →  "silent"
```

---

## What Triggers Each Alert

### 🆘 SOS
**Trigger:** `deviceStatus/sos` changes from `false` → `true`

Child holds the button for 3 seconds → firmware writes `sos: true` → server detects the transition → writes alert → sends FCM push immediately. No cooldown.

---

### ⚠️ Route Deviation
**Trigger:** Haversine distance from registered route exceeds threshold

Server listens to every new GPS log entry in real time. Calculates distance to path. If distance > threshold → fires alert. **5-minute cooldown** per device per route.

---

### ⏰ Late Arrival
**Trigger:** First GPS ping during school hours was after `schoolTimeIn + 15 min grace`

Checked every 5 minutes. Fires once per day per device.

---

### 📋 Possible Absence
**Trigger:** Zero GPS pings during school hours after the grace period

Checked every 5 minutes. Fires once per day per device.

---

### ⚠️ Unusual Activity (Anomaly)
**Trigger:** GPS movement detected after 22:00 or before 05:00

Checked every 5 minutes. Fires once per day per device.

---

### 📡 Device Silent
**Trigger:** `deviceStatus/lastUpdate` has not changed for more than 15 minutes during school hours

Possible causes: battery died, device confiscated, firmware crash, GPRS lost signal.

- **Threshold:** 15 minutes (= 7 missed transmissions at 2-min interval)
- **Re-alert cooldown:** 30 minutes if device stays silent

---

## How the Type Travels to Your Phone

```
Server detects event
  ├── Writes to alertLogs in Firebase     ← AlertScreen reads this
  └── Sends FCM push with type field
        ↓
  App receives FCM push
        ├── Foreground → shows local notification
        ├── Background → FCM shows notification directly
        └── Killed    → FCM shows notification directly
        ↓
  You tap the notification
        ├── SOS / Deviation  → Live Location screen
        └── All others       → Alerts screen
```

---

## Offline Notification Behavior

SafeTrack uses two independent mechanisms so no alerts are lost when your
phone goes offline.

### Mechanism 1 — Firebase RTDB Offline Persistence

The app caches all alert data locally. When your phone reconnects, the
full alert history syncs instantly. **AlertScreen always shows the complete
history regardless of what notifications were delivered.**

### Mechanism 2 — FCM Message Queue

Google stores undelivered FCM pushes for up to **4 weeks**. When your phone
reconnects to the internet, all pending notifications are delivered automatically.
Up to **100 messages** are queued per device.

### Offline Scenario

```
Phone goes offline
  Server keeps running
    → writes alerts to Firebase  ✅
    → FCM pushes queued by Google ✅

Phone comes back online
  → RTDB syncs → AlertScreen updated   ✅
  → FCM delivers queued pushes         ✅ (up to 100)
```

### Delivery Matrix

| Scenario | Notifications | Alert History |
|---|---|---|
| Offline < 4 weeks, < 100 alerts | ✅ All delivered | ✅ Always complete |
| Offline, > 100 alerts | ⚠️ Latest 100 only | ✅ Always complete |
| Phone offline, server also off | ❌ None generated | ✅ Past alerts cached |

---

## Alert Frequency

| Type | Frequency |
|---|---|
| SOS | Immediate, no cooldown |
| Route Deviation | Once per 5 min per device per route |
| Late, Absent, Anomaly | Once per day per device |
| Device Silent | Once per 30 min while silent |

---

## Key Rule

**RTDB is the source of truth. FCM is the doorbell.**

Even if FCM drops a notification, open the **Alerts screen** to see every
alert the server ever wrote — nothing is ever lost.
''';

// ── Screen ────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view settings.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: const SettingsContent(),
    );
  }
}

class SettingsContent extends StatelessWidget {
  const SettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── APP CONFIGURATION ───────────────────────────────────
          _buildSectionHeader('Help & Guides'),
          _buildSettingsTile(
            icon: Icons.menu_book,
            title: 'User Manual',
            subtitle: 'How to use SafeTrack as a parent',
            onTap: () => _showMarkdownSheet(
              context,
              title: 'User Manual',
              content: _kUserManual,
            ),
          ),
          const Divider(),
          _buildSettingsTile(
            icon: Icons.notifications_active,
            title: 'How Notifications Work',
            subtitle: 'Alert types, offline behavior, and delivery',
            onTap: () => _showMarkdownSheet(
              context,
              title: 'How Notifications Work',
              content: _kHowNotificationsWork,
            ),
          ),

          const SizedBox(height: 24),

          // ── ACCOUNT MANAGEMENT ──────────────────────────────────
          _buildSectionHeader('Account Management'),
          _buildAccountInfo(context),
          _buildSettingsTile(
            icon: Icons.key,
            title: 'Change Password',
            subtitle: 'Update your account password',
            onTap: () => _showChangePasswordDialog(context),
          ),
          const SizedBox(height: 16),
          _buildSignOutButton(context),
        ],
      ),
    );
  }

  // ── Markdown bottom sheet ─────────────────────────────────────

  void _showMarkdownSheet(
    BuildContext context, {
    required String title,
    required String content,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MarkdownSheet(title: title, content: content),
    );
  }

  // ── Shared tile builder ───────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blueAccent,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueAccent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildAccountInfo(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Colors.blueAccent, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.email ?? 'No email',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Parent Account',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showSignOutConfirmation(context),
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text(
          'Sign Out',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  void _showSignOutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _performSignOut(context),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performSignOut(BuildContext context) async {
    Navigator.of(context).pop();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      ),
    );

    try {
      final authService = context.read<AuthService>();
      await authService.signOut();

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign out failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ChangePasswordDialog(),
    );
  }
}

// ── Markdown bottom sheet widget ──────────────────────────────────────────────

class _MarkdownSheet extends StatelessWidget {
  final String title;
  final String content;

  const _MarkdownSheet({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            // ── Handle bar ──────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Markdown content ─────────────────────────────────
            Expanded(
              child: Markdown(
                controller: scrollController,
                data: content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  h1: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                  h2: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                  h3: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  p: const TextStyle(fontSize: 13, height: 1.5),
                  tableHead: const TextStyle(fontWeight: FontWeight.bold),
                  tableBody: const TextStyle(fontSize: 12),
                  blockquotePadding: const EdgeInsets.all(12),
                  blockquoteDecoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                  ),
                  code: TextStyle(
                    backgroundColor: Colors.grey[100],
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Change password dialog ────────────────────────────────────────────────────

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      await authService.changePassword(
        currentPassword: _currentPasswordController.text.trim(),
        newPassword: _newPasswordController.text.trim(),
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Password changed successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String message = 'Failed to change password. Please try again.';
      if (e.toString().contains('Incorrect current password')) {
        message = '❌ Incorrect current password. Please try again.';
      } else if (e.toString().contains('weak-password')) {
        message = '❌ Password is too weak. Please choose a stronger password.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateCurrentPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your current password';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a new password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Change Password',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _currentPasswordController,
              decoration: InputDecoration(
                labelText: 'Current Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureCurrentPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () => setState(
                      () => _obscureCurrentPassword = !_obscureCurrentPassword),
                ),
              ),
              obscureText: _obscureCurrentPassword,
              validator: _validateCurrentPassword,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newPasswordController,
              decoration: InputDecoration(
                labelText: 'New Password',
                border: const OutlineInputBorder(),
                helperText: 'At least 6 characters',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNewPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () => setState(
                      () => _obscureNewPassword = !_obscureNewPassword),
                ),
              ),
              obscureText: _obscureNewPassword,
              validator: _validateNewPassword,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _changePassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Change Password'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }
}