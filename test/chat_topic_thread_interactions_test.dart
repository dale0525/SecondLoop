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
  testWidgets('starts topic focus from message action and filters messages',
      (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final repository = _FakeTopicThreadRepository();

    await _pumpChatPage(
      tester,
      backend: _TopicThreadTestBackend(),
      topicThreadRepository: repository,
    );

    expect(
      find.byKey(const ValueKey('chat_topic_thread_filter_button')),
      findsNothing,
    );

    await _openMessageTopicThreadPicker(tester, messageId: 'm1');

    expect(repository.threads.length, 1);
    final created = repository.threads.single;
    expect(created.title, 'first');
    expect(repository.messageIdsForThread(created.id), <String>['m1']);
    expect(
        find.byKey(const ValueKey('topic_thread_active_chip')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_bubble_m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_bubble_m2')), findsNothing);
  });

  testWidgets(
      'activates existing topic thread when message already belongs to it',
      (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final repository = _FakeTopicThreadRepository(
      initialThreads: <TopicThread>[
        const TopicThread(
          id: 'thread_work',
          conversationId: 'main_stream',
          title: 'Work Focus',
          createdAtMs: 1,
          updatedAtMs: 2,
        ),
      ],
      initialMessageIdsByThreadId: <String, List<String>>{
        'thread_work': <String>['m2'],
      },
    );

    await _pumpChatPage(
      tester,
      backend: _TopicThreadTestBackend(),
      topicThreadRepository: repository,
    );

    await _openMessageTopicThreadPicker(tester, messageId: 'm2');

    expect(repository.threads.length, 1);
    expect(find.byKey(const ValueKey('message_bubble_m1')), findsNothing);
    expect(find.byKey(const ValueKey('message_bubble_m2')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('topic_thread_active_chip')), findsOneWidget);
  });

  testWidgets('intersects active topic thread with include tag filter',
      (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final repository = _FakeTopicThreadRepository(
      initialThreads: <TopicThread>[
        const TopicThread(
          id: 'thread_focus',
          conversationId: 'main_stream',
          title: 'Focus',
          createdAtMs: 1,
          updatedAtMs: 2,
        ),
      ],
      initialMessageIdsByThreadId: <String, List<String>>{
        'thread_focus': <String>['m1', 'm2'],
      },
    );

    final tagRepository = _FakeTagRepository(
      tags: <Tag>[
        _tag(
            id: 'system.tag.work',
            name: 'work',
            systemKey: 'work',
            isSystem: true),
      ],
      messageIdsByTagId: <String, List<String>>{
        'system.tag.work': <String>['m2'],
      },
    );

    await _pumpChatPage(
      tester,
      backend: _TopicThreadTestBackend(),
      topicThreadRepository: repository,
      tagRepository: tagRepository,
    );

    await _openMessageTopicThreadPicker(tester, messageId: 'm1');

    await tester.tap(find.byKey(const ValueKey('chat_tag_filter_button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('tag_filter_chip_system.tag.work')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_bubble_m2')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_bubble_m1')), findsNothing);
  });
}

Future<void> _pumpChatPage(
  WidgetTester tester, {
  required AppBackend backend,
  required TopicThreadRepository topicThreadRepository,
  TagRepository tagRepository = const TagRepository(),
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

Future<void> _openMessageTopicThreadPicker(
  WidgetTester tester, {
  required String messageId,
}) async {
  await tester.longPress(find.byKey(ValueKey('message_bubble_$messageId')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('message_action_topic_thread')));
  await tester.pumpAndSettle();
}

final class _TopicThreadTestBackend extends TestAppBackend {
  _TopicThreadTestBackend()
      : super(
          initialMessages: const <Message>[
            Message(
              id: 'm1',
              conversationId: 'main_stream',
              role: 'user',
              content: 'first',
              createdAtMs: 1,
              isMemory: true,
            ),
            Message(
              id: 'm2',
              conversationId: 'main_stream',
              role: 'user',
              content: 'second',
              createdAtMs: 2,
              isMemory: true,
            ),
          ],
        );
}

final class _FakeTopicThreadRepository extends TopicThreadRepository {
  _FakeTopicThreadRepository({
    List<TopicThread> initialThreads = const <TopicThread>[],
    Map<String, List<String>> initialMessageIdsByThreadId =
        const <String, List<String>>{},
  }) {
    for (final thread in initialThreads) {
      _threadsById[thread.id] = thread;
    }
    for (final entry in initialMessageIdsByThreadId.entries) {
      _messageIdsByThreadId[entry.key] = List<String>.from(entry.value);
    }
    _sequence = initialThreads.length;
  }

  final Map<String, TopicThread> _threadsById = <String, TopicThread>{};
  final Map<String, List<String>> _messageIdsByThreadId =
      <String, List<String>>{};
  int _sequence = 0;

  List<TopicThread> get threads {
    final values = _threadsById.values.toList(growable: false)
      ..sort((a, b) {
        final byUpdated = b.updatedAtMs.compareTo(a.updatedAtMs);
        if (byUpdated != 0) return byUpdated;
        return a.id.compareTo(b.id);
      });
    return values;
  }

  List<String> messageIdsForThread(String threadId) {
    return List<String>.from(
        _messageIdsByThreadId[threadId] ?? const <String>[]);
  }

  String? threadTitle(String threadId) {
    return _threadsById[threadId]?.title;
  }

  @override
  Future<List<TopicThread>> listTopicThreads(
    Uint8List key,
    String conversationId,
  ) async {
    return threads
        .where((thread) => thread.conversationId == conversationId)
        .toList(growable: false);
  }

  @override
  Future<TopicThread> createTopicThread(
    Uint8List key,
    String conversationId, {
    String? title,
  }) async {
    _sequence += 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final thread = TopicThread(
      id: 'thread_$_sequence',
      conversationId: conversationId,
      title: title?.trim().isEmpty ?? true ? null : title!.trim(),
      createdAtMs: now,
      updatedAtMs: now,
    );
    _threadsById[thread.id] = thread;
    _messageIdsByThreadId.putIfAbsent(thread.id, () => <String>[]);
    return thread;
  }

  @override
  Future<List<String>> listTopicThreadMessageIds(
    Uint8List key,
    String threadId,
  ) async {
    return messageIdsForThread(threadId);
  }

  @override
  Future<TopicThread> updateTopicThreadTitle(
    Uint8List key,
    String threadId, {
    String? title,
  }) async {
    final existing = _threadsById[threadId];
    if (existing == null) {
      throw StateError('topic thread not found: $threadId');
    }

    final normalized = title?.trim();
    final next = TopicThread(
      id: existing.id,
      conversationId: existing.conversationId,
      title: normalized == null || normalized.isEmpty ? null : normalized,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _threadsById[threadId] = next;
    return next;
  }

  @override
  Future<bool> deleteTopicThread(Uint8List key, String threadId) async {
    final removed = _threadsById.remove(threadId);
    _messageIdsByThreadId.remove(threadId);
    return removed != null;
  }

  @override
  Future<List<String>> setTopicThreadMessageIds(
    Uint8List key,
    String threadId,
    List<String> messageIds,
  ) async {
    final dedup = <String>[];
    final seen = <String>{};
    for (final raw in messageIds) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      dedup.add(trimmed);
    }

    _messageIdsByThreadId[threadId] = dedup;
    final existing = _threadsById[threadId];
    if (existing != null) {
      _threadsById[threadId] = TopicThread(
        id: existing.id,
        conversationId: existing.conversationId,
        title: existing.title,
        createdAtMs: existing.createdAtMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }

    return dedup;
  }
}

final class _FakeTagRepository extends TagRepository {
  _FakeTagRepository({
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
    final out = <String>[];
    final seen = <String>{};
    for (final tagId in tagIds) {
      final ids = messageIdsByTagId[tagId] ?? const <String>[];
      for (final id in ids) {
        if (seen.add(id)) {
          out.add(id);
        }
      }
    }
    return out;
  }
}
