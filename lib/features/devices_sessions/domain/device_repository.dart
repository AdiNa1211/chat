import 'package:secure_chat_app/core/crypto/models/device_prekey_bundle.dart';
import 'package:secure_chat_app/core/error/result.dart';

/// Server-facing side of device/key management (Section 5/7/8). Nothing
/// here ever sees a private key — only the public bundles
/// `IdentityKeyService` hands back.
abstract interface class DeviceRepository {
  /// Registers this device's public prekey bundle + initial one-time
  /// prekeys (Section 8.2). Returns the server-assigned device id, which
  /// becomes this device's `SignalProtocolAddress` device id for every
  /// session it establishes.
  Future<Result<String>> registerDevice({
    required String deviceName,
    required String platform,
    required DevicePrekeyBundlePublic bundle,
    required List<OneTimePreKeyPublic> oneTimePreKeys,
  });

  Future<Result<void>> uploadMoreOneTimePreKeys(
    String deviceId,
    List<OneTimePreKeyPublic> oneTimePreKeys,
  );

  Future<Result<void>> rotateSignedPreKey(String deviceId, DevicePrekeyBundlePublic bundle);

  /// Discovers which active device ids a contact has (`list_user_device_ids`,
  /// Section 7) — the prerequisite step before fetching each one's prekey
  /// bundle to start a session.
  Future<Result<List<({String deviceId, String platform})>>> listDeviceIdsFor(String userId);

  /// Fetches one remote device's public prekey bundle and atomically
  /// consumes a one-time prekey server-side (Section 7's
  /// `consume_one_time_prekey`), for X3DH (Section 8.3).
  Future<Result<RemotePreKeyBundle>> fetchRemotePreKeyBundle({
    required String remoteUserId,
    required String remoteDeviceId,
  });

  /// This device's own server-assigned id, once registered — needed to
  /// stamp `messages.sender_device_id` on every send.
  Future<String?> currentDeviceId();

  /// Records this device's current FCM registration token (Section 10 —
  /// content-free push) so the `push-notify` Edge Function knows where to
  /// deliver a silent wake-up for this device. Safe to call repeatedly;
  /// tokens rotate and the row is just overwritten.
  Future<Result<void>> updatePushToken(String deviceId, String pushToken);
}
