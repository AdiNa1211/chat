import 'dart:typed_data';

/// The **public** material this device publishes so others can start an
/// X3DH session with it (Section 8.2/8.3). Everything here is safe to
/// upload — none of it is sufficient to derive a private key.
class DevicePrekeyBundlePublic {
  const DevicePrekeyBundlePublic({
    required this.registrationId,
    required this.identityPublicKey,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
  });

  final int registrationId;
  final Uint8List identityPublicKey;
  final int signedPreKeyId;
  final Uint8List signedPreKeyPublic;
  final Uint8List signedPreKeySignature;
}

class OneTimePreKeyPublic {
  const OneTimePreKeyPublic({required this.keyId, required this.publicKey});

  final int keyId;
  final Uint8List publicKey;
}

/// What we fetch back from Supabase (`get_device_prekey_bundle` +
/// `consume_one_time_prekey`, Section 7) for a *remote* device we're about
/// to establish a session with. The one-time prekey is optional — X3DH
/// degrades gracefully (with a documented, slightly weaker guarantee) if
/// the remote device's pool was temporarily exhausted.
class RemotePreKeyBundle {
  const RemotePreKeyBundle({
    required this.remoteUserId,
    required this.remoteDeviceId,
    required this.registrationId,
    required this.identityPublicKey,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    this.oneTimePreKeyId,
    this.oneTimePreKeyPublic,
  });

  final String remoteUserId;
  final int remoteDeviceId;
  final int registrationId;
  final Uint8List identityPublicKey;
  final int signedPreKeyId;
  final Uint8List signedPreKeyPublic;
  final Uint8List signedPreKeySignature;
  final int? oneTimePreKeyId;
  final Uint8List? oneTimePreKeyPublic;
}
