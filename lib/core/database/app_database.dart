import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import 'package:secure_chat_app/core/database/tables/local_conversations.dart';
import 'package:secure_chat_app/core/database/tables/local_messages.dart';
import 'package:secure_chat_app/core/database/tables/local_profiles.dart';
import 'package:secure_chat_app/core/database/tables/outbox.dart';
import 'package:secure_chat_app/core/database/tables/signal_store_tables.dart';
import 'package:secure_chat_app/core/database/tables/sync_cursors.dart';
import 'package:secure_chat_app/core/database/daos/conversation_dao.dart';
import 'package:secure_chat_app/core/database/daos/message_dao.dart';
import 'package:secure_chat_app/core/database/daos/outbox_dao.dart';
import 'package:secure_chat_app/core/database/daos/signal_store_dao.dart';

part 'app_database.g.dart';

/// The device's full local, encrypted mirror (Section 3 / 12 of the spec):
/// conversations, messages, the offline outbox, and Signal Protocol key
/// material. Encrypted at rest with SQLCipher on Android/iOS/desktop.
///
/// NOT Web-compatible yet: `NativeDatabase`/SQLCipher are dart:io-based.
/// A real Web build needs a swapped-in WASM/IndexedDB backend with
/// application-layer AES-GCM row encryption behind a conditional import —
/// that file does not exist in this Phase 1 tree yet (mobile-first
/// milestone); adding it is a prerequisite for Web, not a nice-to-have.
@DriftDatabase(
  tables: [
    LocalProfiles,
    LocalConversations,
    LocalConversationMembers,
    LocalMessages,
    LocalAttachments,
    PendingOutbox,
    SignalIdentities,
    SignalPreKeys,
    SignalSignedPreKeys,
    SignalSessions,
    SignalIdentityTrust,
    SyncCursors,
  ],
  daos: [ConversationDao, MessageDao, OutboxDao, SignalStoreDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens (creating if needed) the encrypted local database, keyed by a
  /// passphrase that itself never touches disk in plaintext — the caller
  /// (`DatabaseKeyProvider`, core/crypto) sources it from platform secure
  /// storage, generating a fresh random passphrase on first run.
  factory AppDatabase.open({required String sqlCipherPassphrase}) {
    return AppDatabase(_openConnection(sqlCipherPassphrase));
  }

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection(String passphrase) {
    return LazyDatabase(() async {
      // Ensures the correct sqlite3/SQLCipher native libraries are loaded
      // on every supported platform before opening the database file.
      applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
      final cachebase = await getApplicationSupportDirectory();
      final file = File(p.join(cachebase.path, 'secure_chat.sqlite'));
      return NativeDatabase.createInBackground(
        file,
        setup: (rawDb) {
          // Full-database AES-256 encryption. The key never touches this
          // process's disk logging or crash reports — it's threaded in
          // directly from secure storage at open time (Section 3, 15.3).
          rawDb.execute("PRAGMA key = '$passphrase';");
          rawDb.execute('PRAGMA cipher_page_size = 4096;');
          rawDb.execute('PRAGMA foreign_keys = ON;');
        },
      );
    });
  }
}
