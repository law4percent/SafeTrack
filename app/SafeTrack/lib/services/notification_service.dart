// app/SafeTrack/lib/services/notification_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/path_monitor_service.dart';

class NotificationService {
  // ── Singleton ─────────────────────────────────────────────────
  static final NotificationService _instance =
      NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ── Notification channel IDs ──────────────────────────────────
  static const String _deviationChannelId   = 'safetrack_deviation';
  static const String _deviationChannelName = 'Route Deviation Alerts';
  static const String _deviationChannelDesc =
      'Alerts when a child deviates from their registered route';

  static const String _sosChannelId   = 'safetrack_sos';
  static const String _sosChannelName = 'SOS Alerts';
  static const String _sosChannelDesc =
      'Emergency SOS alerts from child devices';

  static const String _behaviorChannelId   = 'safetrack_behavior';
  static const String _behaviorChannelName = 'Behavior Alerts';
  static const String _behaviorChannelDesc =
      'Alerts for late arrivals, absences, and anomalies';

  // ── Notification ID helpers ───────────────────────────────────
  //
  // Each deviceCode gets its own integer slot so notifications
  // update in place rather than stacking.
  //
  // Deviation slot: deviceCode.hashCode % 10000
  // SOS slot      : (deviation slot + 5000) % 10000
  // Behavior slot : FIX 6 — combine childName AND type so two
  //                 children with different names never collide
  //                 on the same alert type.
  //                 Old: type.hashCode & 0x7FFFFFFF  (same for all children)
  //                 New: (childName.hashCode ^ type.hashCode) & 0x7FFFFFFF

  static int _deviationNotifId(String deviceCode) =>
      deviceCode.hashCode.abs() % 10000;

  static int _sosNotifId(String deviceCode) =>
      (_deviationNotifId(deviceCode) + 5000) % 10000;

  // FIX 6: behavior alert ID now unique per child+type combination.
  // Uses deviceCode (not childName) to stay consistent with the
  // pattern used by deviation and SOS IDs, and to support
  // cancelAllForDevice correctly.
  static int _behaviorNotifId(String deviceCode, String type) =>
      (deviceCode.hashCode ^ type.hashCode) & 0x7FFFFFFF;

  /// Called when the user taps a notification.
  /// Navigator listens to this to route to the correct screen.
  static String? pendingDeviceCode;

