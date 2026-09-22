import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:secure_chat_app/core/di/injection_container.dart';
import 'package:secure_chat_app/core/router/app_router.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/chat_repository.dart';

/// Section 14's "New chat" screen: look up a user by username (Section
/// 13 — server-side search on the plaintext-safe `username` field only;
/// nothing E2EE-sensitive is searched server-side).
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final rows = await getIt<SupabaseClient>()
        .from('profiles')
        .select()
        .ilike('username', '%${query.trim()}%')
        .limit(20);
    setState(() {
      _results = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
  }

  Future<void> _startChat(Map<String, dynamic> profile) async {
    final result = await getIt<ChatRepository>().startOrGetDirectConversation(
      profile['id'] as String,
    );
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (conversation) {
        context.pushReplacement(
          AppRoutes.chatThread(conversation.id),
          extra: ChatThreadRouteExtra(
            otherUserId: conversation.otherUserId,
            otherUserDisplayName: conversation.otherUserDisplayName,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search by username', border: InputBorder.none),
          onChanged: _search,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final profile = _results[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(profile['display_name'] as String? ?? ''),
                  subtitle: Text('@${profile['username']}'),
                  onTap: () => _startChat(profile),
                );
              },
            ),
    );
  }
}
