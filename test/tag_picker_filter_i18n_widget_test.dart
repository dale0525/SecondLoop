import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:secondloop/features/tags/tag_filter_sheet.dart';
import 'package:secondloop/features/tags/tag_picker.dart';
import 'package:secondloop/features/tags/tag_repository.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

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

TagMergeSuggestion _mergeSuggestion({
  required Tag sourceTag,
  required Tag targetTag,
  required String reason,
  int sourceUsageCount = 1,
  int targetUsageCount = 1,
  double score = 0.9,
}) {
  return TagMergeSuggestion(
    sourceTag: sourceTag,
    targetTag: targetTag,
    reason: reason,
    score: score,
    sourceUsageCount: PlatformInt64Util.from(sourceUsageCount),
    targetUsageCount: PlatformInt64Util.from(targetUsageCount),
  );
}

class _FakeTagRepository extends TagRepository {
  _FakeTagRepository({
    required List<Tag> tags,
    List<Tag> messageTags = const <Tag>[],
    List<String> suggestedTags = const <String>[],
    List<TagMergeSuggestion> mergeSuggestions = const <TagMergeSuggestion>[],
  })  : _tags = List<Tag>.from(tags),
        _messageTags = List<Tag>.from(messageTags),
        _suggestedTags = List<String>.from(suggestedTags),
        _mergeSuggestions = List<TagMergeSuggestion>.from(mergeSuggestions);

  final List<Tag> _tags;
  final List<Tag> _messageTags;
  final List<String> _suggestedTags;
  final List<TagMergeSuggestion> _mergeSuggestions;
  List<String>? lastSetTagIds;
  String? lastMergeSourceTagId;
  String? lastMergeTargetTagId;

  @override
  Future<List<Tag>> listTags(Uint8List key) async => List<Tag>.from(_tags);

  @override
  Future<List<Tag>> listMessageTags(Uint8List key, String messageId) async {
    return List<Tag>.from(_messageTags);
  }

  @override
  Future<List<String>> listMessageSuggestedTags(
    Uint8List key,
    String messageId,
  ) async {
    return List<String>.from(_suggestedTags);
  }

  @override
  Future<List<TagMergeSuggestion>> listTagMergeSuggestions(
    Uint8List key, {
    int limit = 10,
  }) async {
    return List<TagMergeSuggestion>.from(_mergeSuggestions.take(limit));
  }

  @override
  Future<int> mergeTags(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
  }) async {
    lastMergeSourceTagId = sourceTagId;
    lastMergeTargetTagId = targetTagId;
    _mergeSuggestions.removeWhere(
      (item) =>
          item.sourceTag.id == sourceTagId && item.targetTag.id == targetTagId,
    );
    return 2;
  }

  @override
  Future<Tag> upsertTag(Uint8List key, String name) async {
    final normalized = name.trim();
    for (final tag in _tags) {
      if (tag.systemKey == normalized || tag.name.trim() == normalized) {
        return tag;
      }
    }

    final created = _tag(
      id: 'custom.${_tags.length + 1}',
      name: normalized,
      systemKey: null,
      isSystem: false,
    );
    _tags.insert(0, created);
    return created;
  }

  @override
  Future<List<Tag>> setMessageTags(
    Uint8List key,
    String messageId,
    List<String> tagIds,
  ) async {
    lastSetTagIds = List<String>.from(tagIds);
    final selected = <Tag>[];
    for (final tag in _tags) {
      if (tagIds.contains(tag.id)) {
        selected.add(tag);
      }
    }
    return selected;
  }
}