  // ── Initialization ────────────────────────────────────────────

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationTapped,
    );

    await _createAndroidChannels();

    debugPrint('[NotificationService] Initialized');
  }

  Future<void> _createAndroidChannels() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _deviationChannelId,
        _deviationChannelName,
        description: _deviationChannelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _sosChannelId,
        _sosChannelName,
        description: _sosChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFF0000),
      ),
    );

    // Create behavior channel at init time so it's ready before
    // the first showBehaviorAlert call (previously created on-demand
    // which risked a race condition on first use).
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _behaviorChannelId,
        _behaviorChannelName,
        description: _behaviorChannelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  // ── Permission request ────────────────────────────────────────

  Future<bool> requestPermissions() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted =
        await androidPlugin?.requestNotificationsPermission() ?? true;

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;

    debugPrint(
        '[NotificationService] Permissions — '
        'Android: $androidGranted, iOS: $iosGranted');
    return androidGranted && iosGranted;
  }

  // ── Deviation alert ───────────────────────────────────────────

  Future<void> showDeviationAlert(DeviationEvent event) async {
    final notifId = _deviationNotifId(event.deviceCode);
    final distance = event.distanceMeters.toStringAsFixed(0);

    final androidDetails = AndroidNotificationDetails(
      _deviationChannelId,
      _deviationChannelName,
      channelDescription: _deviationChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: '⚠️ Route Deviation',
      styleInformation: BigTextStyleInformation(
        '${event.childName} is ${distance}m away from the '
        '"${event.routeName}" route. Last seen at '
        '${event.position.latitude.toStringAsFixed(5)}, '
        '${event.position.longitude.toStringAsFixed(5)}.',
        contentTitle: '⚠️ ${event.childName} Off Route',
        summaryText: 'SafeTrack',
      ),
      color: const Color(0xFFFF9800),
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _plugin.show(
      notifId,
      '⚠️ ${event.childName} Off Route',
      '${distance}m from "${event.routeName}" — Tap to view location',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: event.deviceCode, // consistent: always deviceCode
    );

    debugPrint(
        '[NotificationService] Deviation alert shown for ${event.childName}');
  }

  // ── SOS alert ─────────────────────────────────────────────────

  Future<void> showSosAlert({
    required String childName,
    required String deviceCode,
  }) async {
    final notifId = _sosNotifId(deviceCode);

    final androidDetails = AndroidNotificationDetails(
      _sosChannelId,
      _sosChannelName,
      channelDescription: _sosChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      ticker: '🆘 SOS Alert',
      fullScreenIntent: true,
      color: const Color(0xFFFF0000),
      styleInformation: BigTextStyleInformation(
        '$childName has triggered an SOS emergency alert! '
        'Open the app immediately to view their location.',
        contentTitle: '🆘 SOS — $childName',
        summaryText: 'SafeTrack Emergency',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    await _plugin.show(
      notifId,
      '🆘 SOS — $childName',
      'Emergency alert triggered! Tap to view location.',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: deviceCode, // consistent: always deviceCode
    );

    debugPrint(
        '[NotificationService] SOS alert shown for $childName');
  }

  // ── Behavior alert ────────────────────────────────────────────
  //
  // FIX 6: notifId now uses _behaviorNotifId(deviceCode, type)
  //        so each child+type pair gets its own slot.
  //        Old: type.hashCode & 0x7FFFFFFF (all children shared same ID)
  //
  // FIX 8: payload is now deviceCode (was childName).
  //        All three alert types now consistently pass deviceCode as
  //        payload so _onNotificationTapped can always set
  //        pendingDeviceCode correctly and navigate to the right screen.
  //
  // Added deviceCode as required parameter — callers (e.g.
  // background_monitor_service.dart) must pass it in.

  Future<void> showBehaviorAlert({
    required String childName,
    required String deviceCode, // FIX 8: added, replaces childName as payload
    required String type,       // 'late' | 'absent' | 'anomaly'
    required String message,
  }) async {
    final titles = {
      'late':    '⏰ Late Arrival — $childName',
      'absent':  '📋 Possible Absence — $childName',
      'anomaly': '⚠️ Unusual Activity — $childName',
    };
    final title = titles[type] ?? '🔔 Alert — $childName';

    // FIX 6: unique ID per child+type — prevents second child's
    // alert overwriting the first when both are late at the same time.
    final notifId = _behaviorNotifId(deviceCode, type);

    await _plugin.show(
      notifId,
      title,
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _behaviorChannelId,
          _behaviorChannelName,
          channelDescription: _behaviorChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: deviceCode, // FIX 8: was childName — now deviceCode
    );

    debugPrint(
        '[NotificationService] Behavior alert shown: $type for $childName');
  }

  // ── Cancel helpers ────────────────────────────────────────────

  /// Cancel only the deviation alert for a device.
  Future<void> cancelDeviationAlert(String deviceCode) async {
    await _plugin.cancel(_deviationNotifId(deviceCode));
  }

  /// FIX 7: Cancel ALL notification slots for a given device —
  /// deviation, SOS, and all known behavior alert types.
  /// Call this when a device is removed or goes back online normally.
  Future<void> cancelAllForDevice(String deviceCode) async {
    await _plugin.cancel(_deviationNotifId(deviceCode));
    await _plugin.cancel(_sosNotifId(deviceCode));
    // Cancel behavior alerts for all known types
    for (final type in ['late', 'absent', 'anomaly']) {
      await _plugin.cancel(_behaviorNotifId(deviceCode, type));
    }
    debugPrint(
        '[NotificationService] All notifications cancelled for $deviceCode');
  }

  /// Cancel every notification across all devices and types.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ── Tap handlers ──────────────────────────────────────────────

  static void _onNotificationTapped(NotificationResponse response) {
    final deviceCode = response.payload;
    if (deviceCode != null && deviceCode.isNotEmpty) {
      // All three alert types now consistently use deviceCode as payload
      // so this handler always receives the correct value to navigate with.
      pendingDeviceCode = deviceCode;
      debugPrint(
          '[NotificationService] Tapped — navigate to $deviceCode');
    }
  }
}

// Must be a top-level function for background tap handling
@pragma('vm:entry-point')
void _onBackgroundNotificationTapped(NotificationResponse response) {
  final deviceCode = response.payload;
  if (deviceCode != null && deviceCode.isNotEmpty) {
    NotificationService.pendingDeviceCode = deviceCode;
    debugPrint(
        '[NotificationService] Background tap — deviceCode: $deviceCode');
  }
}