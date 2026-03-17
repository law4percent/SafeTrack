# SafeTrack/server/utils/fcm_sender.py
#
# Sends FCM push notifications to the parent's phone
# via Firebase Admin SDK.
#
# Rule: This module only sends FCM messages.
#       It does NOT write to RTDB.
#       It does NOT import logger — raises exceptions to caller.
#
# Usage:
#   from utils.fcm_sender import send_alert
#
#   send_alert(
#       fcm_token = "device_fcm_token",
#       alert_type = "deviation",
#       child_name = "Juan",
#       device_code = "DEVICE1234",
#       message = "Juan is 80m away from route.",
#   )

import firebase_admin.messaging as fcm_messaging


# ── FCM payload builder ───────────────────────────────────────────────────────

def _build_message(
    fcm_token  : str,
    alert_type : str,
    child_name : str,
    device_code: str,
    message    : str,
    title      : str,
) -> fcm_messaging.Message:
    """
    Build a FCM Message object.

    Data payload keys mirror what the Flutter app reads in showFromFcm():
        type, childName, deviceCode, message

    Notification block is included so FCM shows a visible notification
    when the app is in background or killed state without needing the
    app to process the data payload.
    """
    return fcm_messaging.Message(
        token = fcm_token,

        # Visible notification (background / killed state)
        notification = fcm_messaging.Notification(
            title   = title,
            body    = message,
        ),

        # Data payload (foreground handler + tap routing)
        data = {
            "type"       : alert_type,
            "childName"  : child_name,
            "deviceCode" : device_code,
            "message"    : message,
        },

        # Android-specific config
        android = fcm_messaging.AndroidConfig(
            priority        = "high",
            notification    = fcm_messaging.AndroidNotification(
                # Route to correct channel — must match channel IDs
                # defined in notification_service.dart
                channel_id              = _channel_id(alert_type),
                priority                = "max" if alert_type == "sos" else "high",
                default_vibrate_timings = True,
                default_sound           = True,
            ),
        ),

        # APNS (iOS) config
        apns = fcm_messaging.APNSConfig(
            payload = fcm_messaging.APNSPayload(
                aps = fcm_messaging.Aps(
                    sound               = "default",
                    badge               = 1,
                    content_available   = True,
                ),
            ),
        ),
    )


def _channel_id(alert_type: str) -> str:
    """
    Map alert type to Android notification channel ID.
    Must match channel IDs in notification_service.dart exactly.
    """
    if alert_type == "sos":
        return "safetrack_sos"
    if alert_type == "deviation":
        return "safetrack_deviation"
    # late, absent, anomaly, silent → behavior channel
    return "safetrack_behavior"


def _build_title(alert_type: str, child_name: str) -> str:
    """
    Build notification title matching notification_service.dart titles.
    """
    titles = {
        "sos"      : f"🆘 SOS — {child_name}",
        "deviation": f"⚠️ {child_name} Off Route",
        "late"     : f"⏰ Late Arrival — {child_name}",
        "absent"   : f"📋 Possible Absence — {child_name}",
        "anomaly"  : f"⚠️ Unusual Activity — {child_name}",
        "silent"   : f"📡 Device Silent — {child_name}",
    }
    return titles.get(alert_type, f"🔔 Alert — {child_name}")


# ── Public API ────────────────────────────────────────────────────────────────

def send_alert(
    fcm_token  : str,
    alert_type : str,
    child_name : str,
    device_code: str,
    message    : str,
) -> str:
    """
    Send an FCM push notification to the parent's phone.

    Args:
        fcm_token:   FCM token from users/{uid}/fcmToken in RTDB
        alert_type:  'sos' | 'deviation' | 'late' | 'absent' | 'anomaly' | 'silent'
        child_name:  Child's display name
        device_code: Device identifier e.g. 'DEVICE1234'
        message:     Notification body text

    Returns:
        FCM message ID string on success.

    Raises:
        ValueError: if fcm_token or alert_type is empty
        firebase_admin.exceptions.FirebaseError: if FCM send fails
    """
    if not fcm_token:
        raise ValueError("fcm_token is empty — cannot send FCM push")

    if not alert_type:
        raise ValueError("alert_type is empty — cannot send FCM push")

    title = _build_title(alert_type, child_name)

    msg = _build_message(
        fcm_token   = fcm_token,
        alert_type  = alert_type,
        child_name  = child_name,
        device_code = device_code,
        message     = message,
        title       = title,
    )

    message_id = fcm_messaging.send(msg)
    return message_id