import 'package:drift/drift.dart';

/// The offline outbox (Section 12.2): a message composed while offline —
/// or simply not yet acknowledged — lives here until the send succeeds.
class PendingOutbox extends Table {
  TextColumn get clientMessageId => text()(); // stable client-generated uuid
  TextColumn get conversationId => text()();
  TextColumn get plaintextContent => text()();
  TextColumn get messageType => text().withDefault(const Constant('text'))();
  TextColumn get replyToMessageId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  // queued | sending | failed
  TextColumn get status => text().withDefault(const Constant('queued'))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientMessageId};
}
