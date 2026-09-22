import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:secure_chat_app/core/crypto/device_id_codec.dart';
import 'package:secure_chat_app/core/crypto/identity_key_service.dart';
import 'package:secure_chat_app/core/crypto/models/device_prekey_bundle.dart';
import 'package:secure_chat_app/core/crypto/session_manager.dart';
import 'package:secure_chat_app/core/crypto/signal_store_adapter.dart';
import 'package:secure_chat_app/core/database/app_database.dart';
import 'package:secure_chat_app/core/database/daos/signal_store_dao.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/features/chat_1to1/data/ciphertext_envelope.dart';

/// End-to-end test of the real protocol stack (X3DH + Double Ratchet,
/// Section 8) using the app's own classes wired together exactly as
/// `injection_container.dart` will wire them per real device — just with
/// an in-memory Drift database standing in for the SQLCipher-encrypted
/// one, since the protocol logic doesn't care how its store is backed.
///
/// NOTE: this needs the native sqlite3 library (bundled for desktop/CI by
/// `sqlite3_flutter_libs`) to back `NativeDatabase.memory()`. It does NOT
/// need SQLCipher itself — no passphrase, no PRAGMA key — because this
/// test never opens the real encrypted `AppDatabase.open()` path.
class _FakeDevice {
  _FakeDevice(this.userId, this.deviceUuid) : db = AppDatabase(NativeDatabase.memory()) {
    store = SignalStoreAdapter(SignalStoreDao(db));
    identityService = IdentityKeyService(store);
    sessionManager = SessionManager(store);
  }

  final String userId;
  final String deviceUuid;
  final AppDatabase db;
  late final SignalStoreAdapter store;
  late final IdentityKeyService identityService;
  late final SessionManager sessionManager;

  int get protocolDeviceId => deviceUuidToProtocolDeviceId(deviceUuid);

  Future<void> close() => db.close();
}

RemotePreKeyBundle _remoteBundleFrom(
  _FakeDevice device,
  DevicePrekeyBundlePublic bundle, {
  OneTimePreKeyPublic? oneTimePreKey,
}) {
  return RemotePreKeyBundle(
    remoteUserId: device.userId,
    remoteDeviceId: device.protocolDeviceId,
    registrationId: bundle.registrationId,
    identityPublicKey: bundle.identityPublicKey,
    signedPreKeyId: bundle.signedPreKeyId,
    signedPreKeyPublic: bundle.signedPreKeyPublic,
    signedPreKeySignature: bundle.signedPreKeySignature,
    oneTimePreKeyId: oneTimePreKey?.keyId,
    oneTimePreKeyPublic: oneTimePreKey?.publicKey,
  );
}

Future<String> _sendAndDecrypt(_FakeDevice from, _FakeDevice to, String text) async {
  final encryptResult = await from.sessionManager.encrypt(
    remoteUserId: to.userId,
    remoteDeviceId: to.protocolDeviceId,
    plaintext: Uint8List.fromList(text.codeUnits),
  );
  final envelope = (encryptResult as Ok<EncryptedEnvelope>).value;

  // Round-trip through the actual wire codec, not just the in-memory
  // EncryptedEnvelope, so this also exercises ciphertext_envelope.dart.
  final wireBytes = CiphertextEnvelopeCodec.encode(envelope);
  final decodedEnvelope = CiphertextEnvelopeCodec.decode(wireBytes);

  final decryptResult = await to.sessionManager.decrypt(
    remoteUserId: from.userId,
    remoteDeviceId: from.protocolDeviceId,
    envelope: decodedEnvelope,
  );
  final plaintext = (decryptResult as Ok<Uint8List>).value;
  return String.fromCharCodes(plaintext);
}

