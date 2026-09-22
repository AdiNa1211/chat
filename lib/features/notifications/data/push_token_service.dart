// Push notifications are disabled for now (dropped from Phase 1 per
// request — Supabase has no native push delivery of its own, so this
// would otherwise pull in Firebase purely as the FCM transport). The
// implementation below is left in place, commented out, so it's a
// straight uncomment + re-add the 3 firebase_*/flutter_local_notifications
// deps in pubspec.yaml (and re-wire it in injection_container.dart/
// app.dart/main.dart, also commented there) to bring it back.
/*
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';
import 'package:secure_chat_app/features/devices_sessions/domain/device_repository.dart';
import 'package:secure_chat_app/features/notifications/data/local_notification_service.dart';

/// Top-level, not a class member: `firebase_messaging` requires the
/// background handler to be a top-level or static function so it can run
/// in its own isolate when the app is killed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing decrypts here — a killed app has no unlocked local-DB key in
  // memory (Section 15.4). This exists only so the OS counts the silent
  // data message delivered; the actual local notification is shown by
  // PushTokenService.start()'s FirebaseMessaging.onMessage listener next
  // time the app is foregrounded — Signal's "wake up and go check" model,
  // not "decrypt off the main thread while backgrounded."
}

/// Registers this device for content-free push (Section 10): obtains an
/// FCM token, keeps it in sync with `devices.push_token`, and routes
/// incoming silent data messages to [LocalNotificationService].
class PushTokenService {
  PushTokenService(this._deviceRepository, this._localNotifications);

  final DeviceRepository _deviceRepository;
  final LocalNotificationService _localNotifications;
  final _log = AppLogger.forName('PushTokenService');

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  /// Call once at app launch, after the user is signed in and this
  /// device is provisioned (Section 8.2) — `_syncToken` is a no-op until
  /// `currentDeviceId()` resolves, so calling early just means the first
  /// token sync waits for the next refresh or the next `start()`.
  Future<void> start() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null) await _syncToken(token);
    _tokenRefreshSub = messaging.onTokenRefresh.listen(_syncToken);

    // FCM doesn't surface a system notification for a data-only message
    // while the app is foregrounded, so show one ourselves — same
    // generic, content-free text either way.
    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      final conversationId = message.data['conversation_id'] as String?;
      if (conversationId != null) {
        _localNotifications.showNewMessageNotification(conversationId: conversationId);
      }
    });
  }

  Future<void> _syncToken(String token) async {
    final deviceId = await _deviceRepository.currentDeviceId();
    if (deviceId == null) return; // not provisioned yet; picked up on next start()
    final result = await _deviceRepository.updatePushToken(deviceId, token);
    if (result case Err()) {
      _log.warning('Failed to sync push token to server');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
  }
}
*/
