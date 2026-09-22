import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:secure_chat_app/core/crypto/device_id_codec.dart';
import 'package:secure_chat_app/core/crypto/models/device_prekey_bundle.dart';
import 'package:secure_chat_app/core/crypto/secure_key_storage.dart';
import 'package:secure_chat_app/core/error/failures.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';
import 'package:secure_chat_app/core/utils/sensitive.dart';
import 'package:secure_chat_app/features/devices_sessions/domain/device_repository.dart';

class SupabaseDeviceRepository implements DeviceRepository {
  SupabaseDeviceRepository(this._client, this._secureStorage);

  final SupabaseClient _client;
  final SecureKeyStorage _secureStorage;
  final _log = AppLogger.forName('SupabaseDeviceRepository');

  static const _deviceIdSecureKey = 'own_device_id_v1';
  static const _uuid = Uuid();

  @override
  Future<String?> currentDeviceId() async {
    final secret = await _secureStorage.readSecret(_deviceIdSecureKey);
    return secret?.reveal;
  }

  @override
  Future<Result<String>> registerDevice({
    required String deviceName,
    required String platform,
    required DevicePrekeyBundlePublic bundle,
    required List<OneTimePreKeyPublic> oneTimePreKeys,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return const Err(AuthFailure('Not signed in.'));

      final deviceId = _uuid.v4();
      await _client.from('devices').insert({
        'id': deviceId,
        'user_id': userId,
        'device_name': deviceName,
        'platform': platform,
        'identity_public_key': bundle.identityPublicKey,
        'signed_prekey': bundle.signedPreKeyPublic,
        'signed_prekey_signature': bundle.signedPreKeySignature,
        'registration_id': bundle.registrationId,
      });

      if (oneTimePreKeys.isNotEmpty) {
        await _client.from('one_time_prekeys').insert([
          for (final k in oneTimePreKeys)
            {'device_id': deviceId, 'key_id': k.keyId, 'public_key': k.publicKey},
        ]);
      }

      await _secureStorage.writeSecret(_deviceIdSecureKey, Sensitive(deviceId));
      return Ok(deviceId);
    } on PostgrestException catch (e, st) {
      _log.error('registerDevice failed', e, st);
      return Err(ServerFailure(e.message));
    } catch (e, st) {
      _log.error('registerDevice failed', e, st);
      return const Err(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> uploadMoreOneTimePreKeys(
    String deviceId,
    List<OneTimePreKeyPublic> oneTimePreKeys,
  ) async {
    try {
      if (oneTimePreKeys.isEmpty) return const Ok(null);
      await _client.from('one_time_prekeys').insert([
        for (final k in oneTimePreKeys)
          {'device_id': deviceId, 'key_id': k.keyId, 'public_key': k.publicKey},
      ]);
      return const Ok(null);
    } on PostgrestException catch (e) {
      return Err(ServerFailure(e.message));
    }
  }

  @override
  Future<Result<void>> rotateSignedPreKey(String deviceId, DevicePrekeyBundlePublic bundle) async {
    try {
      await _client.from('devices').update({
        'signed_prekey': bundle.signedPreKeyPublic,
        'signed_prekey_signature': bundle.signedPreKeySignature,
      }).eq('id', deviceId);
      return const Ok(null);
    } on PostgrestException catch (e) {
      return Err(ServerFailure(e.message));
    }
  }

  @override
  Future<Result<List<({String deviceId, String platform})>>> listDeviceIdsFor(
    String userId,
  ) async {
    try {
      final rows = await _client.rpc('list_user_device_ids', params: {'target_user_id': userId});
      final list = (rows as List)
          .map((r) => (deviceId: r['device_id'] as String, platform: r['platform'] as String))
          .toList();
      return Ok(list);
    } on PostgrestException catch (e) {
      return Err(ServerFailure(e.message));
    }
  }

  @override
  Future<Result<RemotePreKeyBundle>> fetchRemotePreKeyBundle({
    required String remoteUserId,
    required String remoteDeviceId,
  }) async {
    try {
      final bundleRows = await _client.rpc(
        'get_device_prekey_bundle',
        params: {'target_device_id': remoteDeviceId},
      );
      final bundleRow = (bundleRows as List).isEmpty ? null : bundleRows.first;
      if (bundleRow == null) {
        return const Err(ServerFailure('That device is no longer available.'));
      }

      // Atomically consumes one one-time prekey server-side (Section 7) —
      // may come back empty if the pool was exhausted; X3DH still
      // proceeds without one, just with a slightly weaker guarantee
      // (documented in Section 8.5).
      final otpRows = await _client.rpc(
        'consume_one_time_prekey',
        params: {'target_device_id': remoteDeviceId},
      );
      final otpRow = (otpRows as List).isEmpty ? null : otpRows.first;

      return Ok(
        RemotePreKeyBundle(
          remoteUserId: remoteUserId,
          // See core/crypto/device_id_codec.dart — libsignal wants a small
          // int; the server's real device id (used for
          // messages.sender_device_id) stays the UUID everywhere else.
          remoteDeviceId: deviceUuidToProtocolDeviceId(bundleRow['device_id'] as String),
          registrationId: bundleRow['registration_id'] as int,
          identityPublicKey: _decodeBytea(bundleRow['identity_public_key']),
          // The signed prekey's own numeric id is only meaningful for the
          // *serving* device's local bookkeeping (Section 8.5's rotation);
          // the recipient just needs the public key + signature to verify
          // and use it, so this is fine to leave as a placeholder locally.
          signedPreKeyId: 0,
          signedPreKeyPublic: _decodeBytea(bundleRow['signed_prekey']),
          signedPreKeySignature: _decodeBytea(bundleRow['signed_prekey_signature']),
          oneTimePreKeyId: otpRow == null ? null : otpRow['key_id'] as int,
          oneTimePreKeyPublic: otpRow == null ? null : _decodeBytea(otpRow['public_key']),
        ),
      );
    } on PostgrestException catch (e, st) {
      _log.error('fetchRemotePreKeyBundle failed', e, st);
      return Err(ServerFailure(e.message));
    }
  }

  @override
  Future<Result<void>> updatePushToken(String deviceId, String pushToken) async {
    try {
      await _client.from('devices').update({'push_token': pushToken}).eq('id', deviceId);
      return const Ok(null);
    } on PostgrestException catch (e, st) {
      _log.warning('updatePushToken failed', e, st);
      return Err(ServerFailure(e.message));
    }
  }

  /// PostgREST returns `bytea` columns as base64 strings over JSON, not raw
  /// bytes — matches the same decode already done for `messages.ciphertext`
  /// in `chat_repository_impl.dart`.
  Uint8List _decodeBytea(dynamic value) {
    if (value is String) return base64Decode(value);
    return Uint8List.fromList(value as List<int>);
  }
}
