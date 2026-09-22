import 'package:flutter/material.dart';

import 'package:secure_chat_app/features/chat_1to1/domain/entities/message.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/widgets/attachment_bubble_content.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = message.isMine;
    final bubbleOnColor = isMine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type == MessageType.media)
              AttachmentBubbleContent(
                messageId: message.id,
                // `content` carries the filename for media messages (see
                // SupabaseMediaRepository.sendFile's local-preview write).
                fileName: message.content,
                onColor: bubbleOnColor,
              )
            else
              Text(message.content, style: TextStyle(color: bubbleOnColor)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.clientSentAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: (isMine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)
                        .withValues(alpha: 0.7),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(_statusIcon(message.deliveryStatus), size: 14, color: theme.colorScheme.onPrimary),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(MessageDeliveryStatus status) {
    switch (status) {
      case MessageDeliveryStatus.sending:
        return Icons.access_time;
      case MessageDeliveryStatus.sent:
        return Icons.check;
      case MessageDeliveryStatus.delivered:
        return Icons.done_all;
      case MessageDeliveryStatus.read:
        return Icons.done_all;
      case MessageDeliveryStatus.failed:
        return Icons.error_outline;
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
