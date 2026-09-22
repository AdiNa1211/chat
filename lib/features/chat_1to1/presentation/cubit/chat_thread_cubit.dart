import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';

import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/chat_repository.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/entities/message.dart';
import 'package:secure_chat_app/features/media_sharing/domain/media_repository.dart';

class ChatThreadState extends Equatable {
  const ChatThreadState({
    this.messages = const [],
    this.otherUserIsTyping = false,
    this.isSendingAttachment = false,
    this.pendingError,
  });

  final List<Message> messages;
  final bool otherUserIsTyping;
  final bool isSendingAttachment;

  /// One-shot notice for a `BlocListener` to show and then clear via
  /// [ChatThreadCubit.clearError] — not persistent UI state.
  final String? pendingError;

  ChatThreadState copyWith({
    List<Message>? messages,
    bool? otherUserIsTyping,
    bool? isSendingAttachment,
  }) {
    return ChatThreadState(
      messages: messages ?? this.messages,
      otherUserIsTyping: otherUserIsTyping ?? this.otherUserIsTyping,
      isSendingAttachment: isSendingAttachment ?? this.isSendingAttachment,
      pendingError: pendingError,
    );
  }

  @override
  List<Object?> get props => [messages, otherUserIsTyping, isSendingAttachment, pendingError];
}

class ChatThreadCubit extends Cubit<ChatThreadState> {
  ChatThreadCubit({
    required ChatRepository chatRepository,
    required MediaRepository mediaRepository,
    required this.conversationId,
    required this.otherUserId,
  })  : _chatRepository = chatRepository,
        _mediaRepository = mediaRepository,
        super(const ChatThreadState()) {
    _chatRepository.subscribeToConversation(conversationId, otherUserId);
    _messagesSub = _chatRepository.watchMessages(conversationId).listen((messages) {
      emit(state.copyWith(messages: messages));
    });
    _typingSub = _chatRepository.watchTyping(conversationId, otherUserId).listen((isTyping) {
      emit(state.copyWith(otherUserIsTyping: isTyping));
    });
  }

  final ChatRepository _chatRepository;
  final MediaRepository _mediaRepository;
  final String conversationId;
  final String otherUserId;
  late final StreamSubscription<List<Message>> _messagesSub;
  late final StreamSubscription<bool> _typingSub;
  Timer? _typingDebounce;

  /// Clears the one-shot [ChatThreadState.pendingError] once the UI has
  /// shown it — call from the `BlocListener` right after displaying it.
  void clearError() => emit(ChatThreadState(
        messages: state.messages,
        otherUserIsTyping: state.otherUserIsTyping,
        isSendingAttachment: state.isSendingAttachment,
      ));

  Future<void> sendMessage(String text, {String? replyToMessageId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _chatRepository.sendTextMessage(
      conversationId: conversationId,
      otherUserId: otherUserId,
      plaintext: trimmed,
      replyToMessageId: replyToMessageId,
    );
    await _chatRepository.sendTypingIndicator(conversationId: conversationId, isTyping: false);
  }

  void onComposerChanged(String text) {
    _chatRepository.sendTypingIndicator(conversationId: conversationId, isTyping: text.isNotEmpty);
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 3), () {
      _chatRepository.sendTypingIndicator(conversationId: conversationId, isTyping: false);
    });
  }

  Future<void> markRead(String messageId) => _chatRepository.markRead(conversationId, messageId);

  /// Picks a file and sends it encrypted (Section 9.1). Mobile/desktop
  /// only in Phase 1 — see [FileCryptoService]'s dart:io note; Web support
  /// is a Phase 2 item.
  Future<void> pickAndSendFile() async {
    if (kIsWeb) {
      emit(ChatThreadState(
        messages: state.messages,
        otherUserIsTyping: state.otherUserIsTyping,
        isSendingAttachment: state.isSendingAttachment,
        pendingError: 'File sharing on Web is coming in a later update.',
      ));
      return;
    }
    if (state.isSendingAttachment) return;

    final picked = await FilePicker.platform.pickFiles(withReadStream: false);
    final pickedFile = picked?.files.single;
    if (pickedFile?.path == null) return;

    final path = pickedFile!.path!;
    final fileName = pickedFile.name;
    final mimeType = lookupMimeType(path) ?? 'application/octet-stream';

    emit(state.copyWith(isSendingAttachment: true));
    final result = await _mediaRepository.sendFile(
      conversationId: conversationId,
      otherUserId: otherUserId,
      file: File(path),
      fileName: fileName,
      mimeType: mimeType,
    );

    emit(ChatThreadState(
      messages: state.messages,
      otherUserIsTyping: state.otherUserIsTyping,
      isSendingAttachment: false,
      pendingError: switch (result) { Err(:final failure) => failure.message, Ok() => null },
    ));
  }

  @override
  Future<void> close() async {
    _typingDebounce?.cancel();
    await _messagesSub.cancel();
    await _typingSub.cancel();
    await _chatRepository.unsubscribeFromConversation(conversationId);
    return super.close();
  }
}
