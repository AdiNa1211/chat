import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:secure_chat_app/core/di/injection_container.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/chat_repository.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/cubit/chat_thread_cubit.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/widgets/message_bubble.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/widgets/message_composer.dart';
import 'package:secure_chat_app/features/media_sharing/domain/media_repository.dart';

class ChatThreadScreen extends StatelessWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserDisplayName,
  });

  final String conversationId;
  final String otherUserId;
  final String otherUserDisplayName;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatThreadCubit(
        chatRepository: getIt<ChatRepository>(),
        mediaRepository: getIt<MediaRepository>(),
        conversationId: conversationId,
        otherUserId: otherUserId,
      ),
      child: BlocListener<ChatThreadCubit, ChatThreadState>(
        listenWhen: (previous, current) =>
            current.pendingError != null && current.pendingError != previous.pendingError,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.pendingError!)));
          context.read<ChatThreadCubit>().clearError();
        },
        child: Scaffold(
          appBar: AppBar(title: Text(otherUserDisplayName)),
          body: Column(
            children: [
              Expanded(
                child: BlocBuilder<ChatThreadCubit, ChatThreadState>(
                  builder: (context, state) {
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        // Messages are stored oldest-first; render newest-first
                        // without re-sorting by indexing from the end.
                        final message = state.messages[state.messages.length - 1 - index];
                        return MessageBubble(message: message);
                      },
                    );
                  },
                ),
              ),
              BlocBuilder<ChatThreadCubit, ChatThreadState>(
                buildWhen: (a, b) => a.otherUserIsTyping != b.otherUserIsTyping,
                builder: (context, state) {
                  if (!state.otherUserIsTyping) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(alignment: Alignment.centerLeft, child: Text('typing…')),
                  );
                },
              ),
              BlocBuilder<ChatThreadCubit, ChatThreadState>(
                buildWhen: (a, b) => a.isSendingAttachment != b.isSendingAttachment,
                builder: (context, state) => MessageComposer(
                  onChanged: context.read<ChatThreadCubit>().onComposerChanged,
                  onSend: (text) => context.read<ChatThreadCubit>().sendMessage(text),
                  onAttach: () => context.read<ChatThreadCubit>().pickAndSendFile(),
                  isSendingAttachment: state.isSendingAttachment,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
