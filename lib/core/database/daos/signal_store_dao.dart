import 'dart:typed_data';

import 'package:drift/drift.dart';

import 'package:secure_chat_app/core/database/app_database.dart';
import 'package:secure_chat_app/core/database/tables/signal_store_tables.dart';

part 'signal_store_dao.g.dart';

/// Pure data-access layer for Signal Protocol key material — deliberately
/// dumb (no crypto logic here). `core/crypto/signal_store_adapter.dart`
/// implements the `IdentityKeyStore`/`PreKeyStore`/`SignedPreKeyStore`/
/// `SessionStore` interfaces from `libsignal_protocol_dart` on top of this
/// DAO, which keeps the persistence boundary distinct from the crypto
/// boundary (Section 4: repository pattern as the security boundary).
@DriftAccessor(tables: [
  SignalIdentities,
  SignalPreKeys,
  SignalSignedPreKeys,
  SignalSessions,
  SignalIdentityTrust,
])
class SignalStoreDao extends DatabaseAccessor<AppDatabase>
    with _$SignalStoreDaoMixin {
  SignalStoreDao(super.db);

  // -- Identity ---------------------------------------------------------
  Future<SignalIdentity?> getOwnIdentity() =>
      (select(signalIdentities)..where((t) => t.id.equals(1))).getSingleOrNull();

  Future<void> saveOwnIdentity({
    required Uint8List identityKeyPairBytes,
    required int registrationId,
  }) {
    return into(signalIdentities).insertOnConflictUpdate(
      SignalIdentitiesCompanion.insert(
        id: const Value(1),
        identityKeyPairBytes: identityKeyPairBytes,
        registrationId: registrationId,
      ),
    );
  }

  // -- Prekeys ------------------------------------------------------------
  Future<SignalPreKey?> getPreKey(int keyId) =>
      (select(signalPreKeys)..where((t) => t.keyId.equals(keyId))).getSingleOrNull();

  Future<void> savePreKey(int keyId, Uint8List recordBytes) {
    return into(signalPreKeys).insertOnConflictUpdate(
      // keyId is a single-column INTEGER primary key, so SQLite/Drift treats
      // it as an optional rowid alias — must be wrapped even though we
      // always supply it ourselves (Signal assigns prekey ids, not SQLite).
      SignalPreKeysCompanion.insert(keyId: Value(keyId), recordBytes: recordBytes),
    );
  }

  Future<void> removePreKey(int keyId) =>
      (delete(signalPreKeys)..where((t) => t.keyId.equals(keyId))).go();

  Future<int> countRemainingPreKeys() async {
    final rows = await select(signalPreKeys).get();
    return rows.length;
  }

  // -- Signed prekeys -------------------------------------------------------
  Future<SignalSignedPreKey?> getSignedPreKey(int keyId) =>
      (select(signalSignedPreKeys)..where((t) => t.keyId.equals(keyId))).getSingleOrNull();

  Future<List<SignalSignedPreKey>> allSignedPreKeys() => select(signalSignedPreKeys).get();

  Future<void> saveSignedPreKey(int keyId, Uint8List recordBytes) {
    return into(signalSignedPreKeys).insertOnConflictUpdate(
      SignalSignedPreKeysCompanion.insert(
        keyId: Value(keyId), // see savePreKey: single-column int PK is optional
        recordBytes: recordBytes,
        createdAt: DateTime.now(),
      ),
    );
  }

  // -- Sessions ------------------------------------------------------------
  Future<SignalSession?> getSession(String addressName, int deviceId) {
    return (select(signalSessions)
          ..where((t) => t.addressName.equals(addressName) & t.addressDeviceId.equals(deviceId)))
        .getSingleOrNull();
  }

  Future<List<SignalSession>> getSubDeviceSessions(String addressName) {
    return (select(signalSessions)..where((t) => t.addressName.equals(addressName))).get();
  }

  Future<void> saveSession(String addressName, int deviceId, Uint8List recordBytes) {
    return into(signalSessions).insertOnConflictUpdate(
      SignalSessionsCompanion.insert(
        addressName: addressName,
        addressDeviceId: deviceId,
        sessionRecordBytes: recordBytes,
      ),
    );
  }

  Future<void> deleteSession(String addressName, int deviceId) {
    return (delete(signalSessions)
          ..where((t) => t.addressName.equals(addressName) & t.addressDeviceId.equals(deviceId)))
        .go();
  }

  Future<void> deleteAllSessionsFor(String addressName) {
    return (delete(signalSessions)..where((t) => t.addressName.equals(addressName))).go();
  }

  // -- Identity trust (safety-number pinning, Section 8.6/8.7) -------------
  Future<SignalIdentityTrustData?> getTrustedIdentity(String addressName, int deviceId) {
    return (select(signalIdentityTrust)
          ..where((t) => t.addressName.equals(addressName) & t.addressDeviceId.equals(deviceId)))
        .getSingleOrNull();
  }

  Future<void> pinIdentity({
    required String addressName,
    required int deviceId,
    required Uint8List identityKeyBytes,
  }) {
    return into(signalIdentityTrust).insertOnConflictUpdate(
      SignalIdentityTrustCompanion.insert(
        addressName: addressName,
        addressDeviceId: deviceId,
        identityKeyBytes: identityKeyBytes,
        firstSeenAt: DateTime.now(),
      ),
    );
  }

  Future<void> markVerified(String addressName, int deviceId) {
    return (update(signalIdentityTrust)
          ..where((t) => t.addressName.equals(addressName) & t.addressDeviceId.equals(deviceId)))
        .write(const SignalIdentityTrustCompanion(verified: Value(true)));
  }
}
