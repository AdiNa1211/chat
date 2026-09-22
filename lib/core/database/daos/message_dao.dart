import 'package:drift/drift.dart';

import 'package:secure_chat_app/core/database/app_database.dart';
import 'package:secure_chat_app/core/database/tables/local_messages.dart';

part 'message_dao.g.dart';

@DriftAccessor(tables: [LocalMessages, LocalAttachments])
class MessageDao extends DatabaseAccessor<AppDatabase> with _$MessageDaoMixin {
  MessageDao(super.db);

  /// Ordering is authoritative server time (Section 12.4): a null
  /// `serverReceivedAt` (still-optimistic, not yet acked) sorts last.
  Stream<List<LocalMessage>> watchMessages(String conversationId) {
    return (select(localMessages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.serverReceivedAt,
                  mode: OrderingMode.asc,
                  nulls: NullsOrder.last,
                ),
            (t) => OrderingTerm(expression: t.clientSentAt),
          ]))
        .watch();
  }

  Future<void> upsertMessage(LocalMessagesCompanion entry) {
    return into(localMessages).insertOnConflictUpdate(entry);
  }

  Future<void> markDeliveryStatus(String messageId, String status) {
    return (update(localMessages)..where((t) => t.id.equals(messageId)))
        .write(LocalMessagesCompanion(deliveryStatus: Value(status)));
  }

  /// Local full-text search across synced history (Section 13) — plain
  /// LIKE for Phase 1; swap for an FTS5 virtual table once search volume
  /// warrants it.
  Future<List<LocalMessage>> searchMessages(String query) {
    return (select(localMessages)
          ..where((t) => t.content.like('%$query%'))
          ..orderBy([(t) => OrderingTerm.desc(t.serverReceivedAt)])
          ..limit(100))
        .get();
  }

  Future<void> upsertAttachment(LocalAttachmentsCompanion entry) {
    return into(localAttachments).insertOnConflictUpdate(entry);
  }

  Future<LocalAttachment?> attachmentForMessage(String messageId) {
    return (select(localAttachments)..where((t) => t.messageId.equals(messageId)))
        .getSingleOrNull();
  }
}
