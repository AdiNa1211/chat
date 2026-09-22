import 'package:drift/drift.dart';

class LocalConversations extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // 'direct' | 'group' (group is Phase 2)
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get lastMessagePreview => text().nullable()(); // decrypted, local-only
  DateTimeColumn get lastMessageAt => dateTime().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirrors `conversation_members`; for Phase 1 (1:1 only) each direct
/// conversation has exactly two rows here.
class LocalConversationMembers extends Table {
  TextColumn get conversationId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text().withDefault(const Constant('member'))();
  DateTimeColumn get joinedAt => dateTime()();
  DateTimeColumn get mutedUntil => dateTime().nullable()();
  TextColumn get lastReadMessageId => text().nullable()();

  @override
  Set<Column> get primaryKey => {conversationId, userId};
}
