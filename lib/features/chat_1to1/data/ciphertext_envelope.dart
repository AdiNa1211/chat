import 'dart:typed_data';

import 'package:secure_chat_app/core/crypto/session_manager.dart';

/// `messages.ciphertext` is an opaque `bytea` — but `SessionCipher` needs
/// to know, on the receiving side, whether a given blob is the very first
/// message in a session (a `PreKeySignalMessage`, carrying the X3DH
/// handshake) or an ordinary Double-Ratchet-encrypted `SignalMessage`
/// (Section 8.3). This tiny 1-byte prefix is that framing, chosen over a
/// separate `message_type` value so it travels atomically with the bytes
/// it describes.
class CiphertextEnvelopeCodec {
  const CiphertextEnvelopeCodec._();

  static const int _preKeyTypeByte = 0x01;
  static const int _signalTypeByte = 0x02;

  static Uint8List encode(EncryptedEnvelope envelope) {
    final out = Uint8List(envelope.bytes.length + 1);
    out[0] = envelope.isPreKeyMessage ? _preKeyTypeByte : _signalTypeByte;
    out.setRange(1, out.length, envelope.bytes);
    return out;
  }

  static EncryptedEnvelope decode(List<int> wireBytes) {
    if (wireBytes.isEmpty) {
      throw const FormatException('Empty ciphertext envelope.');
    }
    final typeByte = wireBytes[0];
    final bytes = Uint8List.fromList(wireBytes.sublist(1));
    return EncryptedEnvelope(bytes: bytes, isPreKeyMessage: typeByte == _preKeyTypeByte);
  }
}
