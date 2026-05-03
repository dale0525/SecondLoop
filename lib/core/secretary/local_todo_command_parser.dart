import 'package:flutter/widgets.dart';

import '../../features/actions/todo/todo_linking.dart';
import '../../features/actions/todo/todo_thread_match.dart';
import '../ai/temporal/temporal_engine.dart';
import '../ai/temporal/temporal_resolution.dart';
import 'todo_command_models.dart';

final class LocalTodoCommandParseResult {
  const LocalTodoCommandParseResult({
    this.command,
    this.diagnostic = 'none',
    this.needsEnhancement = false,
    this.isAmbiguous = false,
  });

  final SecretaryTodoCommand? command;
  final String diagnostic;
  final bool needsEnhancement;
  final bool isAmbiguous;
}

final class LocalTodoCommandParser {
  const LocalTodoCommandParser._();

  static LocalTodoCommandParseResult parse({
    required String messageId,
    required String text,
    required DateTime nowLocal,
    required Locale locale,
    required List<TodoLinkTarget> openTodoTargets,
    int dayEndMinutes = 21 * 60,
    int? morningMinutes,
    int firstDayOfWeekIndex = 1,
    List<TodoThreadMatch> semanticMatches = const <TodoThreadMatch>[],
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return const LocalTodoCommandParseResult();

    final intent = _detectIntent(raw);
    if (intent == SecretaryTodoCommandKind.none) {
      return const LocalTodoCommandParseResult();
    }

    final target = _resolveTarget(
      raw,
      openTodoTargets,
      semanticMatches: semanticMatches,
    );
    if (target.isAmbiguous) {
      return const LocalTodoCommandParseResult(
        diagnostic: 'ambiguous_todo_command',
        needsEnhancement: true,
        isAmbiguous: true,
      );
    }
    final targetTodo = target.target;
    if (targetTodo == null && intent != SecretaryTodoCommandKind.batchUpdate) {
      return const LocalTodoCommandParseResult(
        diagnostic: 'todo_command_needs_target',
        needsEnhancement: true,
      );
    }

    switch (intent) {
      case SecretaryTodoCommandKind.updateTitle:
        final newTitle = _extractNewTitle(raw);
        if (newTitle == null) {
          return const LocalTodoCommandParseResult(
            diagnostic: 'todo_command_needs_enhancement',
            needsEnhancement: true,
          );
        }
        return LocalTodoCommandParseResult(
          command: _command(
            messageId: messageId,
            kind: intent,
            target: targetTodo,
            confidence: 0.9,
            rawText: raw,
            newTitle: newTitle,
          ),
          diagnostic: 'update_title',
        );
      case SecretaryTodoCommandKind.reschedule:
        final due = TemporalEngine.resolve(
          text: raw,
          nowLocal: nowLocal,
          locale: locale,
          timezone: '',
          firstDayOfWeek: firstDayOfWeekIndex,
          mode: TemporalMode.todoFollowupDue,
          allowEnhancement: true,
          dayEndMinutes: dayEndMinutes,
          morningMinutes: morningMinutes,
        );
        if (due.dueAtLocal == null) {
          return LocalTodoCommandParseResult(
            diagnostic: 'todo_command_needs_enhancement',
            needsEnhancement: due.metadata.needsEnhancement,
          );
        }
        return LocalTodoCommandParseResult(
          command: _command(
            messageId: messageId,
            kind: intent,
            target: targetTodo,
            confidence: 0.92,
            rawText: raw,
            dueAtMs: due.dueAtLocal!.millisecondsSinceEpoch,
          ),
          diagnostic: 'reschedule',
        );
      case SecretaryTodoCommandKind.setStatus:
        final status = _statusFor(raw);
        if (status == null) {
          return const LocalTodoCommandParseResult(
            diagnostic: 'todo_command_needs_enhancement',
            needsEnhancement: true,
          );
        }
        return LocalTodoCommandParseResult(
          command: _command(
            messageId: messageId,
            kind: intent,
            target: targetTodo,
            confidence: 0.9,
            rawText: raw,
            newStatus: status,
          ),
          diagnostic: 'set_status',
        );
      case SecretaryTodoCommandKind.dismiss:
        return LocalTodoCommandParseResult(
          command: _command(
            messageId: messageId,
            kind: intent,
            target: targetTodo,
            confidence: 0.9,
            rawText: raw,
          ),
          diagnostic: 'dismiss',
        );
      case SecretaryTodoCommandKind.reprioritize:
        final nudges = _priorityNudgesFor(raw);
        return LocalTodoCommandParseResult(
          command: _command(
            messageId: messageId,
            kind: intent,
            target: targetTodo,
            confidence: 0.91,
            rawText: raw,
            manualImportanceNudgeScore: nudges.importance,
            manualUrgencyNudgeScore: nudges.urgency,
          ),
          diagnostic: 'reprioritize',
        );
      case SecretaryTodoCommandKind.batchUpdate:
        return const LocalTodoCommandParseResult(
          diagnostic: 'todo_command_needs_enhancement',
          needsEnhancement: true,
        );
      case SecretaryTodoCommandKind.create:
      case SecretaryTodoCommandKind.none:
        return const LocalTodoCommandParseResult();
    }
  }

  static SecretaryTodoCommand _command({
    required String messageId,
    required SecretaryTodoCommandKind kind,
    required TodoLinkTarget? target,
    required double confidence,
    required String rawText,
    String? newTitle,
    String? newStatus,
    int? dueAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) {
    return SecretaryTodoCommand(
      id: 'todo-command-$messageId',
      kind: kind,
      route: SecretaryTodoCommandRoute.local,
      confidence: confidence,
      sourceMessageId: messageId,
      targetTodoId: target?.id,
      targetTitle: target?.title,
      newTitle: newTitle,
      newStatus: newStatus,
      dueAtMs: dueAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore,
      rawText: rawText,
    );
  }

  static SecretaryTodoCommandKind _detectIntent(String raw) {
    final lower = raw.toLowerCase();
    if (_containsAny(lower, const [
      '优先级',
      '調高',
      '调高',
      '调低',
      '重要',
      '紧急',
      'more important',
      'less important',
      'more urgent',
      'less urgent',
      'priority',
    ])) {
      return SecretaryTodoCommandKind.reprioritize;
    }
    if (_containsAny(lower, const [
      '删除',
      '删掉',
      '取消',
      '不做了',
      'delete ',
      'delete',
      'remove ',
      'cancel ',
      'dismiss ',
    ])) {
      return SecretaryTodoCommandKind.dismiss;
    }
    if (_containsAny(lower, const [
      '改成',
      '改为',
      '改名',
      'rename ',
      'rename',
      'change title',
      'change name',
    ])) {
      return SecretaryTodoCommandKind.updateTitle;
    }
    if (_containsAny(lower, const [
      '改到',
      '挪到',
      '延期',
      '推迟',
      'reschedule',
      'move ',
      'postpone',
    ])) {
      return SecretaryTodoCommandKind.reschedule;
    }
    if (_containsAny(lower, const [
      '标记完成',
      '标为完成',
      '完成',
      '开始',
      '进行中',
      'mark ',
      'complete',
      'done',
      'start ',
    ])) {
      return SecretaryTodoCommandKind.setStatus;
    }
    if (_containsAny(lower, const [
      '所有',
      '全部',
      'all overdue',
      'all tasks',
    ])) {
      return SecretaryTodoCommandKind.batchUpdate;
    }
    return SecretaryTodoCommandKind.none;
  }

  static String? _extractNewTitle(String raw) {
    for (final marker in const ['改成', '改为', '改名为']) {
      final index = raw.indexOf(marker);
      if (index < 0) continue;
      final title = raw.substring(index + marker.length).trim();
      return title.isEmpty ? null : title;
    }

    final lower = raw.toLowerCase();
    final renameIndex = lower.indexOf('rename ');
    if (renameIndex >= 0) {
      final toIndex = lower.indexOf(' to ', renameIndex);
      if (toIndex >= 0) {
        final title = raw.substring(toIndex + 4).trim();
        return title.isEmpty ? null : title;
      }
    }

    final changeToIndex = lower.indexOf('change ');
    if (changeToIndex >= 0) {
      final toIndex = lower.indexOf(' to ', changeToIndex);
      if (toIndex >= 0) {
        final title = raw.substring(toIndex + 4).trim();
        return title.isEmpty ? null : title;
      }
    }
    return null;
  }

  static String? _statusFor(String raw) {
    final lower = raw.toLowerCase();
    if (_containsAny(lower, const ['完成', 'done', 'complete', 'completed'])) {
      return 'done';
    }
    if (_containsAny(lower, const ['开始', '进行中', 'start ', 'in progress'])) {
      return 'in_progress';
    }
    return null;
  }

  static ({int importance, int urgency}) _priorityNudgesFor(String raw) {
    final lower = raw.toLowerCase();
    final down = _containsAny(lower, const [
      '调低',
      '降低',
      'less important',
      'less urgent',
      'lower priority',
    ]);
    final value = down ? -1 : 1;
    if (_containsAny(lower, const ['urgent', '紧急'])) {
      return (importance: 0, urgency: value);
    }
    if (_containsAny(lower, const ['priority', '优先级'])) {
      return (importance: value, urgency: value);
    }
    return (importance: value, urgency: 0);
  }

  static _ResolvedTodoTarget _resolveTarget(
    String raw,
    List<TodoLinkTarget> targets, {
    required List<TodoThreadMatch> semanticMatches,
  }) {
    final openTargets = targets
        .where(
            (target) => target.status != 'done' && target.status != 'dismissed')
        .toList(growable: false);
    if (openTargets.isEmpty) return const _ResolvedTodoTarget();

    final normalizedRaw = _normalize(raw);
    final explicitMatches = [
      for (final target in openTargets)
        if (_containsTitle(normalizedRaw, target.title)) target,
    ];
    final explicitIds = explicitMatches.map((target) => target.id).toSet();
    if (explicitIds.length == 1) {
      return _ResolvedTodoTarget(target: explicitMatches.first);
    }
    if (explicitIds.length > 1) {
      return const _ResolvedTodoTarget(isAmbiguous: true);
    }

    if (_isDeictic(raw) && openTargets.length == 1) {
      return _ResolvedTodoTarget(target: openTargets.single);
    }

    final sortedMatches = [...semanticMatches]
      ..sort((a, b) => a.distance.compareTo(b.distance));
    if (sortedMatches.isNotEmpty && sortedMatches.first.distance <= 0.35) {
      final secondDistance = sortedMatches.length > 1
          ? sortedMatches[1].distance
          : double.infinity;
      if (secondDistance - sortedMatches.first.distance >= 0.12) {
        final id = sortedMatches.first.todoId;
        for (final target in openTargets) {
          if (target.id == id) return _ResolvedTodoTarget(target: target);
        }
      }
      return const _ResolvedTodoTarget(isAmbiguous: true);
    }

    return const _ResolvedTodoTarget();
  }

  static bool _containsTitle(String normalizedRaw, String title) {
    final normalizedTitle = _normalize(title);
    if (normalizedTitle.isEmpty) return false;
    return normalizedRaw.contains(normalizedTitle);
  }

  static bool _isDeictic(String raw) {
    final lower = raw.toLowerCase();
    return isDeicticOnlyTodoTitle(lower) ||
        _containsAny(lower, const [
          '这个',
          '這個',
          '这个待办',
          '這個待辦',
          '刚才那个',
          '剛才那個',
          'this',
          'that',
          'it',
        ]);
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _containsAny(String haystack, List<String> needles) {
    return needles
        .any((needle) => needle.isNotEmpty && haystack.contains(needle));
  }
}

final class _ResolvedTodoTarget {
  const _ResolvedTodoTarget({this.target, this.isAmbiguous = false});

  final TodoLinkTarget? target;
  final bool isAmbiguous;
}
