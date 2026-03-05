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

  // Notification channel IDs
  static const String _deviationChannelId = 'safetrack_deviation';
  static const String _deviationChannelName = 'Route Deviation Alerts';
  static const String _deviationChannelDesc =
      'Alerts when a child deviates from their registered route';

  static const String _sosChannelId = 'safetrack_sos';
  static const String _sosChannelName = 'SOS Alerts';
  static const String _sosChannelDesc =
      'Emergency SOS alerts from child devices';

  // Notification IDs — use deviceCode hashCode so each
  // device gets its own persistent notification slot
  static int _deviationNotifId(String deviceCode) =>
      deviceCode.hashCode.abs() % 10000;

  // Payload key used to route tap → correct screen
  static const String _payloadDeviceCodeKey = 'deviceCode';

  /// Called when the user taps a notification.
  /// Your navigator should listen to this stream.
  static String? pendingDeviceCode;

  // ── Initialization ────────────────────────────────────────────

  Future<void> initialize() async {
    // Android settings
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings — request permissions at init time
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

    // Create Android notification channels
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
  }

  // ── Permission request (call from UI after first launch) ──────

  Future<bool> requestPermissions() async {
    // Android 13+
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted =
        await androidPlugin?.requestNotificationsPermission() ?? true;

    // iOS
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;

    debugPrint(
        '[NotificationService] Permissions — Android: $androidGranted, iOS: $iosGranted');
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

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      notifId,
      '⚠️ ${event.childName} Off Route',
      '${distance}m from "${event.routeName}" — Tap to view location',
      details,
      payload: event.deviceCode, // used on tap to navigate
    );

    debugPrint(
        '[NotificationService] Deviation alert shown for ${event.childName}');
  }

  // ── SOS alert (bonus — reuse existing SOS detection) ─────────

  Future<void> showSosAlert({
    required String childName,
    required String deviceCode,
  }) async {
    final notifId = (_deviationNotifId(deviceCode) + 5000) % 10000;

    final androidDetails = AndroidNotificationDetails(
      _sosChannelId,
      _sosChannelName,
      channelDescription: _sosChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      ticker: '🆘 SOS Alert',
      fullScreenIntent: true, // pops over lock screen on Android
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
      payload: deviceCode,
    );

    debugPrint('[NotificationService] SOS alert shown for $childName');
  }

  // ── Cancel a specific device notification ─────────────────────

  Future<void> cancelDeviationAlert(String deviceCode) async {
    await _plugin.cancel(_deviationNotifId(deviceCode));
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // Feature 2 — Behavior alert (late, absent, anomaly)
  Future<void> showBehaviorAlert({
    required String childName,
    required String type,
    required String message,
  }) async {
    final titles = {
      'late':    '⏰ Late Arrival — $childName',
      'absent':  '📋 Possible Absence — $childName',
      'anomaly': '⚠️ Unusual Activity — $childName',
    };
    final title = titles[type] ?? '🔔 Alert — $childName';
    const channel = AndroidNotificationChannel(
      'safetrack_behavior',
      'Behavior Alerts',
      description: 'Alerts for late arrivals, absences, and anomalies',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _plugin.show(
      type.hashCode & 0x7FFFFFFF,
      title,
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
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
      payload: childName,
    );
    debugPrint('[NotificationService] Behavior alert shown: $type for $childName');
  }

  // ── Tap handlers ──────────────────────────────────────────────

  static void _onNotificationTapped(NotificationResponse response) {
    final deviceCode = response.payload;
    if (deviceCode != null && deviceCode.isNotEmpty) {
      // Store for AuthWrapper / navigator to pick up after app resumes
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