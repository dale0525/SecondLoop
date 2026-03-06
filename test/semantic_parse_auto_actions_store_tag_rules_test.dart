import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/features/tags/tag_repository.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

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

class _FakeTagRepository extends TagRepository {
  _FakeTagRepository({
    required Map<String, List<Tag>> messageTagsByMessageId,
    required Map<String, List<String>> manualTagNamesByMessageId,
  })  : _messageTagsByMessageId = messageTagsByMessageId,
        _manualTagNamesByMessageId = manualTagNamesByMessageId;

  final Map<String, List<Tag>> _messageTagsByMessageId;
  final Map<String, List<String>> _manualTagNamesByMessageId;
  final Map<String, Tag> _tagsByNormalizedName = <String, Tag>{};

  List<String>? lastSetTagIds;

  @override
  Future<List<Tag>> listMessageTags(Uint8List key, String messageId) async {
    return List<Tag>.from(_messageTagsByMessageId[messageId] ?? const <Tag>[]);
  }

  @override
  Future<List<String>> listManualMessageTagNames(
    Uint8List key,
    String messageId,
  ) async {
    return List<String>.from(
      _manualTagNamesByMessageId[messageId] ?? const <String>[],
    );
  }

  @override
  Future<Tag> upsertTag(Uint8List key, String name) async {
    final normalized = name.trim().toLowerCase();
    final existing = _tagsByNormalizedName[normalized];
    if (existing != null) return existing;

    final created = _tag(
      id: 'tag:$normalized',
      name: normalized,
      systemKey: const <String>{
        'work',
        'finance',
        'travel',
      }.contains(normalized)
          ? normalized
          : null,
      isSystem:
          const <String>{'work', 'finance', 'travel'}.contains(normalized),
    );
    _tagsByNormalizedName[normalized] = created;
    return created;
  }

  @override
  Future<List<Tag>> setMessageTags(
    Uint8List key,
    String messageId,
    List<String> tagIds,
  ) async {
    lastSetTagIds = List<String>.from(tagIds);
    return tagIds
        .map(
          (tagId) => _tagsByNormalizedName.values.firstWhere(
            (tag) => tag.id == tagId,
            orElse: () => _tag(id: tagId, name: tagId),
          ),
        )
        .toList(growable: false);
  }
}

void main() {
  const sessionKey = <int>[
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
  ];

  test('manual hash tags above limit skip semantic auto-apply', () async {
    final repository = _FakeTagRepository(
      messageTagsByMessageId: <String, List<Tag>>{
        'm1': <Tag>[
          _tag(id: 'tag:alpha', name: 'alpha'),
          _tag(id: 'tag:beta', name: 'beta'),
          _tag(id: 'tag:gamma', name: 'gamma'),
          _tag(id: 'tag:delta', name: 'delta'),
        ],
      },
      manualTagNamesByMessageId: <String, List<String>>{
        'm1': const <String>['alpha', 'beta', 'gamma', 'delta'],
      },
    );

    final store = BackendSemanticParseAutoActionsStore(
      backend: TestAppBackend(),
      sessionKey: Uint8List.fromList(sessionKey),
      tagRepository: repository,
    );

    final result = await store.applySemanticTags(
      messageId: 'm1',
      suggestedTags: const <String>['finance', 'work'],
    );

    expect(result.appliedCount, 0);
    expect(result.appliedTagIds, isEmpty);
    expect(repository.lastSetTagIds, isNull);
  });

  test('manual hash tags only allow semantic tags to fill remaining slots',
      () async {
    final repository = _FakeTagRepository(
      messageTagsByMessageId: <String, List<Tag>>{
        'm2': <Tag>[
          _tag(id: 'tag:alpha', name: 'alpha'),
          _tag(id: 'tag:picker', name: 'picker'),
        ],
      },
      manualTagNamesByMessageId: <String, List<String>>{
        'm2': const <String>['alpha'],
      },
    );

    final store = BackendSemanticParseAutoActionsStore(
      backend: TestAppBackend(),
      sessionKey: Uint8List.fromList(sessionKey),
      tagRepository: repository,
    );

    final result = await store.applySemanticTags(
      messageId: 'm2',
      suggestedTags: const <String>['finance', 'work', 'travel', 'alpha'],
    );

    expect(result.appliedCount, 2);
    expect(result.appliedTagIds, const <String>['tag:finance', 'tag:work']);
    expect(
      repository.lastSetTagIds,
      const <String>['tag:alpha', 'tag:finance', 'tag:picker', 'tag:work'],
    );
  });
}
