# SafeTrack/server/main.py
#
# Entry point for the SafeTrack Python server.
# Run with: python main.py
#
# Responsibilities:
#   - Initializes Firebase Admin SDK
#   - Starts DeviationMonitor (real-time RTDB listener)
#   - Runs BehaviorMonitor + SilenceMonitor cron every 5 minutes
#   - Catches and logs all errors from monitors
#   - Runs until KeyboardInterrupt (Ctrl+C)
#
# Architecture:
#   Server is the sole monitor and informer.
#   App is the displayer only.
#
#   ESP32 → Firebase RTDB → Server → FCM → Parent's phone → App

import time
import threading
import signal
import sys

import firebase_admin
from firebase_admin import credentials, db as rtdb

from config import (
    SERVICE_ACCOUNT_PATH,
    DATABASE_URL,
    BEHAVIOR_CRON_INTERVAL_MINUTES,
)
from services.logger import get_logger
from services.deviation_monitor import DeviationMonitor
from services.sos_monitor import SosMonitor
from services.behavior_monitor import run_behavior_checks
from services.silence_monitor import run_silence_checks

# ── Logger ────────────────────────────────────────────────────────────────────
log = get_logger("main.py")

# ── Shutdown flag ─────────────────────────────────────────────────────────────
_shutdown = threading.Event()


# ── Firebase initialization ───────────────────────────────────────────────────

def init_firebase():
    """
    Initialize Firebase Admin SDK.
    Must be called before any RTDB or FCM operations.
    """
    try:
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred, {
            'databaseURL': DATABASE_URL
        })
        log(
            details      = f"Firebase initialized — {DATABASE_URL}",
            log_type     = "info",
            show_console = True,
        )
    except Exception as e:
        log(
            details      = f"Firebase initialization failed: {e}",
            log_type     = "error",
            show_console = True,
        )
        sys.exit(1)


# ── Cron runner ───────────────────────────────────────────────────────────────

def run_cron():
    """
    Runs behavior and silence checks every BEHAVIOR_CRON_INTERVAL_MINUTES.
    Runs in a background thread.
    Logs errors from monitors without crashing the server.
    """
    interval_seconds = BEHAVIOR_CRON_INTERVAL_MINUTES * 60

    log(
        details      = f"Cron started — interval: {BEHAVIOR_CRON_INTERVAL_MINUTES} min",
        log_type     = "info",
        show_console = True,
    )

    while not _shutdown.is_set():
        # ── Behavior checks ───────────────────────────────────────
        try:
            log(
                details      = "Running behavior checks...",
                log_type     = "debug",
                show_console = True,
            )
            run_behavior_checks()
            log(
                details      = "Behavior checks complete",
                log_type     = "info",
                show_console = True,
            )
        except Exception as e:
            log(
                details      = f"Behavior check error: {e}",
                log_type     = "error",
                show_console = True,
            )

        # ── Silence checks ────────────────────────────────────────
        try:
            log(
                details      = "Running silence checks...",
                log_type     = "debug",
                show_console = True,
            )
            run_silence_checks()
            log(
                details      = "Silence checks complete",
                log_type     = "info",
                show_console = True,
            )
        except Exception as e:
            log(
                details      = f"Silence check error: {e}",
                log_type     = "error",
                show_console = True,
            )

        # ── Wait for next interval or shutdown ────────────────────
        _shutdown.wait(timeout=interval_seconds)

    log(
        details      = "Cron stopped",
        log_type     = "info",
        show_console = True,
    )


# ── Deviation monitor runner ──────────────────────────────────────────────────

def run_sos_monitor():
    """
    Starts the real-time SOS monitor.
    Runs in a background thread.
    SosMonitor attaches RTDB listeners — stays alive indefinitely.
    """
    try:
        log(
            details      = "Starting SOS monitor...",
            log_type     = "info",
            show_console = True,
        )
        monitor = SosMonitor()
        monitor.start()
        log(
            details      = "SOS monitor running",
            log_type     = "info",
            show_console = True,
        )

        # Keep thread alive while server is running
        while not _shutdown.is_set():
            _shutdown.wait(timeout=60)

    except Exception as e:
        log(
            details      = f"SOS monitor error: {e}",
            log_type     = "error",
            show_console = True,
        )


def run_deviation_monitor():
    """
    Starts the real-time deviation monitor.
    Runs in a background thread.
    DeviationMonitor attaches RTDB listeners — stays alive indefinitely.
    """
    try:
        log(
            details      = "Starting deviation monitor...",
            log_type     = "info",
            show_console = True,
        )
        monitor = DeviationMonitor()
        monitor.start()
        log(
            details      = "Deviation monitor running",
            log_type     = "info",
            show_console = True,
        )

        # Keep thread alive while server is running
        while not _shutdown.is_set():
            _shutdown.wait(timeout=60)

    except Exception as e:
        log(
            details      = f"Deviation monitor error: {e}",
            log_type     = "error",
            show_console = True,
        )


# ── Shutdown handler ──────────────────────────────────────────────────────────

def _handle_shutdown(signum, frame):
    """Handle Ctrl+C or SIGTERM cleanly."""
    print()  # newline after ^C
    log(
        details      = "Shutdown signal received — stopping server...",
        log_type     = "info",
        show_console = True,
    )
    _shutdown.set()


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  SafeTrack Server")
    print("  Always-on monitoring for student safety")
    print("=" * 60)

    # Register shutdown handlers
    signal.signal(signal.SIGINT,  _handle_shutdown)
    signal.signal(signal.SIGTERM, _handle_shutdown)

    # Step 1: Initialize Firebase
    init_firebase()

    # Step 2: Run initial cron cycle immediately on startup
    # so we don't wait 5 minutes for the first check
    log(
        details      = "Running initial checks on startup...",
        log_type     = "info",
        show_console = True,
    )
    try:
        run_behavior_checks()
        run_silence_checks()
        log(
            details      = "Initial checks complete",
            log_type     = "info",
            show_console = True,
        )
    except Exception as e:
        log(
            details      = f"Initial check error: {e}",
            log_type     = "error",
            show_console = True,
        )

    # Step 3: Start SOS monitor in background thread
    sos_thread = threading.Thread(
        target = run_sos_monitor,
        name   = "SosMonitor",
        daemon = True,
    )
    sos_thread.start()

    # Step 4: Start deviation monitor in background thread
    deviation_thread = threading.Thread(
        target = run_deviation_monitor,
        name   = "DeviationMonitor",
        daemon = True,
    )
    deviation_thread.start()

    # Step 5: Start cron in background thread
    cron_thread = threading.Thread(
        target = run_cron,
        name   = "CronRunner",
        daemon = True,
    )
    cron_thread.start()

    log(
        details      = "Server is running. Press Ctrl+C to stop.",
        log_type     = "info",
        show_console = True,
    )

    # Step 6: Keep main thread alive until shutdown
    try:
        while not _shutdown.is_set():
            _shutdown.wait(timeout=1)
    except KeyboardInterrupt:
        _handle_shutdown(None, None)

    # Step 7: Wait for threads to finish cleanly
    sos_thread.join(timeout=5)
    deviation_thread.join(timeout=5)
    cron_thread.join(timeout=5)

    log(
        details      = "Server stopped cleanly",
        log_type     = "info",
        show_console = True,
    )
    print("=" * 60)
    print("  SafeTrack Server stopped")
    print("=" * 60)


if __name__ == "__main__":
    main()