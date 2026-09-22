import 'package:equatable/equatable.dart';

enum MessageDeliveryStatus { sending, sent, delivered, read, failed }

enum MessageType { text, media, system }

/// Domain-layer message — always **decrypted plaintext** by the time it
/// reaches this layer (Section 4: the repository is the boundary where
/// ciphertext becomes plaintext; nothing above it ever sees a
/// `SessionCipher`).
class Message extends Equatable {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.type,
    required this.clientSentAt,
    required this.deliveryStatus,
    this.serverReceivedAt,
    this.replyToMessageId,
    this.editedAt,
    this.isMine = false,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final MessageType type;
  final DateTime clientSentAt;
  final DateTime? serverReceivedAt;
  final String? replyToMessageId;
  final DateTime? editedAt;
  final MessageDeliveryStatus deliveryStatus;
  final bool isMine;

  @override
  List<Object?> get props => [
        id,
        conversationId,
        senderId,
        content,
        type,
        clientSentAt,
        serverReceivedAt,
        replyToMessageId,
        editedAt,
        deliveryStatus,
        isMine,
      ];
}
