import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:secure_chat_app/core/utils/app_logger.dart';

/// Wraps Supabase Realtime channel subscriptions (Section 11.1) so
/// features don't each reinvent channel lifecycle management. Every
/// payload that flows through here is either ciphertext (new
/// message/reaction rows) or plaintext *metadata only* (typing,
/// presence) — never message content in the clear.
class RealtimeChannelManager {
  RealtimeChannelManager(this._client);

  final SupabaseClient _client;
  final _log = AppLogger.forName('RealtimeChannelManager');
  final Map<String, RealtimeChannel> _channels = {};

  /// Subscribes to new/updated rows in `messages` for one conversation,
  /// via Postgres Changes (RLS-filtered server-side — Section 7/11.1).
  RealtimeChannel watchConversationMessages({
    required String conversationId,
    required void Function(PostgresChangePayload payload) onInsert,
    required void Function(PostgresChangePayload payload) onUpdate,
  }) {
    final key = 'messages:$conversationId';
    _channels[key]?.unsubscribe();

    final channel = _client
        .channel(key)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: onInsert,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: onUpdate,
        )
        .subscribe();

    _channels[key] = channel;
    return channel;
  }

  /// Ephemeral typing indicator (Section 11.1) — Broadcast, never
  /// persisted to Postgres, channel access itself RLS-authorized by
  /// Supabase Realtime Authorization.
  RealtimeChannel watchTyping({
    required String conversationId,
    required void Function(Map<String, dynamic> payload) onTyping,
  }) {
    final key = 'typing:$conversationId';
    _channels[key]?.unsubscribe();
    final channel = _client
        .channel(key)
        .onBroadcast(event: 'typing', callback: (payload) => onTyping(payload))
        .subscribe();
    _channels[key] = channel;
    return channel;
  }

  Future<void> sendTyping({required String conversationId, required bool isTyping}) async {
    final channel = _channels['typing:$conversationId'];
    if (channel == null) {
      _log.warning('sendTyping called before watchTyping subscribed a channel');
      return;
    }
    await channel.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': _client.auth.currentUser?.id, 'is_typing': isTyping},
    );
  }

  /// Online/offline/last-seen (Section 11.1) via Realtime Presence.
  RealtimeChannel watchPresence({
    required String conversationId,
    required void Function(RealtimePresenceSyncPayload payload) onSync,
  }) {
    final key = 'presence:$conversationId';
    _channels[key]?.unsubscribe();
    final channel = _client
        .channel(key)
        .onPresenceSync((payload) => onSync(payload))
        .subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channels[key]?.track({'online_at': DateTime.now().toIso8601String()});
      }
    });
    _channels[key] = channel;
    return channel;
  }

  Future<void> unsubscribeAll() async {
    for (final channel in _channels.values) {
      await channel.unsubscribe();
    }
    _channels.clear();
  }
}
