import 'package:drift/drift.dart';

import 'package:secure_chat_app/core/database/app_database.dart';
import 'package:secure_chat_app/core/database/tables/local_conversations.dart';

part 'conversation_dao.g.dart';

@DriftAccessor(tables: [LocalConversations, LocalConversationMembers])
class ConversationDao extends DatabaseAccessor<AppDatabase>
    with _$ConversationDaoMixin {
  ConversationDao(super.db);

  /// Reactive chat-list stream, newest activity first — this is what the
  /// chat list screen watches; it updates the instant a new message is
  /// inserted locally (Section 12.1, local-first).
  Stream<List<LocalConversation>> watchConversations() {
    return (select(localConversations)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.lastMessageAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
          ]))
        .watch();
  }

  Future<LocalConversation?> findDirectConversationWith(
    String myUserId,
    String otherUserId,
  ) async {
    // A direct conversation is uniquely identified by its two members;
    // this scans local membership rows rather than round-tripping to
    // Supabase, so "open chat with X" works offline once synced once.
    final query = select(localConversations).join([
      innerJoin(
        localConversationMembers,
        localConversationMembers.conversationId.equalsExp(localConversations.id) &
            localConversationMembers.userId.equals(otherUserId),
      ),
    ])
      ..where(localConversations.type.equals('direct'));
    final rows = await query.get();
    for (final row in rows) {
      final convo = row.readTable(localConversations);
      final members = await (select(localConversationMembers)
            ..where((t) => t.conversationId.equals(convo.id)))
          .get();
      final memberIds = members.map((m) => m.userId).toSet();
      if (memberIds.contains(myUserId) && memberIds.contains(otherUserId)) {
        return convo;
      }
    }
    return null;
  }

  Future<void> upsertConversation(LocalConversationsCompanion entry) {
    return into(localConversations).insertOnConflictUpdate(entry);
  }

  Future<void> upsertMember(LocalConversationMembersCompanion entry) {
    return into(localConversationMembers).insertOnConflictUpdate(entry);
  }

  Future<void> touchLastMessage({
    required String conversationId,
    required String preview,
    required DateTime at,
  }) {
    return (update(localConversations)..where((t) => t.id.equals(conversationId)))
        .write(LocalConversationsCompanion(
      lastMessagePreview: Value(preview),
      lastMessageAt: Value(at),
    ));
  }
}
