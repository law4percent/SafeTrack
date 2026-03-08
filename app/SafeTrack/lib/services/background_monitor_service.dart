// app/SafeTrack/lib/services/background_monitor_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'path_monitor_service.dart';
import 'notification_service.dart';
// FIX (critical): import added — BehaviorMonitorService.runChecks() was never
// called from callbackDispatcher, so absent/late/anomaly alerts only fired
// while the app was in the foreground.
import 'behavior_monitor_service.dart';

// ── Task name constants ────────────────────────────────────────
const String _kDeviationCheckTask = 'safetrack.deviationCheck';
const String _kPeriodicTaskName   = 'safetrack.periodicMonitor';

/// Top-level callback required by workmanager.
/// Must be a top-level function annotated with @pragma.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      debugPrint('[BackgroundMonitor] Task started: $taskName');

      // Re-initialize Flutter engine dependencies in this isolate
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: '.env');
      await Firebase.initializeApp();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[BackgroundMonitor] No user — skipping task');
        return Future.value(true);
      }

      // Initialize notification service before any alerts can fire
      await NotificationService().initialize();

      // ── Deviation check via PathMonitorService ─────────────────
      // Start the monitor, give it a window to process the latest log
      // entry per device, then stop it cleanly.
      await PathMonitorService().start(
        onDeviationDetected: (event) async {
          await NotificationService().showDeviationAlert(event);
        },
      );

      // Give the monitor time to process latest logs.
      // PathMonitorService uses limitToLast(1).onChildAdded which replays
      // the latest stored entry on subscribe, so 10s is generally sufficient
      // for deviation checks on a connected network.
      await Future.delayed(const Duration(seconds: 10));
      PathMonitorService().stop();

      // FIX (critical): Run behavior checks in background.
      // Was missing entirely — absent/late/anomaly alerts never fired unless
      // the app was open in the foreground.
      // _notYetFiredToday() uses RTDB for cooldown so it is isolate-safe.
      await BehaviorMonitorService().runChecks();

      debugPrint('[BackgroundMonitor] Task completed: $taskName');
      return Future.value(true);
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
        requiresBatteryNotLow: false,       // still run on low battery (safety app)
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
    debugPrint('[BackgroundMonitor] Periodic monitoring registered');
  }

  /// Cancel all background tasks.
  ///
  /// FIX (minor): call this in your sign-out handler BEFORE
  /// FirebaseAuth.instance.signOut(). Without this, workmanager keeps firing
  /// the task every 15 min after sign-out, each one waking the device and
  /// initializing Firebase only to find no authenticated user.
  ///
  /// Example in settings_screen.dart or auth handler:
  ///   await BackgroundMonitorService().stopPeriodicMonitoring();
  ///   await FirebaseAuth.instance.signOut();
  Future<void> stopPeriodicMonitoring() async {
    await Workmanager().cancelAll();
    debugPrint('[BackgroundMonitor] All background tasks cancelled');
  }
}