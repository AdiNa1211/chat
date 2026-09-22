import 'package:drift/drift.dart';

import 'package:secure_chat_app/core/database/app_database.dart';
import 'package:secure_chat_app/core/database/tables/outbox.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [PendingOutbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  Future<void> enqueue(PendingOutboxCompanion entry) {
    return into(pendingOutbox).insertOnConflictUpdate(entry);
  }

  Stream<List<PendingOutboxData>> watchQueued() {
    return (select(pendingOutbox)
          ..where((t) => t.status.isNotValue('sent'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<PendingOutboxData>> nextBatch({int limit = 20}) {
    return (select(pendingOutbox)
          ..where((t) => t.status.equals('queued') | t.status.equals('failed'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> markSending(String clientMessageId) {
    return (update(pendingOutbox)..where((t) => t.clientMessageId.equals(clientMessageId)))
        .write(const PendingOutboxCompanion(status: Value('sending')));
  }

  Future<void> markFailed(String clientMessageId, String error) {
    return (update(pendingOutbox)..where((t) => t.clientMessageId.equals(clientMessageId)))
        .write(PendingOutboxCompanion(
      status: const Value('failed'),
      lastError: Value(error),
      retryCount: const Value.absent(),
    ));
  }

  Future<void> incrementRetry(String clientMessageId, int newCount) {
    return (update(pendingOutbox)..where((t) => t.clientMessageId.equals(clientMessageId)))
        .write(PendingOutboxCompanion(retryCount: Value(newCount)));
  }

  Future<void> remove(String clientMessageId) {
    return (delete(pendingOutbox)..where((t) => t.clientMessageId.equals(clientMessageId))).go();
  }
}
