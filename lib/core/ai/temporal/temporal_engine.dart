import 'package:flutter/widgets.dart';

import 'temporal_locale_plugin.dart';
import 'temporal_resolution.dart';
import 'temporal_rule_resolver.dart';

final class TemporalEngine {
  static TemporalResolution resolve({
    required String text,
    required DateTime nowLocal,
    required Locale locale,
    required String timezone,
    required int firstDayOfWeek,
    required TemporalMode mode,
    required bool allowEnhancement,
    int dayEndMinutes = 21 * 60,
  }) {
    final normalizedText = TemporalRuleResolver.normalize(text);
    if (normalizedText.isEmpty) {
      return TemporalResolution(
        mode: mode,
        confidence: 0,
        resolver: TemporalResolver.none,
        semantics: TemporalSemantics.none,
        metadata: const TemporalMetadata(normalizedExpression: ''),
      );
    }

    final request = TemporalPluginRequest(
      text: text,
      normalizedText: normalizedText,
      nowLocal: nowLocal,
      locale: locale,
      timezone: timezone,
      firstDayOfWeek: firstDayOfWeek,
    );

    final candidate = TemporalRuleResolver.resolve(
          text: text,
          normalizedText: normalizedText,
          nowLocal: nowLocal,
          locale: locale,
          firstDayOfWeek: firstDayOfWeek,
        ) ??
        TemporalLocalePluginRegistry.resolve(request);
    final needsEnhancementHint =
        TemporalLocalePluginRegistry.needsEnhancement(request);

    if (candidate == null ||
        candidate.isAmbiguous ||
        candidate.confidence < 0.6) {
      return TemporalResolution(
        mode: mode,
        confidence: candidate?.confidence ?? 0,
        resolver: TemporalResolver.none,
        semantics: TemporalSemantics.none,
        metadata: (candidate?.metadata ?? const TemporalMetadata()).copyWith(
          normalizedExpression: normalizedText,
          needsEnhancement:
              candidate?.metadata.needsEnhancement ?? needsEnhancementHint,
        ),
      );
    }

    return _projectCandidate(
      candidate,
      mode: mode,
      nowLocal: nowLocal,
      dayEndMinutes: dayEndMinutes,
      normalizedText: normalizedText,
    );
  }

  static TemporalResolution _projectCandidate(
    TemporalCandidate candidate, {
    required TemporalMode mode,
    required DateTime nowLocal,
    required int dayEndMinutes,
    required String normalizedText,
  }) {
    switch (mode) {
      case TemporalMode.retrievalWindow:
        final specialWindow = _projectBoundaryExpressionWindow(
          candidate,
          mode: mode,
          nowLocal: nowLocal,
          normalizedText: normalizedText,
        );
        if (specialWindow != null) {
          return specialWindow;
        }
        if (candidate.startLocal != null && candidate.endLocal != null) {
          return TemporalResolution(
            mode: mode,
            confidence: candidate.confidence,
            resolver: candidate.resolver,
            semantics: candidate.semantics,
            startLocal: candidate.startLocal,
            endLocal: candidate.endLocal,
            metadata: candidate.metadata.copyWith(
              normalizedExpression:
                  candidate.metadata.normalizedExpression ?? normalizedText,
            ),
          );
        }
        final point = candidate.pointLocal;
        if (point == null) {
          return _none(mode, normalizedText, candidate.metadata);
        }
        final start = DateTime(point.year, point.month, point.day);
        final end = start.add(const Duration(days: 1));
        final todayStart =
            DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
        final semantics = !end.isAfter(todayStart)
            ? TemporalSemantics.rangePast
            : start.isAfter(todayStart)
                ? TemporalSemantics.rangeFuture
                : TemporalSemantics.rangeBoth;
        return TemporalResolution(
          mode: mode,
          confidence: candidate.confidence,
          resolver: candidate.resolver,
          semantics: semantics,
          startLocal: start,
          endLocal: end,
          metadata: candidate.metadata.copyWith(
            normalizedExpression:
                candidate.metadata.normalizedExpression ?? normalizedText,
          ),
        );
      case TemporalMode.todoDue:
      case TemporalMode.todoFollowupDue:
        if (candidate.pointLocal == null) {
          return _none(mode, normalizedText, candidate.metadata);
        }
        final point = candidate.pointLocal!;
        final dueAtLocal = candidate.hasExplicitTime
            ? point
            : DateTime(
                point.year,
                point.month,
                point.day,
                dayEndMinutes ~/ 60,
                dayEndMinutes % 60,
              );
        final adjustedDueAtLocal = !candidate.hasExplicitTime &&
                candidate.projectedRollForwardDays > 0 &&
                dueAtLocal.isBefore(nowLocal)
            ? dueAtLocal.add(
                Duration(days: candidate.projectedRollForwardDays),
              )
            : dueAtLocal;
        return TemporalResolution(
          mode: mode,
          confidence: candidate.confidence,
          resolver: candidate.resolver,
          semantics: TemporalSemantics.pointInTime,
          dueAtLocal: adjustedDueAtLocal,
          metadata: candidate.metadata.copyWith(
            normalizedExpression:
                candidate.metadata.normalizedExpression ?? normalizedText,
          ),
        );
    }
  }

  static TemporalResolution? _projectBoundaryExpressionWindow(
    TemporalCandidate candidate, {
    required TemporalMode mode,
    required DateTime nowLocal,
    required String normalizedText,
  }) {
    final expression =
        candidate.metadata.normalizedExpression ?? normalizedText;
    if (!expression.contains('春节后') || candidate.pointLocal == null) {
      return null;
    }

    final boundary = candidate.pointLocal!;
    if (!boundary.isAfter(nowLocal)) {
      return TemporalResolution(
        mode: mode,
        confidence: candidate.confidence,
        resolver: candidate.resolver,
        semantics: TemporalSemantics.rangePast,
        startLocal: boundary,
        endLocal: nowLocal,
        metadata: candidate.metadata.copyWith(
          normalizedExpression: expression,
        ),
      );
    }

    return TemporalResolution(
      mode: mode,
      confidence: candidate.confidence,
      resolver: candidate.resolver,
      semantics: TemporalSemantics.rangeFuture,
      startLocal: boundary,
      endLocal: boundary.add(const Duration(days: 7)),
      metadata: candidate.metadata.copyWith(
        normalizedExpression: expression,
      ),
    );
  }

  static TemporalResolution _none(
    TemporalMode mode,
    String normalizedText,
    TemporalMetadata metadata,
  ) {
    return TemporalResolution(
      mode: mode,
      confidence: 0,
      resolver: TemporalResolver.none,
      semantics: TemporalSemantics.none,
      metadata: metadata.copyWith(
        normalizedExpression: metadata.normalizedExpression ?? normalizedText,
      ),
    );
  }
}
