import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:secure_chat_app/core/utils/sensitive.dart';

/// Thin wrapper over `flutter_secure_storage` (iOS Keychain / Android
/// Keystore, hardware-backed where available — Section 3). This is the
/// **only** place in the app allowed to touch the platform secure-storage
/// APIs directly, so every other file depends on this narrow interface
/// instead of the plugin.
///
/// Web builds must not use this for private key material — see Section 17;
/// a separate `WebKeyStorage` (Web Crypto non-extractable `CryptoKey`,
/// JS-interop) is required there and is out of scope for this mobile-first
/// Phase 1 milestone, stubbed with a `throw UnsupportedError` so it fails
/// loudly instead of silently degrading to plaintext local storage.
class SecureKeyStorage {
  SecureKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _sqlCipherPassphraseKey = 'sqlcipher_passphrase_v1';

  /// The local database's SQLCipher passphrase. Generated once, on first
  /// run, with a CSPRNG, and never derived from anything guessable (not
  /// the user's password, not a device id).
  Future<Sensitive<String>> getOrCreateDatabasePassphrase() async {
    final existing = await _storage.read(key: _sqlCipherPassphraseKey);
    if (existing != null) return Sensitive(existing);

    final fresh = _randomBase64(32);
    await _storage.write(key: _sqlCipherPassphraseKey, value: fresh);
    return Sensitive(fresh);
  }

  Future<void> writeSecret(String key, Sensitive<String> value) {
    return _storage.write(key: key, value: value.reveal);
  }

  Future<Sensitive<String>?> readSecret(String key) async {
    final value = await _storage.read(key: key);
    return value == null ? null : Sensitive(value);
  }

  Future<void> deleteSecret(String key) => _storage.delete(key: key);

  /// Wipes every secret this app has stored — called on "log out this
  /// device" / a forced revoke (Section 10.4), so a subsequent login
  /// starts from a clean key state rather than reusing stale material.
  Future<void> wipeAll() => _storage.deleteAll();

  String _randomBase64(int byteLength) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