void main() {
  late _FakeDevice alice;
  late _FakeDevice bob;

  setUp(() {
    alice = _FakeDevice('alice-user-id', '11111111-1111-1111-1111-111111111111');
    bob = _FakeDevice('bob-user-id', '22222222-2222-2222-2222-222222222222');
  });

  tearDown(() async {
    await alice.close();
    await bob.close();
  });

  test('X3DH session establishment + first message is a PreKeySignalMessage', () async {
    final provisionedBob = await bob.identityService.provisionDeviceIfNeeded();
    expect(provisionedBob.oneTimePreKeys, isNotEmpty);

    final sessionResult = await alice.sessionManager.ensureSession(
      _remoteBundleFrom(bob, provisionedBob.bundle, oneTimePreKey: provisionedBob.oneTimePreKeys.first),
    );
    expect(sessionResult.isOk, isTrue);

    final encryptResult = await alice.sessionManager.encrypt(
      remoteUserId: bob.userId,
      remoteDeviceId: bob.protocolDeviceId,
      plaintext: Uint8List.fromList('hello bob'.codeUnits),
    );
    final envelope = (encryptResult as Ok<EncryptedEnvelope>).value;
    expect(envelope.isPreKeyMessage, isTrue,
        reason: 'the first message in a fresh session must carry the X3DH handshake');
  });

  test('Bob decrypts what Alice sends, byte for byte', () async {
    final provisionedBob = await bob.identityService.provisionDeviceIfNeeded();
    await alice.sessionManager.ensureSession(
      _remoteBundleFrom(bob, provisionedBob.bundle, oneTimePreKey: provisionedBob.oneTimePreKeys.first),
    );

    final decrypted = await _sendAndDecrypt(alice, bob, 'hello bob, this is alice');
    expect(decrypted, 'hello bob, this is alice');
  });

  test('Double Ratchet keeps working across an interleaved back-and-forth', () async {
    final provisionedBob = await bob.identityService.provisionDeviceIfNeeded();
    await alice.sessionManager.ensureSession(
      _remoteBundleFrom(bob, provisionedBob.bundle, oneTimePreKey: provisionedBob.oneTimePreKeys.first),
    );

    expect(await _sendAndDecrypt(alice, bob, 'msg 1 from alice'), 'msg 1 from alice');
    expect(await _sendAndDecrypt(bob, alice, 'msg 1 from bob'), 'msg 1 from bob');
    expect(await _sendAndDecrypt(alice, bob, 'msg 2 from alice'), 'msg 2 from alice');
    expect(await _sendAndDecrypt(alice, bob, 'msg 3 from alice'), 'msg 3 from alice');
    expect(await _sendAndDecrypt(bob, alice, 'msg 2 from bob'), 'msg 2 from bob');
  });

  test('tampered ciphertext fails closed (Section 18) instead of decrypting garbage', () async {
    final provisionedBob = await bob.identityService.provisionDeviceIfNeeded();
    await alice.sessionManager.ensureSession(
      _remoteBundleFrom(bob, provisionedBob.bundle, oneTimePreKey: provisionedBob.oneTimePreKeys.first),
    );

    final encryptResult = await alice.sessionManager.encrypt(
      remoteUserId: bob.userId,
      remoteDeviceId: bob.protocolDeviceId,
      plaintext: Uint8List.fromList('do not tamper with me'.codeUnits),
    );
    final envelope = (encryptResult as Ok<EncryptedEnvelope>).value;
    final wireBytes = CiphertextEnvelopeCodec.encode(envelope);

    final tampered = Uint8List.fromList(wireBytes);
    tampered[tampered.length - 1] ^= 0xFF; // flip a bit inside the real libsignal ciphertext
    final decodedTampered = CiphertextEnvelopeCodec.decode(tampered);

    final decryptResult = await bob.sessionManager.decrypt(
      remoteUserId: alice.userId,
      remoteDeviceId: alice.protocolDeviceId,
      envelope: decodedTampered,
    );
    expect(decryptResult.isErr, isTrue);
  });

  test('a changed identity key on re-handshake is rejected, not silently trusted', () async {
    final provisionedBob = await bob.identityService.provisionDeviceIfNeeded();
    final firstBundle =
        _remoteBundleFrom(bob, provisionedBob.bundle, oneTimePreKey: provisionedBob.oneTimePreKeys.first);

    // First contact: trust-on-first-use pins Bob's identity key for this
    // address (Section 8.6).
    final firstSession = await alice.sessionManager.ensureSession(firstBundle);
    expect(firstSession.isOk, isTrue);

    // Force a *re*-handshake against the same address (e.g. a local
    // session reset) rather than relying on the already-established
    // session, which `ensureSession` would otherwise short-circuit on
    // without touching identity trust at all.
    await alice.store.deleteSession(SignalProtocolAddress(bob.userId, bob.protocolDeviceId));

    // A different "Bob" device presenting a different identity key under
    // the same address — the exact shape of an impersonation/compromise
    // scenario (Section 8.7).
    final impostor = _FakeDevice(bob.userId, bob.deviceUuid);
    final provisionedImpostor = await impostor.identityService.provisionDeviceIfNeeded();
    final impostorBundle = _remoteBundleFrom(
      impostor,
      provisionedImpostor.bundle,
      oneTimePreKey: provisionedImpostor.oneTimePreKeys.first,
    );

    final result = await alice.sessionManager.ensureSession(impostorBundle);
    expect(result.isErr, isTrue);
    expect((result as Err).failure, isA<IdentityChangedFailure>());

    await impostor.close();
  });
}
