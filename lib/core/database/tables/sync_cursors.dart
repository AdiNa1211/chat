import 'package:drift/drift.dart';

/// One row per conversation: the last `server_received_at` this device
/// has fully synced, so a reconnect (Section 12.3) can do a bounded
/// catch-up query before resubscribing to Realtime instead of refetching
/// everything.
class SyncCursors extends Table {
  TextColumn get conversationId => text()();
  DateTimeColumn get lastSyncedServerReceivedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {conversationId};
}
