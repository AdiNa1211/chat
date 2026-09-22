import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:secure_chat_app/core/router/app_router.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_event.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/entities/conversation.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/cubit/chat_list_cubit.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthBloc>().add(const SignOutRequested()),
          ),
        ],
      ),
      body: BlocBuilder<ChatListCubit, List<Conversation>>(
        builder: (context, conversations) {
          if (conversations.isEmpty) {
            return const Center(child: Text('No conversations yet. Start one below.'));
          }
          return ListView.separated(
            itemCount: conversations.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final convo = conversations[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      convo.otherUserAvatarUrl != null ? NetworkImage(convo.otherUserAvatarUrl!) : null,
                  child: convo.otherUserAvatarUrl == null ? const Icon(Icons.person) : null,
                ),
                title: Text(convo.otherUserDisplayName),
                subtitle: Text(
                  convo.lastMessagePreview ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => context.push(
                  AppRoutes.chatThread(convo.id),
                  extra: ChatThreadRouteExtra(
                    otherUserId: convo.otherUserId,
                    otherUserDisplayName: convo.otherUserDisplayName,
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.newChat),
        child: const Icon(Icons.chat),
      ),
    );
  }
}
