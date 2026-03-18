// app/SafeTrack/lib/services/notification_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

  // ── Notification ID ranges ────────────────────────────────────
  //
  // Each alert type occupies a dedicated, non-overlapping integer range
  // so notifications from different alert types can NEVER collide
  // regardless of how many devices a parent links.
  //
  //   Deviation : 1,000,000 – 1,049,999
  //   SOS       : 2,000,000 – 2,049,999
  //   Behavior  : 3,000,000 – 3,049,999

  static int _deviationNotifId(String deviceCode) =>
      1000000 + (deviceCode.hashCode.abs() % 50000);

  static int _sosNotifId(String deviceCode) =>
      2000000 + (deviceCode.hashCode.abs() % 50000);

  static int _behaviorNotifId(String deviceCode, String type) =>
      3000000 + ((deviceCode.hashCode ^ type.hashCode).abs() % 50000);

  // ── Pending navigation ────────────────────────────────────────
  //
  // FIX: Replaced static String? pendingDeviceCode with ValueNotifier.
  //
  // The old design stored only deviceCode in a static variable and relied
  // on _handlePendingNotification() being called from initState. This meant
  // taps were silently ignored when the app was foreground or resuming from
  // background because initState never re-fires in those cases.
  //
  // New design:
  //   - pendingNav is a ValueNotifier<_PendingNav?> holding both type and
  //     deviceCode so the navigator can route to the correct screen.
  //   - AuthWrapper listens to pendingNav via addListener — reacts instantly
  //     regardless of app state (foreground, background, or killed).
  //   - Payload format changed from "deviceCode" to "type:deviceCode"
  //     across all show methods so the tap handler can extract both values.

  static final ValueNotifier<PendingNav?> pendingNav =
      ValueNotifier(null);

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
    final notifId  = _deviationNotifId(event.deviceCode);
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
      // FIX: payload now includes type for correct screen routing on tap
      payload: 'deviation:${event.deviceCode}',
    );

    debugPrint(
        '[NotificationService] Deviation alert shown for ${event.childName} '
        '(notifId: $notifId)');
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
      // FIX: payload now includes type for correct screen routing on tap
      payload: 'sos:$deviceCode',
    );

    debugPrint(
        '[NotificationService] SOS alert shown for $childName '
        '(notifId: $notifId)');
  }

  // ── Behavior alert ────────────────────────────────────────────

  Future<void> showBehaviorAlert({
    required String childName,
    required String deviceCode,
    required String type,   // 'late' | 'absent' | 'anomaly' | 'silent'
    required String message,
  }) async {
    final titles = {
      'late':    '⏰ Late Arrival — $childName',
      'absent':  '📋 Possible Absence — $childName',
      'anomaly': '⚠️ Unusual Activity — $childName',
      'silent':  '📡 Device Silent — $childName',
    };
    final title   = titles[type] ?? '🔔 Alert — $childName';
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
      // FIX: payload now includes type for correct screen routing on tap
      payload: '$type:$deviceCode',
    );

    debugPrint(
        '[NotificationService] Behavior alert shown: $type for $childName '
        '(notifId: $notifId)');
  }

  // ── FCM foreground handler ────────────────────────────────────

  Future<void> showFromFcm(RemoteMessage message) async {
    final type       = message.data['type']       as String? ?? '';
    final deviceCode = message.data['deviceCode'] as String? ?? '';
    final childName  = message.data['childName']  as String? ?? 'Your child';
    final msgBody    = message.data['message']    as String? ?? '';

    switch (type) {
      case 'sos':
        await showSosAlert(
          childName:  childName,
          deviceCode: deviceCode,
        );
        break;

      case 'deviation':
        await _plugin.show(
          _deviationNotifId(deviceCode),
          '⚠️ $childName Off Route',
          msgBody.isNotEmpty ? msgBody : 'Tap to view location',
          NotificationDetails(
            android: AndroidNotificationDetails(
              _deviationChannelId,
              _deviationChannelName,
              channelDescription: _deviationChannelDesc,
              importance: Importance.high,
              priority:   Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
              interruptionLevel: InterruptionLevel.timeSensitive,
            ),
          ),
          // FIX: payload includes type for correct routing
          payload: 'deviation:$deviceCode',
        );
        break;

      case 'late':
      case 'absent':
      case 'anomaly':
      case 'silent':
        await showBehaviorAlert(
          childName:  childName,
          deviceCode: deviceCode,
          type:       type,
          message:    msgBody.isNotEmpty ? msgBody : 'Tap to view details',
        );
        break;

      default:
        debugPrint('[NotificationService] showFromFcm: unknown type "$type"');
    }

    debugPrint('[NotificationService] showFromFcm type="$type" '
        'device="$deviceCode"');
  }

  // ── Cancel helpers ────────────────────────────────────────────

  /// Cancel only the deviation alert for a device.
  Future<void> cancelDeviationAlert(String deviceCode) async {
    await _plugin.cancel(_deviationNotifId(deviceCode));
  }

  /// Cancel ALL notification slots for a given device —
  /// deviation, SOS, and all known behavior alert types.
  Future<void> cancelAllForDevice(String deviceCode) async {
    await _plugin.cancel(_deviationNotifId(deviceCode));
    await _plugin.cancel(_sosNotifId(deviceCode));
    for (final type in ['late', 'absent', 'anomaly', 'silent']) {
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

  // FIX: Parse "type:deviceCode" payload and set pendingNav ValueNotifier
  // instead of the old pendingDeviceCode static string.
  // ValueNotifier allows AuthWrapper to react instantly via addListener
  // regardless of whether the app is foreground, background, or resuming.
  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    final separatorIndex = payload.indexOf(':');
    if (separatorIndex == -1) return;

    final type       = payload.substring(0, separatorIndex);
    final deviceCode = payload.substring(separatorIndex + 1);

    if (deviceCode.isEmpty) return;

    pendingNav.value = PendingNav(deviceCode, type);
    debugPrint(
        '[NotificationService] Tapped — type=$type device=$deviceCode');
  }
}

// ── Pending navigation model ──────────────────────────────────────────────────

/// Holds both deviceCode and type so AuthWrapper can route
/// to the correct screen when a local notification is tapped.
class PendingNav {
  final String deviceCode;
  final String type;
  const PendingNav(this.deviceCode, this.type);
}

// ── Background tap handler ────────────────────────────────────────────────────

// Must be a top-level function for background tap handling.
// FIX: Now parses "type:deviceCode" payload same as foreground handler.
@pragma('vm:entry-point')
void _onBackgroundNotificationTapped(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  final separatorIndex = payload.indexOf(':');
  if (separatorIndex == -1) return;

  final type       = payload.substring(0, separatorIndex);
  final deviceCode = payload.substring(separatorIndex + 1);

  if (deviceCode.isEmpty) return;

  NotificationService.pendingNav.value = PendingNav(deviceCode, type);
  debugPrint(
      '[NotificationService] Background tap — type=$type device=$deviceCode');
}