import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:secure_chat_app/core/database/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:secure_chat_app/core/crypto/device_id_codec.dart';
import 'package:secure_chat_app/core/crypto/models/device_prekey_bundle.dart';
import 'package:secure_chat_app/core/crypto/session_manager.dart';
import 'package:secure_chat_app/core/database/daos/conversation_dao.dart';
import 'package:secure_chat_app/core/database/daos/message_dao.dart';
import 'package:secure_chat_app/core/database/daos/outbox_dao.dart';
import 'package:secure_chat_app/core/error/failures.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/core/network/realtime_channel_manager.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';
import 'package:secure_chat_app/features/chat_1to1/data/ciphertext_envelope.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/chat_repository.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/entities/conversation.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/entities/message.dart';
import 'package:secure_chat_app/features/devices_sessions/domain/device_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({
    required SupabaseClient client,
    required ConversationDao conversationDao,
    required MessageDao messageDao,
    required OutboxDao outboxDao,
    required SessionManager sessionManager,
    required DeviceRepository deviceRepository,
    required RealtimeChannelManager realtimeChannelManager,
  })  : _client = client,
        _conversationDao = conversationDao,
        _messageDao = messageDao,
        _outboxDao = outboxDao,
        _sessionManager = sessionManager,
        _deviceRepository = deviceRepository,
        _realtime = realtimeChannelManager;

  final SupabaseClient _client;
  final ConversationDao _conversationDao;
  final MessageDao _messageDao;
  final OutboxDao _outboxDao;
  final SessionManager _sessionManager;
  final DeviceRepository _deviceRepository;
  final RealtimeChannelManager _realtime;
  final _log = AppLogger.forName('ChatRepositoryImpl');
  static const _uuid = Uuid();

  String get _myUserId => _client.auth.currentUser!.id;

  @override
  Stream<List<Conversation>> watchConversations() {
    final db = _conversationDao.attachedDatabase;
    return _conversationDao.watchConversations().asyncMap((rows) async {
      final out = <Conversation>[];
      for (final row in rows) {
        final members = await (db.select(db.localConversationMembers)
              ..where((t) => t.conversationId.equals(row.id)))
            .get();
        final otherMember = members.firstWhereOrNull((m) => m.userId != _myUserId);
        if (otherMember == null) continue;
        final profile = await (db.select(db.localProfiles)
              ..where((t) => t.id.equals(otherMember.userId)))
            .getSingleOrNull();
        out.add(Conversation(
          id: row.id,
          otherUserId: otherMember.userId,
          otherUserDisplayName: profile?.displayName ?? 'Unknown',
          otherUserAvatarUrl: profile?.avatarUrl,
          lastMessagePreview: row.lastMessagePreview,
          lastMessageAt: row.lastMessageAt,
          unreadCount: row.unreadCount,
        ));
      }
      return out;
    });
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    return _messageDao.watchMessages(conversationId).map((rows) {
      return rows
          .map((r) => Message(
                id: r.id,
                conversationId: r.conversationId,
                senderId: r.senderId,
                content: r.content,
                type: MessageType.values.byName(r.messageType),
                clientSentAt: r.clientSentAt,
                serverReceivedAt: r.serverReceivedAt,
                replyToMessageId: r.replyToMessageId,
                editedAt: r.editedAt,
                deliveryStatus: MessageDeliveryStatus.values.byName(r.deliveryStatus),
                isMine: r.senderId == _myUserId,
              ))
          .toList();
    });
  }

  @override
  Future<Result<Conversation>> startOrGetDirectConversation(String otherUserId) async {
    try {
      final existing = await _conversationDao.findDirectConversationWith(_myUserId, otherUserId);
      if (existing != null) {
        final db = _conversationDao.attachedDatabase;
        final profile = await (db.select(db.localProfiles)..where((t) => t.id.equals(otherUserId)))
            .getSingleOrNull();
        return Ok(Conversation(
          id: existing.id,
          otherUserId: otherUserId,
          otherUserDisplayName: profile?.displayName ?? 'Unknown',
          otherUserAvatarUrl: profile?.avatarUrl,
        ));
      }

      // Not cached locally — create it server-side. The creator's own
      // membership row must be inserted with role 'owner' (not the
      // default 'member'), or the RLS policy on the *second* insert (the
      // other participant) has no admin/owner row to authorize against
      // (see supabase/migrations/0002_rls.sql, conversation_members_insert_member).
      final conversationId = _uuid.v4();
      await _client.from('conversations').insert({
        'id': conversationId,
        'type': 'direct',
        'created_by': _myUserId,
      });
      await _client.from('conversation_members').insert({
        'conversation_id': conversationId,
        'user_id': _myUserId,
        'role': 'owner',
      });
      await _client.from('conversation_members').insert({
        'conversation_id': conversationId,
        'user_id': otherUserId,
        'role': 'member',
      });

      final otherProfile =
          await _client.from('profiles').select().eq('id', otherUserId).maybeSingle();

      await _conversationDao.upsertConversation(LocalConversationsCompanion.insert(
        id: conversationId,
        type: 'direct',
        createdBy: _myUserId,
        createdAt: DateTime.now(),
      ));
      await _conversationDao.upsertMember(LocalConversationMembersCompanion.insert(
        conversationId: conversationId,
        userId: _myUserId,
        joinedAt: DateTime.now(),
        role: const Value('owner'),
      ));
      await _conversationDao.upsertMember(LocalConversationMembersCompanion.insert(
        conversationId: conversationId,
        userId: otherUserId,
        joinedAt: DateTime.now(),
      ));

      return Ok(Conversation(
        id: conversationId,
        otherUserId: otherUserId,
        otherUserDisplayName: (otherProfile?['display_name'] as String?) ?? 'Unknown',
        otherUserAvatarUrl: otherProfile?['avatar_url'] as String?,
      ));
    } on PostgrestException catch (e, st) {
      _log.error('startOrGetDirectConversation failed', e, st);
      return Err(ServerFailure(e.message));
    } catch (e, st) {
      _log.error('startOrGetDirectConversation failed', e, st);
      return const Err(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> sendTextMessage({
    required String conversationId,
    required String otherUserId,
    required String plaintext,
    String? replyToMessageId,
  }) async {
    final clientMessageId = _uuid.v4();
    final now = DateTime.now();
    final myDeviceIdForOptimisticRow = (await _deviceRepository.currentDeviceId()) ?? '';

    // 1. Optimistic local write — the UI shows this instantly regardless
    //    of network state (Section 2/12.1).
    await _messageDao.upsertMessage(LocalMessagesCompanion.insert(
      id: clientMessageId,
      conversationId: conversationId,
      senderId: _myUserId,
      senderDeviceId: myDeviceIdForOptimisticRow,
      content: plaintext,
      messageType: 'text',
      clientSentAt: now,
      replyToMessageId: Value(replyToMessageId),
      deliveryStatus: const Value('sending'),
    ));
    await _conversationDao.touchLastMessage(
      conversationId: conversationId,
      preview: plaintext,
      at: now,
    );

    // 2. Enqueue to the outbox *before* attempting the network send —
    //    if the attempt below throws (app killed mid-send, etc.) the
    //    message is still recoverable by `drainOutbox()` on next launch.
    await _outboxDao.enqueue(PendingOutboxCompanion.insert(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      plaintextContent: plaintext,
      createdAt: now,
      replyToMessageId: Value(replyToMessageId),
    ));

    // 3. Attempt the send immediately; on failure, leave it queued for
    //    `drainOutbox()` (Section 12.2) rather than surfacing an error —
    //    from the user's point of view this is just "sending...".
    final sendResult = await _attemptSend(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      otherUserId: otherUserId,
      plaintext: plaintext,
      replyToMessageId: replyToMessageId,
    );

    if (sendResult case Err(:final failure)) {
      await _outboxDao.markFailed(clientMessageId, failure.message);
    }
    return const Ok(null);
  }

  Future<Result<void>> _attemptSend({
    required String clientMessageId,
    required String conversationId,
    required String otherUserId,
    required String plaintext,
    String? replyToMessageId,
  }) async {
    try {
      await _outboxDao.markSending(clientMessageId);

      // Phase 1 simplification (Section 2.1 roadmap note): fans out to
      // the contact's *first* active device only. Full multi-device
      // fan-out (one ciphertext per device) is Phase 2.
      final deviceIdsResult = await _deviceRepository.listDeviceIdsFor(otherUserId);
      if (deviceIdsResult case Err(:final failure)) return Err(failure);
      final deviceIds =
          (deviceIdsResult as Ok<List<({String deviceId, String platform})>>).value;
      if (deviceIds.isEmpty) {
        return const Err(ServerFailure('This contact has no active devices to message.'));
      }
      final remoteDeviceUuid = deviceIds.first.deviceId;
      final remoteDeviceIntId = deviceUuidToProtocolDeviceId(remoteDeviceUuid);

      final bundleResult = await _deviceRepository.fetchRemotePreKeyBundle(
        remoteUserId: otherUserId,
        remoteDeviceId: remoteDeviceUuid,
      );
      if (bundleResult case Err(:final failure)) return Err(failure);
      final remoteBundle = (bundleResult as Ok<RemotePreKeyBundle>).value;

      final sessionResult = await _sessionManager.ensureSession(remoteBundle);
      if (sessionResult case Err(:final failure)) return Err(failure);

      final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
      final encryptResult = await _sessionManager.encrypt(
        remoteUserId: otherUserId,
        remoteDeviceId: remoteDeviceIntId,
        plaintext: plaintextBytes,
      );
      if (encryptResult case Err(:final failure)) return Err(failure);
      final envelope = (encryptResult as Ok<EncryptedEnvelope>).value;
      final wireBytes = CiphertextEnvelopeCodec.encode(envelope);

      final myDeviceId = await _deviceRepository.currentDeviceId();
      if (myDeviceId == null) {
        return const Err(UnknownFailure('This device is not registered yet.'));
      }

      final inserted = await _client
          .from('messages')
          .insert({
            'id': clientMessageId,
            'conversation_id': conversationId,
            'sender_id': _myUserId,
            'sender_device_id': myDeviceId,
            'ciphertext': wireBytes,
            'message_type': 'text',
            'reply_to_message_id': replyToMessageId,
            'client_sent_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      await _messageDao.upsertMessage(LocalMessagesCompanion.insert(
        id: clientMessageId,
        conversationId: conversationId,
        senderId: _myUserId,
        senderDeviceId: myDeviceId,
        content: plaintext,
        messageType: 'text',
        clientSentAt: DateTime.parse(inserted['client_sent_at'] as String),
        serverReceivedAt: Value(DateTime.parse(inserted['server_received_at'] as String)),
        deliveryStatus: const Value('sent'),
      ));
      await _outboxDao.remove(clientMessageId);

      return const Ok(null);
    } on PostgrestException catch (e, st) {
      _log.warning('Send attempt failed (will retry from outbox)', e, st);
      await _messageDao.markDeliveryStatus(clientMessageId, 'failed');
      return Err(ServerFailure(e.message));
    } catch (e, st) {
      _log.warning('Send attempt failed (will retry from outbox)', e, st);
      await _messageDao.markDeliveryStatus(clientMessageId, 'failed');
      return const Err(UnknownFailure());
    }
  }

  @override
  Future<void> drainOutbox() async {
    final db = _conversationDao.attachedDatabase;
    final batch = await _outboxDao.nextBatch();
    for (final row in batch) {
      // The conversation's other participant is looked up locally; a row
      // whose conversation was never synced locally (rare — created on
      // another device) is skipped this pass rather than guessing.
      final members = await (db.select(db.localConversationMembers)
            ..where((t) => t.conversationId.equals(row.conversationId)))
          .get();
      final other = members.firstWhereOrNull((m) => m.userId != _myUserId);
      if (other == null) continue;

      final result = await _attemptSend(
        clientMessageId: row.clientMessageId,
        conversationId: row.conversationId,
        otherUserId: other.userId,
        plaintext: row.plaintextContent,
        replyToMessageId: row.replyToMessageId,
      );
      if (result case Err()) {
        await _outboxDao.incrementRetry(row.clientMessageId, row.retryCount + 1);
      }
    }
  }

  @override
  Future<void> subscribeToConversation(String conversationId, String otherUserId) async {
    _realtime.watchConversationMessages(
      conversationId: conversationId,
      onInsert: (payload) => _handleIncomingRow(payload.newRecord, conversationId, otherUserId),
      onUpdate: (payload) => _handleIncomingRow(payload.newRecord, conversationId, otherUserId),
    );
  }

  Future<void> _handleIncomingRow(
    Map<String, dynamic> row,
    String conversationId,
    String otherUserId,
  ) async {
    final senderId = row['sender_id'] as String;
    if (senderId == _myUserId) return; // our own echo, already stored optimistically

    try {
      final senderDeviceUuid = row['sender_device_id'] as String;
      final senderDeviceIntId = deviceUuidToProtocolDeviceId(senderDeviceUuid);
      final ciphertext = row['ciphertext'];
      final wireBytes = ciphertext is String ? base64Decode(ciphertext) : ciphertext as List<int>;
      final envelope = CiphertextEnvelopeCodec.decode(wireBytes);

      final decryptResult = await _sessionManager.decrypt(
        remoteUserId: senderId,
        remoteDeviceId: senderDeviceIntId,
        envelope: envelope,
      );
      if (decryptResult case Err(:final failure)) {
        _log.warning('Could not decrypt incoming message: ${failure.message}');
        return;
      }
      final plaintext = utf8.decode((decryptResult as Ok<Uint8List>).value);

      await _messageDao.upsertMessage(LocalMessagesCompanion.insert(
        id: row['id'] as String,
        conversationId: conversationId,
        senderId: senderId,
        senderDeviceId: senderDeviceUuid,
        content: plaintext,
        messageType: row['message_type'] as String? ?? 'text',
        clientSentAt: DateTime.parse(row['client_sent_at'] as String),
        serverReceivedAt: Value(DateTime.parse(row['server_received_at'] as String)),
        replyToMessageId: Value(row['reply_to_message_id'] as String?),
        deliveryStatus: const Value('delivered'),
      ));
      await _conversationDao.touchLastMessage(
        conversationId: conversationId,
        preview: plaintext,
        at: DateTime.parse(row['server_received_at'] as String),
      );

      await _client.from('read_receipts').upsert({
        'message_id': row['id'],
        'user_id': _myUserId,
        'status': 'delivered',
      });
    } catch (e, st) {
      _log.error('Failed to process incoming message', e, st);
    }
  }

  @override
  Future<void> unsubscribeFromConversation(String conversationId) async {
    await _realtime.unsubscribeAll(); // Phase 1: one thread open at a time
  }

  @override
  Future<void> sendTypingIndicator({
    required String conversationId,
    required bool isTyping,
  }) {
    return _realtime.sendTyping(conversationId: conversationId, isTyping: isTyping);
  }

  @override
  Stream<bool> watchTyping(String conversationId, String otherUserId) {
    final controller = StreamController<bool>.broadcast();
    _realtime.watchTyping(
      conversationId: conversationId,
      onTyping: (payload) {
        if (payload['user_id'] == otherUserId) {
          controller.add(payload['is_typing'] as bool? ?? false);
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> markRead(String conversationId, String messageId) async {
    await _messageDao.markDeliveryStatus(messageId, 'read');
    await _client.from('read_receipts').upsert({
      'message_id': messageId,
      'user_id': _myUserId,
      'status': 'read',
    });
  }
}
