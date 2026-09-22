import 'package:equatable/equatable.dart';

class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserDisplayName,
    this.otherUserAvatarUrl,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final String otherUserId;
  final String otherUserDisplayName;
  final String? otherUserAvatarUrl;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;

  @override
  List<Object?> get props => [
        id,
        otherUserId,
        otherUserDisplayName,
        otherUserAvatarUrl,
        lastMessagePreview,
        lastMessageAt,
        unreadCount,
      ];
}
