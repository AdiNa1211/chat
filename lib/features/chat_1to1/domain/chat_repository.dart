import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/entities/conversation.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/entities/message.dart';

abstract interface class ChatRepository {
  /// Local-first (Section 12.1) — reflects the Drift mirror immediately,
  /// then updates as Supabase/Realtime data arrives.
  Stream<List<Conversation>> watchConversations();

  Stream<List<Message>> watchMessages(String conversationId);

  /// Finds or creates the 1:1 conversation with `otherUserId` (Section 3
  /// "New chat" flow) — local lookup first, only hits Supabase if not
  /// found locally.
  Future<Result<Conversation>> startOrGetDirectConversation(String otherUserId);

  /// Encrypts and sends (Section 8/9), or — if offline — enqueues to the
  /// local outbox for the background sync worker (Section 12.2) to drain.
  /// Returns immediately after the optimistic local write so the UI can
  /// show the message right away.
  Future<Result<void>> sendTextMessage({
    required String conversationId,
    required String otherUserId,
    required String plaintext,
    String? replyToMessageId,
  });

  Future<void> sendTypingIndicator({required String conversationId, required bool isTyping});

  Stream<bool> watchTyping(String conversationId, String otherUserId);

  Future<void> markRead(String conversationId, String messageId);

  /// Begins listening to Realtime for this conversation and reconciling
  /// against the local mirror (Section 11/12.3) — call when a thread
  /// screen opens; the returned subscription handle should be disposed
  /// when it closes.
  Future<void> subscribeToConversation(String conversationId, String otherUserId);

  Future<void> unsubscribeFromConversation(String conversationId);

  /// Drains the offline outbox (Section 12.2) — called by
  /// `OutboxSyncService` on reconnect and on a periodic timer while
  /// online. Exposed on the interface (rather than kept private to the
  /// impl) so it's independently testable with a fake repository.
  Future<void> drainOutbox();
}
