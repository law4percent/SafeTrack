// path: app/SafeTrack/lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/path_monitor_service.dart';
import 'services/background_monitor_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/live_location_screen.dart';
import 'screens/alerts_screen.dart';

// ── FCM background handler ────────────────────────────────────────────────────
// Must be top-level and annotated — runs in a separate isolate.
// The visible notification in background/killed state is handled by the
// FCM notification payload sent from the server directly.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] Background message: '
      'type=${message.data['type']} '
      'device=${message.data['deviceCode']}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp();

  _initializeRealtimeDatabase();

  // ── Notification service ──────────────────────────────────────
  await NotificationService().initialize();
  await NotificationService().requestPermissions();

  // ── Background monitor (workmanager) ─────────────────────────
  await BackgroundMonitorService().initialize();
  await BackgroundMonitorService().startPeriodicMonitoring();

  // ── FCM setup ────────────────────────────────────────────────
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  await _initializeFcm();

  // ── Foreground path monitor ───────────────────────────────────
  // Starts only if a user is already signed in on cold start
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    _startForegroundMonitor();
  }

  runApp(const MyApp());
}

void _startForegroundMonitor() {
  PathMonitorService().start(
    onDeviationDetected: (event) {
      NotificationService().showDeviationAlert(event);
    },
  );
}

void _initializeRealtimeDatabase() {
  try {
    final database = FirebaseDatabase.instance;
    database.setPersistenceEnabled(true);
    database.setPersistenceCacheSizeBytes(10000000);
    debugPrint('✅ Firebase RTDB initialized with offline persistence');
  } catch (e) {
    debugPrint('❌ Error initializing RTDB: $e');
  }
}

Future<void> _initializeFcm() async {
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission(
    alert:         true,
    badge:         true,
    sound:         true,
    announcement:  false,
    carPlay:       false,
    criticalAlert: false,
    provisional:   false,
  );

  // Save token on startup if user is already signed in
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await _saveFcmToken(user.uid);
  }

  // Re-save whenever FCM rotates the token
  messaging.onTokenRefresh.listen((newToken) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await _saveFcmToken(currentUser.uid);
    }
  });

  // Foreground FCM message → show local notification
  // SOS is skipped here — app's own RTDB listener in dashboard_screen.dart
  // already shows the local notification immediately when sos: true fires.
  // Showing it again from FCM would give the parent a duplicate alert.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final type = message.data['type'] as String? ?? '';
    debugPrint('[FCM] Foreground message: type=$type');
    if (type == 'sos') return;
    NotificationService().showFromFcm(message);
  });

  debugPrint('[FCM] Initialized');
}

Future<void> _saveFcmToken(String uid) async {
  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;
  await FirebaseDatabase.instance
      .ref('users/$uid/fcmToken')
      .set(token);
  debugPrint('[FCM] Token saved for uid=$uid');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthService(),
      child: MaterialApp(
        title: 'SafeTrack - Child Safety',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {

  @override
  void initState() {
    super.initState();

    // FIX: Listen to local notification taps via ValueNotifier.
    // Fires instantly whether the app is foreground, background, or resuming.
    // The old pendingDeviceCode static string only worked on cold start
    // because it relied on initState — which never re-fires for a mounted widget.
    NotificationService.pendingNav.addListener(_onPendingNavChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Killed-state FCM tap
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _routeFcmMessage(initial);

      // Killed-state local notification tap
      _handlePendingNotification();
    });

    // Background FCM tap (app suspended, not killed)
    FirebaseMessaging.onMessageOpenedApp.listen(_routeFcmMessage);
  }

  @override
  void dispose() {
    // Remove listener to prevent memory leak when AuthWrapper is disposed
    NotificationService.pendingNav.removeListener(_onPendingNavChanged);
    super.dispose();
  }

  // ── Local notification tap handler (ValueNotifier) ────────────

  // FIX: Called instantly whenever pendingNav changes — covers all app states.
  void _onPendingNavChanged() {
    final pending = NotificationService.pendingNav.value;
    if (pending == null) return;
    if (!mounted) return;

    // Consume immediately to prevent double navigation
    NotificationService.pendingNav.value = null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _navigateForType(pending.type);
  }

  // ── Killed-state local notification tap ───────────────────────

  // Handles the case where the app was fully killed when the notification
  // was tapped. pendingNav may already be set before the listener attached.
  void _handlePendingNotification() {
    final pending = NotificationService.pendingNav.value;
    if (pending == null) return;

    NotificationService.pendingNav.value = null; // consume

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _navigateForType(pending.type);
  }

  // ── FCM tap routing ───────────────────────────────────────────

  void _routeFcmMessage(RemoteMessage message) {
    final type       = message.data['type']       as String? ?? '';
    final deviceCode = message.data['deviceCode'] as String? ?? '';

    if (deviceCode.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    _navigateForType(type);
  }

  // ── Shared navigation by type ─────────────────────────────────

  // Single routing function used by both local notification taps
  // and FCM message taps — ensures consistent behavior across all paths.
  void _navigateForType(String type) {
    switch (type) {
      case 'sos':
      case 'deviation':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LiveLocationsScreen()),
        );
        break;
      case 'late':
      case 'absent':
      case 'anomaly':
      case 'silent':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AlertScreen()),
        );
        break;
      default:
        debugPrint('[AuthWrapper] Unknown notification type: $type');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return StreamBuilder<User?>(
      stream: authService.userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          // Start foreground monitor when user logs in
          if (!PathMonitorService().isRunning) {
            _startForegroundMonitor();
          }
          return const DashboardScreen();
        }

        // Stop monitor and background tasks on sign out
        PathMonitorService().stop();
        BackgroundMonitorService().stopPeriodicMonitoring();
        return const LoginScreen();
      },
    );
  }
}