/// `libsignal_protocol_dart`'s `SignalProtocolAddress` expects a small
/// **integer** device id (the original Signal Protocol's convention: an
/// account's devices are indexed 1, 2, 3...). This app's Postgres schema
/// (Section 6) instead uses a `uuid` primary key for `devices.id`, which
/// is the right choice server-side (globally unique, no coordination
/// needed) but doesn't fit libsignal's addressing directly.
///
/// This codec derives a stable, deterministic 31-bit positive integer
/// from a device UUID, used **only** as the local libsignal session-store
/// key (`SignalProtocolAddress(userId, deviceIdInt)`) — it is never sent
/// to the server, and `messages.sender_device_id` always uses the real
/// UUID. A collision here would only ever mean two of one contact's
/// devices share local session-store bucket — a correctness bug to watch
/// for in multi-device testing (Section 18), not a security one, since
/// each session's actual key material still comes from that specific
/// device's own X3DH handshake.
int deviceUuidToProtocolDeviceId(String uuidString) {
  final hex = uuidString.replaceAll('-', '');
  // First 8 hex chars -> 32 bits; mask to keep it a positive Dart int
  // representable identically on VM and web (dart2js safe-integer range).
  final chunk = hex.substring(0, 8);
  final value = int.parse(chunk, radix: 16);
  return value & 0x7fffffff;
}