Widget _host({
  required Widget child,
  required Locale locale,
}) {
  return wrapWithI18n(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: Center(child: child)),
    ),
  );
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

  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  testWidgets('tag filter sheet follows zh locale and localizes system tags',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);

    final repository = _FakeTagRepository(
      tags: <Tag>[
        _tag(
          id: 'system.tag.work',
          name: 'work',
          systemKey: 'work',
          isSystem: true,
        ),
        _tag(id: 'custom.1', name: 'Weekly Review'),
      ],
    );

    await tester.pumpWidget(
      _host(
        locale: const Locale('zh', 'CN'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_filter'),
              onPressed: () async {
                await showTagFilterSheet(
                  context: context,
                  sessionKey: Uint8List.fromList(sessionKey),
                  initialSelectedTagIds: const <String>{'system.tag.work'},
                  repository: repository,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_tag_filter')));
    await tester.pumpAndSettle();

    expect(find.text('按标签筛选'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('清空'), findsWidgets);
    expect(find.text('取消'), findsWidgets);
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('Weekly Review'), findsOneWidget);
  });

  testWidgets('tag filter sheet can set exclude mode by second tap',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.en);

    final repository = _FakeTagRepository(
      tags: <Tag>[
        _tag(
          id: 'system.tag.work',
          name: 'work',
          systemKey: 'work',
          isSystem: true,
        ),
        _tag(id: 'custom.1', name: 'Weekly Review'),
      ],
    );

    TagFilterSelection? selection;

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_filter_mode'),
              onPressed: () async {
                selection = await showTagFilterSheetWithModes(
                  context: context,
                  sessionKey: Uint8List.fromList(sessionKey),
                  initialIncludeTagIds: const <String>{},
                  initialExcludeTagIds: const <String>{},
                  repository: repository,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_tag_filter_mode')));
    await tester.pumpAndSettle();

    expect(find.text('Tap: Include  ·  Tap again: Exclude'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('tag_filter_chip_system.tag.work')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('tag_filter_chip_system.tag.work')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(selection, isNotNull);
    expect(selection!.includeTags, isEmpty);
    expect(selection!.excludeTags.map((tag) => tag.id),
        contains('system.tag.work'));
  });
  testWidgets('message tag picker can apply merge suggestion', (tester) async {
    LocaleSettings.setLocale(AppLocale.en);

    final weeklyReview =
        _tag(id: 'custom.weekly_review', name: 'Weekly Review');
    final weeklyReviewAlias =
        _tag(id: 'custom.weekly_review_alias', name: 'weekly-review');

    final repository = _FakeTagRepository(
      tags: <Tag>[weeklyReview, weeklyReviewAlias],
      mergeSuggestions: <TagMergeSuggestion>[
        _mergeSuggestion(
          sourceTag: weeklyReviewAlias,
          targetTag: weeklyReview,
          reason: 'name_compact_match',
          sourceUsageCount: 2,
          targetUsageCount: 3,
        ),
      ],
    );

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_picker_merge'),
              onPressed: () async {
                await showMessageTagPicker(
                  context: context,
                  sessionKey: Uint8List.fromList(sessionKey),
                  messageId: 'm1',
                  repository: repository,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_tag_picker_merge')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('tag_picker_merge_title')), findsOneWidget);
    expect(find.text('Merge suggestions'), findsOneWidget);
    expect(find.text('weekly-review -> Weekly Review'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'tag_picker_merge_apply_custom.weekly_review_alias_custom.weekly_review',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Merge tags?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag_picker_merge_confirm')));
    await tester.pumpAndSettle();

    expect(repository.lastMergeSourceTagId, 'custom.weekly_review_alias');
    expect(repository.lastMergeTargetTagId, 'custom.weekly_review');
    expect(find.text('Merged 2 messages'), findsOneWidget);
  });

  testWidgets('message tag picker follows en locale and localizes system tags',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.en);

    final repository = _FakeTagRepository(
      tags: <Tag>[
        _tag(
          id: 'system.tag.work',
          name: 'work',
          systemKey: 'work',
          isSystem: true,
        ),
        _tag(id: 'custom.1', name: 'ProjectX'),
      ],
      messageTags: <Tag>[],
      suggestedTags: <String>['work', 'ad-hoc'],
    );

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_picker'),
              onPressed: () async {
                await showMessageTagPicker(
                  context: context,
                  sessionKey: Uint8List.fromList(sessionKey),
                  messageId: 'm1',
                  repository: repository,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_tag_picker')));
    await tester.pumpAndSettle();

    expect(find.text('Manage tags'), findsOneWidget);
    expect(find.text('Suggested tags'), findsOneWidget);
    expect(find.text('All tags'), findsOneWidget);
    expect(find.text('Type a tag name'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsWidgets);
    expect(find.text('Work'), findsWidgets);
    expect(find.text('ProjectX'), findsOneWidget);
  });
}
