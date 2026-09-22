import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:secure_chat_app/features/chat_1to1/domain/chat_repository.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/entities/conversation.dart';

class ChatListCubit extends Cubit<List<Conversation>> {
  ChatListCubit(this._chatRepository) : super(const []) {
    _sub = _chatRepository.watchConversations().listen(emit);
  }

  final ChatRepository _chatRepository;
  late final StreamSubscription<List<Conversation>> _sub;

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
