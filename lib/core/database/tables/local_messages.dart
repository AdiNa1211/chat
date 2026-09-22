import 'package:drift/drift.dart';

/// Local mirror of `messages` — but here `content` is **decrypted
/// plaintext**, because this database only ever exists inside this
/// device's own encrypted-at-rest storage (SQLCipher, Section 3/12). This
/// is what makes offline chat history and local search (Section 13)
/// possible without a network round trip or a fresh decrypt each time.
class LocalMessages extends Table {
  TextColumn get id => text()(); // server message id once synced, else the client uuid
  TextColumn get conversationId => text()();
  TextColumn get senderId => text()();
  TextColumn get senderDeviceId => text()();
  TextColumn get content => text()(); // decrypted plaintext (text messages)
  TextColumn get messageType => text()(); // 'text' | 'media' | 'system'
  TextColumn get replyToMessageId => text().nullable()();
  DateTimeColumn get clientSentAt => dateTime()();
  DateTimeColumn get serverReceivedAt => dateTime().nullable()();
  DateTimeColumn get editedAt => dateTime().nullable()();
  DateTimeColumn get deletedForEveryoneAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  // sending | sent | delivered | read | failed (Section 2/12)
  TextColumn get deliveryStatus => text().withDefault(const Constant('sending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local mirror of `message_attachments`, plus a pointer to the locally
/// decrypted cache file (Section 9.2), which is cleaned up independently
/// of this metadata row.
class LocalAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get messageId => text()();
  TextColumn get storagePath => text()(); // opaque Supabase Storage path
  TextColumn get fileName => text()(); // decrypted, from encrypted_metadata
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get localCachePath => text().nullable()(); // null until downloaded+decrypted
  // pending | downloading | downloaded | failed
  TextColumn get downloadStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
