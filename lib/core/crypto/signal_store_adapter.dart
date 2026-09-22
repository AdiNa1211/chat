import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:secure_chat_app/core/database/daos/signal_store_dao.dart';

/// Implements every store interface `libsignal_protocol_dart` needs
/// (`IdentityKeyStore`, `PreKeyStore`, `SignedPreKeyStore`, `SessionStore`)
/// on top of the local encrypted database (Section 8). This is the single
/// seam between "the Signal Protocol library's idea of storage" and "how
/// we actually persist it" — nothing else in the app talks to
/// `SignalStoreDao` for key material directly.
///
/// NOTE: `libsignal_protocol_dart`'s exact store-interface method
/// signatures can shift slightly between versions. This adapter follows
/// the conventions common across the Signal Protocol's Java/JS/Dart ports
/// (Curve25519 identity keys, integer prekey ids, `SignalProtocolAddress`
/// keyed by name+deviceId). Run `flutter pub get` and `flutter analyze`
/// against the pinned version in `pubspec.yaml` as the first local step —
/// pub.dev wasn't reachable from the build sandbox this was written in to
/// pin exact method names against the installed version's API docs.
class SignalStoreAdapter
    implements IdentityKeyStore, PreKeyStore, SignedPreKeyStore, SessionStore {
  SignalStoreAdapter(this._dao);

  final SignalStoreDao _dao;

  IdentityKeyPair? _cachedIdentity;
  int? _cachedRegistrationId;

  /// Called once, on first app run for this device, after
  /// `IdentityKeyService` generates a fresh identity key pair.
  Future<void> persistOwnIdentity(IdentityKeyPair pair, int registrationId) async {
    await _dao.saveOwnIdentity(
      identityKeyPairBytes: pair.serialize(),
      registrationId: registrationId,
    );
    _cachedIdentity = pair;
    _cachedRegistrationId = registrationId;
  }

  Future<bool> hasOwnIdentity() async => (await _dao.getOwnIdentity()) != null;

  // -- IdentityKeyStore -----------------------------------------------------
  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    if (_cachedIdentity != null) return _cachedIdentity!;
    final row = await _dao.getOwnIdentity();
    if (row == null) {
      throw StateError(
        'No identity key pair provisioned for this device yet — '
        'call IdentityKeyService.provisionDevice() first.',
      );
    }
    _cachedIdentity = IdentityKeyPair.fromSerialized(row.identityKeyPairBytes);
    return _cachedIdentity!;
  }

  @override
  Future<int> getLocalRegistrationId() async {
    if (_cachedRegistrationId != null) return _cachedRegistrationId!;
    final row = await _dao.getOwnIdentity();
    if (row == null) {
      throw StateError('No registration id provisioned for this device yet.');
    }
    _cachedRegistrationId = row.registrationId;
    return _cachedRegistrationId!;
  }

  @override
  Future<bool> saveIdentity(SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;
    final existing = await _dao.getTrustedIdentity(address.getName(), address.getDeviceId());
    final changed = existing != null &&
        !_bytesEqual(existing.identityKeyBytes, identityKey.serialize());
    await _dao.pinIdentity(
      addressName: address.getName(),
      deviceId: address.getDeviceId(),
      identityKeyBytes: identityKey.serialize(),
    );
    // `changed == true` is exactly the "safety number changed" signal
    // (Section 8.6/8.7) — the caller (SessionManager) surfaces this to the
    // UI rather than this low-level store deciding what to do about it.
    return changed;
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    if (identityKey == null) return false;
    final existing = await _dao.getTrustedIdentity(address.getName(), address.getDeviceId());
    // Trust-on-first-use: an identity we've never seen for this
    // address is trusted provisionally (X3DH still ran; Section 8.6's
    // out-of-band verification is what upgrades "provisional" to
    // "verified" — this method only guards against a *silent switch*
    // after the fact).
    if (existing == null) return true;
    return _bytesEqual(existing.identityKeyBytes, identityKey.serialize());
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final row = await _dao.getTrustedIdentity(address.getName(), address.getDeviceId());
    if (row == null) return null;
    return IdentityKey.fromBytes(row.identityKeyBytes, 0);
  }

  // -- PreKeyStore ----------------------------------------------------------
  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final row = await _dao.getPreKey(preKeyId);
    if (row == null) throw InvalidKeyIdException('No such prekey: $preKeyId');
    return PreKeyRecord.fromBuffer(row.recordBytes);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) {
    return _dao.savePreKey(preKeyId, record.serialize());
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async => (await _dao.getPreKey(preKeyId)) != null;

  @override
  Future<void> removePreKey(int preKeyId) => _dao.removePreKey(preKeyId);

  // -- SignedPreKeyStore ------------------------------------------------------
  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final row = await _dao.getSignedPreKey(signedPreKeyId);
    if (row == null) {
      throw InvalidKeyIdException('No such signed prekey: $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(row.recordBytes);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final rows = await _dao.allSignedPreKeys();
    return rows.map((r) => SignedPreKeyRecord.fromSerialized(r.recordBytes)).toList();
  }

  @override
  Future<void> storeSignedPreKey(int signedPreKeyId, SignedPreKeyRecord record) {
    return _dao.saveSignedPreKey(signedPreKeyId, record.serialize());
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      (await _dao.getSignedPreKey(signedPreKeyId)) != null;

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    // Retained briefly server-side (Section 8.5) but fine to drop locally
    // once rotated — this device doesn't need to prove past prekeys.
  }

  // -- SessionStore -----------------------------------------------------
  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final row = await _dao.getSession(address.getName(), address.getDeviceId());
    if (row == null) return SessionRecord();
    return SessionRecord.fromSerialized(row.sessionRecordBytes);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final rows = await _dao.getSubDeviceSessions(name);
    return rows.map((r) => r.addressDeviceId).toList();
  }

  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) {
    return _dao.saveSession(address.getName(), address.getDeviceId(), record.serialize());
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async {
    final row = await _dao.getSession(address.getName(), address.getDeviceId());
    return row != null;
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) {
    return _dao.deleteSession(address.getName(), address.getDeviceId());
  }

  @override
  Future<void> deleteAllSessions(String name) => _dao.deleteAllSessionsFor(name);

  /// Records that the user confirmed an out-of-band safety-number match
  /// (Section 8.6) for this address.
  Future<void> markVerified(String addressName, int deviceId) {
    return _dao.markVerified(addressName, deviceId);
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
