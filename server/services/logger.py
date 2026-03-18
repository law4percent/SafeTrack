# SafeTrack/server/services/logger.py
#
# Centralized logging system for the SafeTrack server.
# Copied as-is from existing logger implementation.
#
# Usage:
#   from services.logger import get_logger
#
#   log = get_logger("main.py")
#   log(details="Server started", log_type="info", show_console=True)
#   log(details="FCM send failed", log_type="error", show_console=True)
#
# Rule: Service modules (deviation_monitor, behavior_monitor, etc.)
#       do NOT import this logger directly.
#       They raise exceptions to their caller.
#       Only main.py uses this logger to record errors.

from datetime import datetime
from pathlib import Path
from typing import Literal, Callable
import logging
from logging.handlers import RotatingFileHandler

# Define log types
LogType = Literal["error", "info", "warning", "debug", "bug"]

# Valid log types
VALID_LOG_TYPES = {"error", "info", "warning", "debug", "bug"}

# Get project root directory (assuming logger.py is in services/)
PROJECT_ROOT = Path(__file__).parent.parent
LOGS_DIR = PROJECT_ROOT / "logs"

# Create logs directory if it doesn't exist
LOGS_DIR.mkdir(exist_ok=True)

# Log file configuration
LOG_FILES = {
    "error"  : LOGS_DIR / "error.log",
    "info"   : LOGS_DIR / "info.log",
    "warning": LOGS_DIR / "warning.log",
    "debug"  : LOGS_DIR / "debug.log",
    "bug"    : LOGS_DIR / "bug.log",
    "all"    : LOGS_DIR / "all.log"
}

# Rotation settings: 10MB max per file, keep last 5 files
MAX_BYTES    = 10 * 1024 * 1024  # 10 MB
BACKUP_COUNT = 5

# Color codes for console output
COLORS = {
    "error"  : "\033[91m",   # Red
    "warning": "\033[93m",   # Yellow
    "info"   : "\033[92m",   # Green
    "debug"  : "\033[94m",   # Blue
    "bug"    : "\033[95m",   # Magenta
    "reset"  : "\033[0m"     # Reset
}


class LoggerSystem:
    """Custom logging system with flexible file routing and console output"""

    def __init__(self):
        self._handlers = {}
        self._setup_handlers()
        self._print_log_location()

    def _setup_handlers(self):
        """Initialize rotating file handlers for each log type"""
        for log_type, log_path in LOG_FILES.items():
            handler = RotatingFileHandler(
                filename    = log_path,
                maxBytes    = MAX_BYTES,
                backupCount = BACKUP_COUNT,
                encoding    = 'utf-8'
            )

            formatter = logging.Formatter(
                fmt     = '[%(asctime)s.%(msecs)03d] [%(levelname)s] [%(filename)s:%(lineno)d] %(message)s',
                datefmt = '%Y-%m-%d %H:%M:%S'
            )
            handler.setFormatter(formatter)
            self._handlers[log_type] = handler

    def _print_log_location(self):
        """Print log directory location on initialization"""
        print(f"\n{'='*60}")
        print(f"📁 Log Directory: {LOGS_DIR.absolute()}")
        print(f"{'='*60}")
        print("Available log files:")
        for log_type, log_path in LOG_FILES.items():
            print(f"  • {log_type.upper()}: {log_path.name}")
        print(f"{'='*60}\n")

    def _validate_type(self, log_type: str) -> str:
        """Validate log type and default to 'info' if invalid"""
        if log_type not in VALID_LOG_TYPES:
            print(
                f"\n⚠️  WARNING: Invalid log type '{log_type}'. "
                f"Valid types: {', '.join(VALID_LOG_TYPES)}"
            )
            print(f"Defaulting to 'info' log type.\n")
            raise ValueError(
                f"Invalid log type: '{log_type}'. "
                f"Valid types: {', '.join(VALID_LOG_TYPES)}"
            )
        return log_type

    def _write_to_file(self, log_type: str, message: str, filename: str, lineno: int, save_to_all: bool):
        """Write log message to appropriate file(s)"""
        record = logging.LogRecord(
            name     = "safetrack_server",
            level    = logging.INFO,
            pathname = filename,
            lineno   = lineno,
            msg      = message,
            args     = (),
            exc_info = None
        )

        level_map = {
            "debug"  : logging.DEBUG,
            "info"   : logging.INFO,
            "warning": logging.WARNING,
            "error"  : logging.ERROR,
            "bug"    : logging.CRITICAL
        }
        record.levelno   = level_map.get(log_type, logging.INFO)
        record.levelname = log_type.upper()

        handler = self._handlers[log_type]
        handler.emit(record)

        if save_to_all:
            all_handler = self._handlers["all"]
            all_handler.emit(record)

    def _print_to_console(self, log_type: str, message: str, filename: str):
        """Print formatted log message to console with colors"""
        timestamp   = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        color       = COLORS.get(log_type, COLORS["reset"])
        reset       = COLORS["reset"]

        console_msg = (
            f"{color}[{timestamp}] [{log_type.upper()}] "
            f"[{filename}] {message}{reset}"
        )
        print(console_msg)

    def log(
        self,
        details         : str,
        file            : str,
        log_type        : LogType = "info",
        show_console    : bool    = False,
        save_to_all_logs: bool    = True
    ):
        """
        Main logging function with flexible parameters.

        Args:
            details:          The log message/details
            file:             Source file name (e.g., "main.py")
            log_type:         Log type - "error", "info", "warning", "debug", or "bug"
            show_console:     Whether to print to console (default: False)
            save_to_all_logs: Whether to also save to all.log (default: True)
        """
        try:
            try:
                validated_type = self._validate_type(log_type)
            except ValueError:
                validated_type = "info"

            import inspect
            frame        = inspect.currentframe()
            caller_frame = frame.f_back.f_back
            lineno       = caller_frame.f_lineno if caller_frame else 0

            self._write_to_file(validated_type, details, file, lineno, save_to_all_logs)

            if show_console:
                self._print_to_console(validated_type, details, file)

        except Exception as e:
            print(f"LOGGER ERROR: {e}")
            print(f"Original message: [{log_type.upper()}] {file}: {details}")

    def get_log_location(self) -> Path:
        """Return the logs directory path"""
        return LOGS_DIR

    def get_log_file(self, log_type: str) -> Path:
        """Get specific log file path"""
        if log_type not in LOG_FILES:
            raise ValueError(f"Invalid log type: {log_type}")
        return LOG_FILES[log_type]


# Global logger instance
_logger_instance = LoggerSystem()


def get_logger(filename: str) -> Callable:
    """
    Get a logger function bound to a specific filename.

    Args:
        filename: Source file name (e.g., "main.py")

    Returns:
        A logging function that doesn't require the 'file' parameter

    Example:
        from services.logger import get_logger

        log = get_logger("main.py")
        log(details="Server started", log_type="info", show_console=True)
        log(details="FCM error", log_type="error", show_console=True)
    """
    def bound_logger(
        details         : str,
        log_type        : LogType = "info",
        show_console    : bool    = False,
        save_to_all_logs: bool    = True
    ):
        _logger_instance.log(
            details          = details,
            file             = filename,
            log_type         = log_type,
            show_console     = show_console,
            save_to_all_logs = save_to_all_logs
        )

    return bound_logger


def get_log_location() -> Path:
    """Get the logs directory path"""
    return _logger_instance.get_log_location()


def get_log_file(log_type: str) -> Path:
    """Get specific log file path"""
    return _logger_instance.get_log_file(log_type)