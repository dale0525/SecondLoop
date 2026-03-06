import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:secondloop/features/tags/tag_filter_sheet.dart';
import 'package:secondloop/features/tags/tag_picker.dart';
import 'package:secondloop/features/tags/tag_merge_tag_selector_sheet.dart';
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
    List<TagMergeSuggestion> hiddenMergeSuggestions =
        const <TagMergeSuggestion>[],
  })  : _tags = List<Tag>.from(tags),
        _messageTags = List<Tag>.from(messageTags),
        _suggestedTags = List<String>.from(suggestedTags),
        _mergeSuggestions = List<TagMergeSuggestion>.from(mergeSuggestions),
        _hiddenMergeSuggestions =
            List<TagMergeSuggestion>.from(hiddenMergeSuggestions);

  final List<Tag> _tags;
  final List<Tag> _messageTags;
  final List<String> _suggestedTags;
  final List<TagMergeSuggestion> _mergeSuggestions;
  final List<TagMergeSuggestion> _hiddenMergeSuggestions;
  List<String>? lastSetTagIds;
  String? lastMergeSourceTagId;
  String? lastMergeTargetTagId;
  String? lastDeletedTagId;
  String? lastClearedMergeSourceTagId;
  String? lastClearedMergeTargetTagId;
  final List<String> feedbackRecords = <String>[];

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
  Future<List<TagMergeSuggestion>> listHiddenTagMergeSuggestions(
    Uint8List key, {
    int limit = 10,
  }) async {
    return List<TagMergeSuggestion>.from(_hiddenMergeSuggestions.take(limit));
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
    _hiddenMergeSuggestions.removeWhere(
      (item) =>
          item.sourceTag.id == sourceTagId && item.targetTag.id == targetTagId,
    );
    return 2;
  }

  @override
  Future<void> deleteTag(Uint8List key, String tagId) async {
    lastDeletedTagId = tagId;
    _tags.removeWhere((tag) => tag.id == tagId);
    _messageTags.removeWhere((tag) => tag.id == tagId);
    _mergeSuggestions.removeWhere(
      (suggestion) =>
          suggestion.sourceTag.id == tagId || suggestion.targetTag.id == tagId,
    );
  }

  @override
  Future<void> recordTagMergeFeedback(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
    required String reason,
    required TagMergeFeedbackAction action,
  }) async {
    feedbackRecords.add(
      '${action.wireValue}:$sourceTagId:$targetTagId:$reason',
    );
    if (action == TagMergeFeedbackAction.dismiss) {
      final index = _mergeSuggestions.indexWhere(
        (item) =>
            item.sourceTag.id == sourceTagId &&
            item.targetTag.id == targetTagId,
      );
      if (index >= 0) {
        _hiddenMergeSuggestions.add(_mergeSuggestions.removeAt(index));
      }
    }
  }

  @override
  Future<void> clearTagMergeFeedback(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
  }) async {
    lastClearedMergeSourceTagId = sourceTagId;
    lastClearedMergeTargetTagId = targetTagId;
    final index = _hiddenMergeSuggestions.indexWhere(
      (item) =>
          item.sourceTag.id == sourceTagId && item.targetTag.id == targetTagId,
    );
    if (index >= 0) {
      _mergeSuggestions.insert(0, _hiddenMergeSuggestions.removeAt(index));
    }
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
    expect(
      repository.feedbackRecords,
      contains(
        'accept:custom.weekly_review_alias:custom.weekly_review:name_compact_match',
      ),
    );
    expect(find.text('Merged 2 messages'), findsOneWidget);
  });

  testWidgets('message tag picker can dismiss and defer merge suggestion',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.en);

    final aliasA = _tag(id: 'custom.alias_a', name: 'weekly-review-a');
    final canonical = _tag(id: 'custom.canonical', name: 'Weekly Review');
    final aliasB = _tag(id: 'custom.alias_b', name: 'weekly-review-b');

    final repository = _FakeTagRepository(
      tags: <Tag>[canonical, aliasA, aliasB],
      mergeSuggestions: <TagMergeSuggestion>[
        _mergeSuggestion(
          sourceTag: aliasA,
          targetTag: canonical,
          reason: 'name_compact_match',
        ),
        _mergeSuggestion(
          sourceTag: aliasB,
          targetTag: canonical,
          reason: 'name_contains',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_picker_feedback'),
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

    await tester.tap(find.byKey(const ValueKey('open_tag_picker_feedback')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'tag_picker_merge_dismiss_custom.alias_a_custom.canonical',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Merge suggestion dismissed'), findsOneWidget);
    expect(
      repository.feedbackRecords,
      contains('dismiss:custom.alias_a:custom.canonical:name_compact_match'),
    );

    await tester.tap(
      find.byKey(
        const ValueKey(
            'tag_picker_merge_later_custom.alias_b_custom.canonical'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
            'tag_picker_merge_later_custom.alias_b_custom.canonical'),
      ),
      findsNothing,
    );
    expect(
      repository.feedbackRecords,
      contains('later:custom.alias_b:custom.canonical:name_contains'),
    );
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
    expect(
      find.text('AI confidence is low. Please confirm before applying.'),
      findsOneWidget,
    );
    expect(find.text('All tags'), findsOneWidget);
    expect(find.text('Type a tag name'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsWidgets);
    expect(find.text('Work'), findsWidgets);
    expect(find.text('ProjectX'), findsOneWidget);
  });

  testWidgets('message tag picker can manually merge tags', (tester) async {
    LocaleSettings.setLocale(AppLocale.en);

    final alias = _tag(id: 'custom.alias', name: 'weekly-review');
    final canonical = _tag(id: 'custom.canonical', name: 'Weekly Review');
    final system = _tag(
      id: 'system.tag.work',
      name: 'work',
      systemKey: 'work',
      isSystem: true,
    );

    final repository = _FakeTagRepository(
      tags: <Tag>[
        system,
        canonical,
        alias,
        _tag(id: 'custom.alpha', name: 'Alpha'),
        _tag(id: 'custom.beta', name: 'Beta'),
        _tag(id: 'custom.gamma', name: 'Gamma'),
      ],
      mergeSuggestions: <TagMergeSuggestion>[
        _mergeSuggestion(
          sourceTag: alias,
          targetTag: canonical,
          reason: 'name_compact_match',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_picker_manual_merge'),
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

    await tester
        .tap(find.byKey(const ValueKey('open_tag_picker_manual_merge')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tag_picker_manual_merge')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('manual_tag_merge_title')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('manual_tag_merge_pick_source')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('manual_tag_merge_source_selector_title')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
            'manual_tag_merge_source_selector_option_system.tag.work'),
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('manual_tag_merge_source_selector_search')),
      'weekly-',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('manual_tag_merge_source_selector_option_custom.alias'),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('manual_tag_merge_pick_target')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('manual_tag_merge_target_selector_title')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('manual_tag_merge_target_selector_option_custom.alias'),
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('manual_tag_merge_target_selector_search')),
      'weekly',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'manual_tag_merge_target_selector_option_custom.canonical',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('manual_tag_merge_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Merge tags?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag_picker_merge_confirm')));
    await tester.pumpAndSettle();

    expect(repository.lastMergeSourceTagId, 'custom.alias');
    expect(repository.lastMergeTargetTagId, 'custom.canonical');
  });

  testWidgets('manual merge sheet hosts ignored merge suggestions', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.en);

    final canonical = _tag(id: 'custom.canonical', name: 'Weekly Review');
    final hiddenSuggestions = List<TagMergeSuggestion>.generate(
      6,
      (index) => _mergeSuggestion(
        sourceTag: _tag(
          id: 'custom.hidden_$index',
          name: 'weekly-review-$index',
        ),
        targetTag: canonical,
        reason: 'name_compact_match',
      ),
    );

    final repository = _FakeTagRepository(
      tags: <Tag>[
        canonical,
        ...hiddenSuggestions.map((item) => item.sourceTag),
      ],
      hiddenMergeSuggestions: hiddenSuggestions,
    );

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_picker_restore_hidden'),
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

    await tester
        .tap(find.byKey(const ValueKey('open_tag_picker_restore_hidden')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('tag_picker_hidden_merge_title')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('tag_picker_manual_merge')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('manual_tag_merge_title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('manual_tag_merge_hidden_title')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('manual_tag_merge_hidden_expand')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('manual_tag_merge_hidden_search')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual_tag_merge_hidden_search')),
      '5',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'manual_tag_merge_accept_custom.hidden_5_custom.canonical',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'manual_tag_merge_accept_custom.hidden_1_custom.canonical',
        ),
      ),
      findsNothing,
    );

    final acceptSuggestion = find.byKey(
      const ValueKey(
        'manual_tag_merge_accept_custom.hidden_5_custom.canonical',
      ),
    );
    await tester.dragUntilVisible(
      acceptSuggestion,
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(acceptSuggestion);
    await tester.pumpAndSettle();

    expect(find.text('Merge tags?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag_picker_merge_confirm')));
    await tester.pumpAndSettle();

    expect(repository.lastMergeSourceTagId, 'custom.hidden_5');
    expect(repository.lastMergeTargetTagId, 'custom.canonical');
    expect(
      repository.feedbackRecords,
      contains('accept:custom.hidden_5:custom.canonical:name_compact_match'),
    );
    expect(repository.lastClearedMergeSourceTagId, isNull);
    expect(repository.lastClearedMergeTargetTagId, isNull);
  });

  testWidgets('tag merge selector groups selected custom and system tags',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.en);

    final selected = _tag(id: 'custom.selected', name: 'Pinned');
    final alpha = _tag(id: 'custom.alpha', name: 'Alpha');
    final beta = _tag(id: 'custom.beta', name: 'Beta');
    final system = _tag(
      id: 'system.tag.work',
      name: 'work',
      systemKey: 'work',
      isSystem: true,
    );

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_merge_selector_grouped'),
              onPressed: () async {
                await showTagMergeTagSelectorSheet(
                  context: context,
                  title: 'Pick a tag',
                  tags: <Tag>[system, beta, selected, alpha],
                  keyPrefix: 'selector_test',
                  selectedTag: selected,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('open_tag_merge_selector_grouped')));
    await tester.pumpAndSettle();

    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Custom tags'), findsOneWidget);
    expect(find.text('System tags'), findsOneWidget);

    final selectedOption =
        find.byKey(const ValueKey('selector_test_option_custom.selected'));
    final alphaOption =
        find.byKey(const ValueKey('selector_test_option_custom.alpha'));
    final systemOption =
        find.byKey(const ValueKey('selector_test_option_system.tag.work'));

    expect(
      tester.getTopLeft(selectedOption).dy,
      lessThan(tester.getTopLeft(alphaOption).dy),
    );
    expect(
      tester.getTopLeft(alphaOption).dy,
      lessThan(tester.getTopLeft(systemOption).dy),
    );
  });

  testWidgets('tag merge selector prioritizes best matches above other matches',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.en);

    final exact = _tag(id: 'custom.exact', name: 'Review');
    final prefix = _tag(id: 'custom.prefix', name: 'Review Later');
    final contains = _tag(id: 'custom.contains', name: 'Weekly Review Archive');
    final unrelated = _tag(id: 'custom.unrelated', name: 'Alpha');

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_merge_selector_search_ranked'),
              onPressed: () async {
                await showTagMergeTagSelectorSheet(
                  context: context,
                  title: 'Pick a tag',
                  tags: <Tag>[contains, unrelated, prefix, exact],
                  keyPrefix: 'selector_search_test',
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(
      const ValueKey('open_tag_merge_selector_search_ranked'),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('selector_search_test_search')),
      'review',
    );
    await tester.pumpAndSettle();

    expect(find.text('Best matches'), findsOneWidget);
    expect(find.text('Other matches'), findsOneWidget);

    final exactOption =
        find.byKey(const ValueKey('selector_search_test_option_custom.exact'));
    final prefixOption =
        find.byKey(const ValueKey('selector_search_test_option_custom.prefix'));
    final containsOption = find.byKey(
      const ValueKey('selector_search_test_option_custom.contains'),
    );

    expect(
      tester.getTopLeft(exactOption).dy,
      lessThan(tester.getTopLeft(prefixOption).dy),
    );
    expect(
      tester.getTopLeft(prefixOption).dy,
      lessThan(tester.getTopLeft(containsOption).dy),
    );
  });

  testWidgets('message tag picker only allows deleting custom tags',
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
    );

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_tag_picker_delete'),
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

    await tester.tap(find.byKey(const ValueKey('open_tag_picker_delete')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tag_picker_delete_system.tag.work')),
        findsNothing);
    expect(find.byKey(const ValueKey('tag_picker_delete_custom.1')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_picker_delete_custom.1')));
    await tester.pumpAndSettle();

    expect(find.text('Delete tag?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag_picker_delete_confirm')));
    await tester.pumpAndSettle();

    expect(repository.lastDeletedTagId, 'custom.1');
    expect(find.text('ProjectX'), findsNothing);
    expect(find.text('Work'), findsWidgets);
  });
}
