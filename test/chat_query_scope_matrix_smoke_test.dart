import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/tags/tag_repository.dart';
import 'package:secondloop/features/topic_threads/topic_thread_repository.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('query scope matrix smoke: tag include/exclude + topic thread',
      (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});

    final tagRepository = _MatrixTagRepository(
      tags: <Tag>[
        _tag(
            id: 'system.tag.work',
            name: 'work',
            systemKey: 'work',
            isSystem: true),
        _tag(
            id: 'system.tag.travel',
            name: 'travel',
            systemKey: 'travel',
            isSystem: true),
      ],
      messageIdsByTagId: <String, List<String>>{
        'system.tag.work': <String>['m1', 'm2'],
        'system.tag.travel': <String>['m2', 'm3'],
      },
    );

    final topicThreadRepository = _MatrixTopicThreadRepository(
      threads: const <TopicThread>[
        TopicThread(
          id: 'thread_focus',
          conversationId: 'main_stream',
          title: 'Focus',
          createdAtMs: 1,
          updatedAtMs: 2,
        ),
      ],
      messageIdsByThreadId: const <String, List<String>>{
        'thread_focus': <String>['m2', 'm3'],
      },
    );

    await _pumpChatPage(
      tester,
      backend: _MatrixBackend(),
      tagRepository: tagRepository,
      topicThreadRepository: topicThreadRepository,
    );

    await tester.tap(find.byKey(const ValueKey('chat_tag_filter_button')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('tag_filter_chip_system.tag.work')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('chat_topic_thread_filter_button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('topic_thread_filter_thread_focus')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_bubble_m2')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_bubble_m1')), findsNothing);
    expect(find.byKey(const ValueKey('message_bubble_m3')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat_tag_filter_button')));
    await tester.pumpAndSettle();

    final travelChip =
        find.byKey(const ValueKey('tag_filter_chip_system.tag.travel'));
    await tester.tap(travelChip);
    await tester.pumpAndSettle();
    await tester.tap(travelChip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_bubble_m1')), findsNothing);
    expect(find.byKey(const ValueKey('message_bubble_m2')), findsNothing);
    expect(find.byKey(const ValueKey('message_bubble_m3')), findsNothing);
  });
}

Future<void> _pumpChatPage(
  WidgetTester tester, {
  required AppBackend backend,
  required TagRepository tagRepository,
  required TopicThreadRepository topicThreadRepository,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 2400);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: ChatPage(
              conversation: const Conversation(
                id: 'main_stream',
                title: 'Main Stream',
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
              tagRepository: tagRepository,
              topicThreadRepository: topicThreadRepository,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

Tag _tag({
  required String id,
  required String name,
  String? systemKey,
  bool isSystem = false,
}) {
  return Tag(
    id: id,
    name: name,
    systemKey: systemKey,
    isSystem: isSystem,
    color: null,
    createdAtMs: PlatformInt64Util.from(0),
    updatedAtMs: PlatformInt64Util.from(0),
  );
}

final class _MatrixBackend extends TestAppBackend {
  _MatrixBackend()
      : super(
          initialMessages: const <Message>[
            Message(
              id: 'm1',
              conversationId: 'main_stream',
              role: 'user',
              content: 'work only',
              createdAtMs: 1,
              isMemory: true,
            ),
            Message(
              id: 'm2',
              conversationId: 'main_stream',
              role: 'user',
              content: 'work and travel',
              createdAtMs: 2,
              isMemory: true,
            ),
            Message(
              id: 'm3',
              conversationId: 'main_stream',
              role: 'user',
              content: 'travel only',
              createdAtMs: 3,
              isMemory: true,
            ),
          ],
        );
}

final class _MatrixTagRepository extends TagRepository {
  _MatrixTagRepository({
    required List<Tag> tags,
    required this.messageIdsByTagId,
  }) : _tags = List<Tag>.from(tags);

  final List<Tag> _tags;
  final Map<String, List<String>> messageIdsByTagId;

  @override
  Future<List<Tag>> listTags(Uint8List key) async => List<Tag>.from(_tags);

  @override
  Future<List<String>> listMessageIdsByTagIds(
    Uint8List key,
    String conversationId,
    List<String> tagIds,
  ) async {
    final merged = <String>[];
    final seen = <String>{};
    for (final tagId in tagIds) {
      final ids = messageIdsByTagId[tagId] ?? const <String>[];
      for (final id in ids) {
        if (seen.add(id)) {
          merged.add(id);
        }
      }
    }
    return merged;
  }
}

final class _MatrixTopicThreadRepository extends TopicThreadRepository {
  _MatrixTopicThreadRepository({
    required List<TopicThread> threads,
    required Map<String, List<String>> messageIdsByThreadId,
  })  : _threads = List<TopicThread>.from(threads),
        _messageIdsByThreadId = Map<String, List<String>>.fromEntries(
          messageIdsByThreadId.entries.map(
            (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
          ),
        );

  final List<TopicThread> _threads;
  final Map<String, List<String>> _messageIdsByThreadId;

  @override
  Future<List<TopicThread>> listTopicThreads(
    Uint8List key,
    String conversationId,
  ) async {
    return _threads
        .where((thread) => thread.conversationId == conversationId)
        .toList(growable: false);
  }

  @override
  Future<List<String>> listTopicThreadMessageIds(
    Uint8List key,
    String threadId,
  ) async {
    return List<String>.from(
        _messageIdsByThreadId[threadId] ?? const <String>[]);
  }
}
