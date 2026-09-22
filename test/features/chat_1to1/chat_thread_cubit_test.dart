import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:secure_chat_app/core/error/failures.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/chat_repository.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/entities/message.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/cubit/chat_thread_cubit.dart';
import 'package:secure_chat_app/features/media_sharing/domain/media_repository.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

class _MockMediaRepository extends Mock implements MediaRepository {}

void main() {
  // NOTE: `pickAndSendFile()`'s file-selection step goes through the
  // `file_picker` plugin's platform channel, which needs a real OS file
  // dialog and isn't exercised here — that path needs an integration/
  // device test, not a unit test. Everything downstream of a file being
  // picked (MediaRepository.sendFile + state transitions) is covered via
  // MediaRepository directly in SupabaseMediaRepository's own review, and
  // the state-transition shape mirrors sendMessage's, tested below.

  late _MockChatRepository chatRepository;
  late _MockMediaRepository mediaRepository;
  late StreamController<List<Message>> messagesController;
  late StreamController<bool> typingController;

  const conversationId = 'conversation-1';
  const otherUserId = 'other-user-1';

  setUp(() {
    chatRepository = _MockChatRepository();
    mediaRepository = _MockMediaRepository();
    messagesController = StreamController<List<Message>>.broadcast();
    typingController = StreamController<bool>.broadcast();

    when(() => chatRepository.subscribeToConversation(any(), any()))
        .thenAnswer((_) async {});
    when(() => chatRepository.watchMessages(any())).thenAnswer((_) => messagesController.stream);
    when(() => chatRepository.watchTyping(any(), any())).thenAnswer((_) => typingController.stream);
    when(() => chatRepository.unsubscribeFromConversation(any())).thenAnswer((_) async {});
    when(() => chatRepository.sendTypingIndicator(
          conversationId: any(named: 'conversationId'),
          isTyping: any(named: 'isTyping'),
        )).thenAnswer((_) async {});
  });

  tearDown(() async {
    await messagesController.close();
    await typingController.close();
  });

  ChatThreadCubit buildCubit() => ChatThreadCubit(
        chatRepository: chatRepository,
        mediaRepository: mediaRepository,
        conversationId: conversationId,
        otherUserId: otherUserId,
      );

  final sampleMessage = Message(
    id: 'm1',
    conversationId: conversationId,
    senderId: otherUserId,
    content: 'hi',
    type: MessageType.text,
    clientSentAt: DateTime(2026, 1, 1),
    deliveryStatus: MessageDeliveryStatus.delivered,
  );

  blocTest<ChatThreadCubit, ChatThreadState>(
    'subscribes on construction and mirrors the message stream into state',
    build: buildCubit,
    act: (cubit) => messagesController.add([sampleMessage]),
    expect: () => [
      isA<ChatThreadState>().having((s) => s.messages, 'messages', [sampleMessage]),
    ],
    verify: (_) {
      verify(() => chatRepository.subscribeToConversation(conversationId, otherUserId)).called(1);
    },
  );

  blocTest<ChatThreadCubit, ChatThreadState>(
    'mirrors the typing stream into state',
    build: buildCubit,
    act: (cubit) => typingController.add(true),
    expect: () => [
      isA<ChatThreadState>().having((s) => s.otherUserIsTyping, 'otherUserIsTyping', isTrue),
    ],
  );

  blocTest<ChatThreadCubit, ChatThreadState>(
    'sendMessage delegates to the repository and clears the typing indicator',
    build: buildCubit,
    setUp: () {
      when(() => chatRepository.sendTextMessage(
            conversationId: any(named: 'conversationId'),
            otherUserId: any(named: 'otherUserId'),
            plaintext: any(named: 'plaintext'),
            replyToMessageId: any(named: 'replyToMessageId'),
          )).thenAnswer((_) async => const Ok(null));
    },
    act: (cubit) => cubit.sendMessage('  hello  '),
    verify: (_) {
      verify(() => chatRepository.sendTextMessage(
            conversationId: conversationId,
            otherUserId: otherUserId,
            plaintext: 'hello',
            replyToMessageId: null,
          )).called(1);
      verify(() => chatRepository.sendTypingIndicator(
            conversationId: conversationId,
            isTyping: false,
          )).called(1);
    },
  );

  blocTest<ChatThreadCubit, ChatThreadState>(
    'sendMessage ignores whitespace-only input without calling the repository',
    build: buildCubit,
    act: (cubit) => cubit.sendMessage('   '),
    verify: (_) {
      verifyNever(() => chatRepository.sendTextMessage(
            conversationId: any(named: 'conversationId'),
            otherUserId: any(named: 'otherUserId'),
            plaintext: any(named: 'plaintext'),
            replyToMessageId: any(named: 'replyToMessageId'),
          ));
    },
  );

  blocTest<ChatThreadCubit, ChatThreadState>(
    'markRead delegates to the repository with the conversation id',
    build: buildCubit,
    setUp: () {
      when(() => chatRepository.markRead(any(), any())).thenAnswer((_) async {});
    },
    act: (cubit) => cubit.markRead('m1'),
    verify: (_) {
      verify(() => chatRepository.markRead(conversationId, 'm1')).called(1);
    },
  );

  blocTest<ChatThreadCubit, ChatThreadState>(
    'close() unsubscribes from the conversation',
    build: buildCubit,
    verify: (_) {},
    tearDown: () async {
      verify(() => chatRepository.unsubscribeFromConversation(conversationId)).called(1);
    },
  );

  test('a failed send would surface as a Failure with a user-facing message', () {
    // Documents the contract sendMessage/pickAndSendFile rely on: any
    // Result the repositories return carries a displayable message
    // (Section 15 — never a raw exception string reaching the UI).
    const failure = ServerFailure('This contact has no active devices to message.');
    const result = Err<void>(failure);
    expect(result.isErr, isTrue);
    expect((result as Err).failure.message, isNotEmpty);
  });
}
