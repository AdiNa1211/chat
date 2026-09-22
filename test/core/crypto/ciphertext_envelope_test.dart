import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secure_chat_app/core/crypto/session_manager.dart';
import 'package:secure_chat_app/features/chat_1to1/data/ciphertext_envelope.dart';

void main() {
  group('CiphertextEnvelopeCodec', () {
    test('round-trips a PreKeySignalMessage-flagged envelope', () {
      final envelope = EncryptedEnvelope(
        bytes: Uint8List.fromList([10, 20, 30, 40, 50]),
        isPreKeyMessage: true,
      );
      final wire = CiphertextEnvelopeCodec.encode(envelope);
      final decoded = CiphertextEnvelopeCodec.decode(wire);

      expect(decoded.isPreKeyMessage, isTrue);
      expect(decoded.bytes, envelope.bytes);
    });

    test('round-trips a plain SignalMessage-flagged envelope', () {
      final envelope = EncryptedEnvelope(
        bytes: Uint8List.fromList([1, 2, 3]),
        isPreKeyMessage: false,
      );
      final wire = CiphertextEnvelopeCodec.encode(envelope);
      final decoded = CiphertextEnvelopeCodec.decode(wire);

      expect(decoded.isPreKeyMessage, isFalse);
      expect(decoded.bytes, envelope.bytes);
    });

    test('the type byte is the first byte on the wire, not appended', () {
      final envelope = EncryptedEnvelope(bytes: Uint8List.fromList([99, 99]), isPreKeyMessage: true);
      final wire = CiphertextEnvelopeCodec.encode(envelope);
      expect(wire.length, envelope.bytes.length + 1);
      expect(wire[0], 0x01); // prekey type byte
      expect(wire.sublist(1), envelope.bytes);
    });

    test('decoding empty bytes throws rather than silently producing garbage', () {
      expect(() => CiphertextEnvelopeCodec.decode(const []), throwsFormatException);
    });
  });
}
