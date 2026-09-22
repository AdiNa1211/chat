import 'package:flutter_test/flutter_test.dart';

import 'package:secure_chat_app/core/crypto/device_id_codec.dart';

void main() {
  group('deviceUuidToProtocolDeviceId', () {
    test('is deterministic for the same UUID', () {
      const uuid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      expect(deviceUuidToProtocolDeviceId(uuid), deviceUuidToProtocolDeviceId(uuid));
    });

    test('always returns a positive int (masked to 31 bits)', () {
      // Chosen so the raw 32-bit parse would be negative if not masked.
      const uuid = 'ffffffff-0000-0000-0000-000000000000';
      final result = deviceUuidToProtocolDeviceId(uuid);
      expect(result, greaterThanOrEqualTo(0));
      expect(result, lessThanOrEqualTo(0x7fffffff));
    });

    test('different UUIDs (usually) map to different ids', () {
      const uuidA = '11111111-0000-0000-0000-000000000000';
      const uuidB = '22222222-0000-0000-0000-000000000000';
      expect(deviceUuidToProtocolDeviceId(uuidA), isNot(deviceUuidToProtocolDeviceId(uuidB)));
    });

    test('only the first 8 hex chars matter — documents the collision surface', () {
      const uuidA = '12345678-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      const uuidB = '12345678-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      // Same first 8 hex chars => same protocol device id. This is the
      // exact tradeoff documented on the function: acceptable because a
      // collision only merges local session-store buckets, never key
      // material (see the doc comment on deviceUuidToProtocolDeviceId).
      expect(deviceUuidToProtocolDeviceId(uuidA), deviceUuidToProtocolDeviceId(uuidB));
    });
  });
}
