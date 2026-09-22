// Disabled along with push_token_service.dart — see the note at the top
// of that file. This is the client-side piece that would decide what
// text a human sees for a silent FCM data message; commented out rather
// than deleted so re-enabling push later is a straight uncomment.
/*
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:secure_chat_app/core/utils/app_logger.dart';

/// Shows a generic, content-free local notification for a silent FCM
/// data message (Section 10) — this is the ONLY place that decides what
/// text a human sees; the server (see supabase/functions/push-notify)
/// never sends a preview, sender name, or anything else message-derived.
///
/// NOTE: `flutter_local_notifications`' exact v17 API surface (class/
/// method names below) should be double-checked against the pinned
/// version via `flutter analyze` — see the same caveat on
/// FileCryptoService, written for the same reason (pub.dev unreachable
/// from the build sandbox this was authored in).
class LocalNotificationService {
  LocalNotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _log = AppLogger.forName('LocalNotificationService');

  static const _channelId = 'messages';
  static const _channelName = 'Messages';

  Future<void> init({required void Function(String? conversationId) onNotificationTap}) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) => onNotificationTap(response.payload),
    );

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'New message notifications',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// [conversationId] is only ever used as the tap payload for
  /// deep-linking — never shown in the notification text itself.
  Future<void> showNewMessageNotification({required String conversationId}) async {
    try {
      await _plugin.show(
        conversationId.hashCode,
        'New message',
        'You have a new secure message',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: conversationId,
      );
    } catch (e, st) {
      _log.error('Failed to show local notification', e, st);
    }
  }
}
*/
