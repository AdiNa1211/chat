import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:secure_chat_app/core/crypto/models/device_prekey_bundle.dart';
import 'package:secure_chat_app/core/crypto/signal_store_adapter.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';

/// Generates and persists this device's Signal Protocol key material
/// (Section 8.2). Every private key this class touches stays inside
/// `SignalStoreAdapter` (backed by the SQLCipher-encrypted local DB,
/// Section 3) — this class only ever hands the *caller* public bytes,
/// meant for upload.
class IdentityKeyService {
  IdentityKeyService(this._store);

  final SignalStoreAdapter _store;
  final _log = AppLogger.forName('IdentityKeyService');

  static const _initialOneTimePreKeyCount = 100;
  static const _lowWaterMark = 20;

  /// Runs once per device, right after a successful signup/login on a
  /// device that has no identity yet (Section 2.1: Phase 1, "Device/
  /// Identity Keys" step runs immediately after Auth). Idempotent — safe
  /// to call again if it was interrupted, since it checks first.
  ///
  /// Returns both the public bundle *and* the initial one-time prekey
  /// batch it just generated, so the caller can upload all of it in one
  /// go rather than generating a second batch immediately afterwards.
  Future<({DevicePrekeyBundlePublic bundle, List<OneTimePreKeyPublic> oneTimePreKeys})>
      provisionDeviceIfNeeded() async {
    if (await _store.hasOwnIdentity()) {
      _log.info('Device already provisioned; returning existing public bundle.');
      return (bundle: await _currentPublicBundle(), oneTimePreKeys: const <OneTimePreKeyPublic>[]);
    }

    _log.info('Provisioning new device identity (X3DH key material)...');

    final identityKeyPair = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    await _store.persistOwnIdentity(identityKeyPair, registrationId);

    final signedPreKey = await _generateAndStoreSignedPreKey(identityKeyPair);
    final oneTimePreKeys = await _generateAndStoreOneTimePreKeys(_initialOneTimePreKeyCount);

    final bundle = DevicePrekeyBundlePublic(
      registrationId: registrationId,
      identityPublicKey: Uint8List.fromList(identityKeyPair.getPublicKey().serialize()),
      signedPreKeyId: signedPreKey.id,
      signedPreKeyPublic: Uint8List.fromList(signedPreKey.getKeyPair().publicKey.serialize()),
      signedPreKeySignature: Uint8List.fromList(signedPreKey.signature),
    );
    return (bundle: bundle, oneTimePreKeys: oneTimePreKeys);
  }

  /// Called on a schedule / after the `prekey-replenish-check` Edge
  /// Function (Section 5) flags this device as low — tops the pool back
  /// up so X3DH keeps getting the stronger one-time-prekey guarantee
  /// rather than silently degrading (Section 8.5).
  Future<List<OneTimePreKeyPublic>> topUpOneTimePreKeysIfLow() async {
    // A real implementation tracks the server's ack of which ids were
    // consumed; for Phase 1 we regenerate a fresh batch each time this is
    // called by the (infrequent) background check.
    return _generateAndStoreOneTimePreKeys(_initialOneTimePreKeyCount - _lowWaterMark);
  }

  Future<DevicePrekeyBundlePublic> _currentPublicBundle() async {
    final identityPair = await _store.getIdentityKeyPair();
    final registrationId = await _store.getLocalRegistrationId();
    final signedPreKeys = await _store.loadSignedPreKeys();
    final latest = signedPreKeys.last;
    return DevicePrekeyBundlePublic(
      registrationId: registrationId,
      identityPublicKey: Uint8List.fromList(identityPair.getPublicKey().serialize()),
      signedPreKeyId: latest.id,
      signedPreKeyPublic: Uint8List.fromList(latest.getKeyPair().publicKey.serialize()),
      signedPreKeySignature: Uint8List.fromList(latest.signature),
    );
  }

  Future<SignedPreKeyRecord> _generateAndStoreSignedPreKey(IdentityKeyPair identity) async {
    final signedPreKeyId = DateTime.now().millisecondsSinceEpoch % 0x7fffffff;
    final record = generateSignedPreKey(identity, signedPreKeyId);
    await _store.storeSignedPreKey(signedPreKeyId, record);
    return record;
  }

  Future<List<OneTimePreKeyPublic>> _generateAndStoreOneTimePreKeys(int count) async {
    if (count <= 0) return const [];
    final start = DateTime.now().millisecondsSinceEpoch % 0x0fffffff;
    final records = generatePreKeys(start, count);
    final out = <OneTimePreKeyPublic>[];
    for (final record in records) {
      await _store.storePreKey(record.id, record);
      out.add(
        OneTimePreKeyPublic(
          keyId: record.id,
          publicKey: Uint8List.fromList(record.getKeyPair().publicKey.serialize()),
        ),
      );
    }
    return out;
  }

  /// Signed prekey rotation (Section 8.5) — called on a schedule (e.g.
  /// weekly, via a local timer or on app foreground if overdue). The
  /// previous key is left in the store so any X3DH handshake already
  /// in flight against it can still complete; the caller is responsible
  /// for uploading the new public bundle and, after a grace period,
  /// invoking `_store`'s removal path for the old one.
  Future<DevicePrekeyBundlePublic> rotateSignedPreKey() async {
    final identity = await _store.getIdentityKeyPair();
    final record = await _generateAndStoreSignedPreKey(identity);
    final registrationId = await _store.getLocalRegistrationId();
    return DevicePrekeyBundlePublic(
      registrationId: registrationId,
      identityPublicKey: Uint8List.fromList(identity.getPublicKey().serialize()),
      signedPreKeyId: record.id,
      signedPreKeyPublic: Uint8List.fromList(record.getKeyPair().publicKey.serialize()),
      signedPreKeySignature: Uint8List.fromList(record.signature),
    );
  }
}
