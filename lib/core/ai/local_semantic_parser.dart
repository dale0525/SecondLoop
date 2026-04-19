import 'package:flutter/widgets.dart';

import '../../features/actions/todo/message_action_resolver.dart';
import '../../features/actions/todo/todo_linking.dart';
import '../../features/actions/todo/todo_thread_match.dart';
import 'semantic_parse_edit_policy.dart';
import 'local_semantic_parse_result.dart';
import 'temporal/temporal_engine.dart';
import 'temporal/temporal_resolution.dart';

final class LocalSemanticParser {
  static LocalSemanticParseResult parse({
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
    if (raw.isEmpty) {
      return const LocalSemanticParseResult(
        kind: LocalSemanticParseKind.none,
        confidence: 1,
        resolver: SemanticResolver.local,
      );
    }

    final decision = MessageActionResolver.resolve(
      raw,
      locale: locale,
      nowLocal: nowLocal,
      dayEndMinutes: dayEndMinutes,
      morningMinutes: morningMinutes,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
      openTodoTargets: openTodoTargets,
      semanticMatches: semanticMatches,
    );

    switch (decision) {
      case MessageActionCreateDecision(
          :final title,
          :final status,
          :final dueAtLocal,
          :final recurrenceRule,
        ):
        return LocalSemanticParseResult(
          kind: LocalSemanticParseKind.create,
          confidence: 0.92,
          resolver: SemanticResolver.local,
          title: title,
          status: status,
          dueAtLocal: dueAtLocal,
          recurrenceRule: recurrenceRule,
          diagnostics:
              const LocalSemanticParseDiagnostics(localIntent: 'create'),
        );
      case MessageActionFollowUpDecision(
          :final todoId,
          :final newStatus,
          :final dueAtLocal,
        ):
        return LocalSemanticParseResult(
          kind: LocalSemanticParseKind.followup,
          confidence: 0.9,
          resolver: SemanticResolver.local,
          todoId: todoId,
          status: newStatus,
          dueAtLocal: dueAtLocal,
          diagnostics:
              const LocalSemanticParseDiagnostics(localIntent: 'followup'),
        );
      case MessageActionNoneDecision():
        final updateIntent = inferTodoUpdateIntent(raw);
        final dueForFollowup = TemporalEngine.resolve(
          text: raw,
          nowLocal: nowLocal,
          locale: locale,
          timezone: '',
          firstDayOfWeek: firstDayOfWeekIndex,
          mode: TemporalMode.todoFollowupDue,
          allowEnhancement: false,
          dayEndMinutes: dayEndMinutes,
        );
        final dueForCreate = TemporalEngine.resolve(
          text: raw,
          nowLocal: nowLocal,
          locale: locale,
          timezone: '',
          firstDayOfWeek: firstDayOfWeekIndex,
          mode: TemporalMode.todoDue,
          allowEnhancement: false,
          dayEndMinutes: dayEndMinutes,
        );
        final looksLikeFollowupEdit = looksLikeTodoFollowupEdit(raw);
        final hasAutomationSignal = updateIntent.isExplicit ||
            dueForFollowup.dueAtLocal != null ||
            dueForCreate.dueAtLocal != null ||
            looksLikeFollowupEdit;
        final needsEnhancement =
            !hasAutomationSignal && looksLikeTodoRelevantForSemanticParse(raw);
        final ambiguousFollowup =
            hasAutomationSignal && openTodoTargets.length > 1;
        return LocalSemanticParseResult(
          kind: LocalSemanticParseKind.none,
          confidence: ambiguousFollowup
              ? 0.45
              : needsEnhancement
                  ? 0.55
                  : hasAutomationSignal
                      ? 0.6
                      : 0.95,
          resolver: SemanticResolver.local,
          diagnostics: LocalSemanticParseDiagnostics(
            localIntent: ambiguousFollowup
                ? 'ambiguous_followup'
                : needsEnhancement
                    ? 'needs_enhancement'
                    : 'none',
          ),
        );
    }
  }
}
