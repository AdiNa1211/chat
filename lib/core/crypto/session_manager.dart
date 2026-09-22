import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:secure_chat_app/core/crypto/models/device_prekey_bundle.dart';
import 'package:secure_chat_app/core/crypto/signal_store_adapter.dart';
import 'package:secure_chat_app/core/error/failures.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';

/// Encrypted bytes plus the framing `SessionCipher` needs to know how to
/// decrypt them (Section 8.3: the very first message in a session is a
/// `PreKeySignalMessage`; every message after that is a plain
/// `SignalMessage` riding the Double Ratchet).
class EncryptedEnvelope {
  const EncryptedEnvelope({required this.bytes, required this.isPreKeyMessage});

  final Uint8List bytes;
  final bool isPreKeyMessage;
}

/// Raised (via `Result`/`Err`) when `saveIdentity` reports the remote
/// party's identity key changed since we last saw it (Section 8.6/8.7).
/// The UI must show this prominently — never suppress or auto-retry past
/// it silently, since it's indistinguishable on the wire from an actual
/// man-in-the-middle.
class IdentityChangedFailure extends CryptoFailure {
  const IdentityChangedFailure(this.remoteUserId, this.remoteDeviceId)
      : super('This contact\'s safety number has changed. Verify before continuing.');

  final String remoteUserId;
  final int remoteDeviceId;
}

/// Owns X3DH session establishment (Section 8.3) and per-message Double
/// Ratchet encrypt/decrypt (Section 8.4) for 1:1 conversations. Group
/// Sender Keys (Section 8.4, groups) are Phase 2 and live in a sibling
/// class, not here.
class SessionManager {
  SessionManager(this._store);

  final SignalStoreAdapter _store;
  final _log = AppLogger.forName('SessionManager');

  /// Establishes a session with a remote device if one doesn't already
  /// exist locally. Safe to call before every send — a no-op (just an
  /// existence check) once a session is already up, since libsignal's
  /// session store makes this idempotent.
  Future<Result<void>> ensureSession(RemotePreKeyBundle remote) async {
    try {
      final address = SignalProtocolAddress(remote.remoteUserId, remote.remoteDeviceId);
      if (await _store.containsSession(address)) {
        return const Ok(null);
      }

      final bundle = PreKeyBundle(
        remote.registrationId,
        remote.remoteDeviceId,
        remote.oneTimePreKeyId,
        remote.oneTimePreKeyPublic == null
            ? null
            : Curve.decodePoint(remote.oneTimePreKeyPublic!, 0),
        remote.signedPreKeyId,
        Curve.decodePoint(remote.signedPreKeyPublic, 0),
        remote.signedPreKeySignature,
        IdentityKey.fromBytes(remote.identityPublicKey, 0),
      );

      final builder = SessionBuilder(_store, _store, _store, _store, address);
      await builder.processPreKeyBundle(bundle);

      _log.info('X3DH session established with ${remote.remoteUserId}:${remote.remoteDeviceId}');
      return const Ok(null);
    } on UntrustedIdentityException {
      return Err(IdentityChangedFailure(remote.remoteUserId, remote.remoteDeviceId));
    } catch (e, st) {
      _log.error('Session establishment failed', e, st);
      return const Err(CryptoFailure('Could not establish a secure session.'));
    }
  }

  Future<Result<EncryptedEnvelope>> encrypt({
    required String remoteUserId,
    required int remoteDeviceId,
    required Uint8List plaintext,
  }) async {
    try {
      final address = SignalProtocolAddress(remoteUserId, remoteDeviceId);
      final cipher = SessionCipher(_store, _store, _store, _store, address);
      final message = await cipher.encrypt(plaintext);
      return Ok(
        EncryptedEnvelope(
          bytes: Uint8List.fromList(message.serialize()),
          isPreKeyMessage: message.getType() == CiphertextMessage.prekeyType,
        ),
      );
    } catch (e, st) {
      _log.error('Encryption failed', e, st);
      return const Err(CryptoFailure('This message could not be encrypted.'));
    }
  }

  Future<Result<Uint8List>> decrypt({
    required String remoteUserId,
    required int remoteDeviceId,
    required EncryptedEnvelope envelope,
  }) async {
    try {
      final address = SignalProtocolAddress(remoteUserId, remoteDeviceId);
      final cipher = SessionCipher(_store, _store, _store, _store, address);

      final plaintext = envelope.isPreKeyMessage
          ? await cipher.decrypt(PreKeySignalMessage(envelope.bytes))
          : await cipher.decryptFromSignal(SignalMessage.fromSerialized(envelope.bytes));

      return Ok(Uint8List.fromList(plaintext));
    } on UntrustedIdentityException {
      return Err(IdentityChangedFailure(remoteUserId, remoteDeviceId));
    } catch (e, st) {
      // Tampered, truncated, or reordered-beyond-window ciphertext lands
      // here too — libsignal_protocol_dart doesn't export a dedicated MAC
      // failure exception type, so every decrypt failure fails closed
      // uniformly (Section 18) rather than trying to distinguish causes.
      _log.warning('Decryption failed (possibly tampered/corrupted ciphertext)', e, st);
      return const Err(CryptoFailure());
    }
  }

  /// Explicit safety-number verification (Section 8.6): call after the
  /// user confirms an out-of-band (QR/numeric) comparison matched.
  Future<void> markVerified(String remoteUserId, int remoteDeviceId) {
    return _store.markVerified(remoteUserId, remoteDeviceId);
  }
}
