// path: app/SafeTrack/lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/path_monitor_service.dart';
import 'services/background_monitor_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/live_location_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp();

  _initializeRealtimeDatabase();

  // ── Notification service ─────────────────────────────────────
  await NotificationService().initialize();
  await NotificationService().requestPermissions();

  // ── Background monitor (workmanager) ─────────────────────────
  await BackgroundMonitorService().initialize();
  await BackgroundMonitorService().startPeriodicMonitoring();

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
    // Check for a pending notification tap after app resumes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingNotification();
    });
  }

  void _handlePendingNotification() {
    final deviceCode = NotificationService.pendingDeviceCode;
    if (deviceCode == null) return;

    NotificationService.pendingDeviceCode = null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Navigate to the child's Live Location screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveLocationScreen(
          deviceCode: deviceCode,
          userId: user.uid,
        ),
      ),
    );
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