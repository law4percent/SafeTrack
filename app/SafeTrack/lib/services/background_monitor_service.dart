// app/SafeTrack/lib/services/background_monitor_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'path_monitor_service.dart';
import 'notification_service.dart';

// ── Task name constants ────────────────────────────────────────
const String _kDeviationCheckTask = 'safetrack.deviationCheck';
const String _kPeriodicTaskName = 'safetrack.periodicMonitor';

/// Top-level callback required by workmanager.
/// Must be a top-level function annotated with @pragma.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      debugPrint('[BackgroundMonitor] Task started: $taskName');

      // Re-initialize Flutter engine dependencies
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: '.env');
      await Firebase.initializeApp();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[BackgroundMonitor] No user — skipping task');
        return Future.value(true);
      }

      // Initialize notification service
      await NotificationService().initialize();

      // Run path monitor for a short window then stop
      // (workmanager tasks must complete quickly)
      bool completed = false;

      await PathMonitorService().start(
        onDeviationDetected: (event) async {
          await NotificationService().showDeviationAlert(event);
        },
      );

      // Give the monitor 10 seconds to process latest logs
      await Future.delayed(const Duration(seconds: 10));
      PathMonitorService().stop();
      completed = true;

      debugPrint('[BackgroundMonitor] Task completed: $taskName');
      return Future.value(completed);
    } catch (e) {
      debugPrint('[BackgroundMonitor] Task error: $e');
      return Future.value(false);
    }
  });
}

class BackgroundMonitorService {
  // ── Singleton ─────────────────────────────────────────────────
  static final BackgroundMonitorService _instance =
      BackgroundMonitorService._internal();
  factory BackgroundMonitorService() => _instance;
  BackgroundMonitorService._internal();

  /// Call once in main() after Firebase.initializeApp()
  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // set true during development
    );
    debugPrint('[BackgroundMonitor] Workmanager initialized');
  }

  /// Register a periodic background check every 15 minutes.
  /// 15 minutes is the minimum interval Android allows.
  Future<void> startPeriodicMonitoring() async {
    await Workmanager().registerPeriodicTask(
      _kPeriodicTaskName,
      _kDeviationCheckTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected, // only run with network
        requiresBatteryNotLow: false,       // still run on low battery
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
    debugPrint('[BackgroundMonitor] Periodic monitoring registered');
  }

  /// Cancel all background tasks (e.g. on sign out)
  Future<void> stopPeriodicMonitoring() async {
    await Workmanager().cancelAll();
    debugPrint('[BackgroundMonitor] All background tasks cancelled');
  }
}