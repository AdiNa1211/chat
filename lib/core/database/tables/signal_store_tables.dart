import 'package:drift/drift.dart';

/// Backing tables for the Signal Protocol stores (Section 8). Everything
/// here lives only inside this device's SQLCipher-encrypted database —
/// private key bytes never leave this table, let alone this device.

/// Singleton row (id is always 1): this device's own long-term identity
/// key pair and local registration id (Section 8.2).
class SignalIdentities extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  BlobColumn get identityKeyPairBytes => blob()(); // serialized IdentityKeyPair
  IntColumn get registrationId => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// This device's own one-time prekeys (private halves). A row is removed
/// once consumed locally (mirrors server-side consumption bookkeeping,
/// Section 7's `consume_one_time_prekey`).
class SignalPreKeys extends Table {
  IntColumn get keyId => integer()();
  BlobColumn get recordBytes => blob()(); // serialized PreKeyRecord

  @override
  Set<Column> get primaryKey => {keyId};
}

class SignalSignedPreKeys extends Table {
  IntColumn get keyId => integer()();
  BlobColumn get recordBytes => blob()(); // serialized SignedPreKeyRecord
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {keyId};
}

/// Double Ratchet session state per (contact user id, contact device id) —
/// this is `encryption_key_material.wrapped_session_state`'s *unwrapped*
/// form, kept only here, never uploaded in this form (Section 8.4).
class SignalSessions extends Table {
  TextColumn get addressName => text()(); // remote user id
  IntColumn get addressDeviceId => integer()();
  BlobColumn get sessionRecordBytes => blob()();

  @override
  Set<Column> get primaryKey => {addressName, addressDeviceId};
}

/// Trust-on-first-use identity pinning: the identity public key this
/// device last saw for (user, device), so a later change can be detected
/// and surfaced as a safety-number warning (Section 8.6/8.7) instead of
/// silently trusted.
class SignalIdentityTrust extends Table {
  TextColumn get addressName => text()();
  IntColumn get addressDeviceId => integer()();
  BlobColumn get identityKeyBytes => blob()();
  DateTimeColumn get firstSeenAt => dateTime()();
  BoolColumn get verified => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {addressName, addressDeviceId};
}
