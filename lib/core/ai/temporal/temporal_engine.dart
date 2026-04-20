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
      mode: mode,
    );

    final candidate = TemporalRuleResolver.resolve(
          text: text,
          normalizedText: normalizedText,
          nowLocal: nowLocal,
          locale: locale,
          firstDayOfWeek: firstDayOfWeek,
          mode: mode,
        ) ??
        TemporalLocalePluginRegistry.resolve(request);
    final needsEnhancementHint = allowEnhancement &&
        TemporalLocalePluginRegistry.needsEnhancement(request);

    if (candidate == null ||
        candidate.isAmbiguous ||
        candidate.confidence < 0.6) {
      return TemporalResolution(
        mode: mode,
        confidence: candidate?.confidence ?? 0,
        resolver: TemporalResolver.none,
        semantics: TemporalSemantics.none,
        metadata: _applyEnhancementPolicy(
          (candidate?.metadata ?? const TemporalMetadata()).copyWith(
            normalizedExpression: normalizedText,
            needsEnhancement:
                candidate?.metadata.needsEnhancement ?? needsEnhancementHint,
          ),
          allowEnhancement: allowEnhancement,
        ),
      );
    }

    return _projectCandidate(
      candidate,
      mode: mode,
      nowLocal: nowLocal,
      dayEndMinutes: dayEndMinutes,
      normalizedText: normalizedText,
      allowEnhancement: allowEnhancement,
    );
  }

  static TemporalResolution _projectCandidate(
    TemporalCandidate candidate, {
    required TemporalMode mode,
    required DateTime nowLocal,
    required int dayEndMinutes,
    required String normalizedText,
    required bool allowEnhancement,
  }) {
    switch (mode) {
      case TemporalMode.retrievalWindow:
        if (candidate.startLocal != null && candidate.endLocal != null) {
          return TemporalResolution(
            mode: mode,
            confidence: candidate.confidence,
            resolver: candidate.resolver,
            semantics: candidate.semantics,
            startLocal: candidate.startLocal,
            endLocal: candidate.endLocal,
            metadata: _applyEnhancementPolicy(
              candidate.metadata.copyWith(
                normalizedExpression:
                    candidate.metadata.normalizedExpression ?? normalizedText,
              ),
              allowEnhancement: allowEnhancement,
            ),
          );
        }
        final point = candidate.pointLocal;
        if (point == null) {
          return _none(
            mode,
            normalizedText,
            candidate.metadata,
            allowEnhancement: allowEnhancement,
          );
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
          metadata: _applyEnhancementPolicy(
            candidate.metadata.copyWith(
              normalizedExpression:
                  candidate.metadata.normalizedExpression ?? normalizedText,
            ),
            allowEnhancement: allowEnhancement,
          ),
        );
      case TemporalMode.todoDue:
      case TemporalMode.todoFollowupDue:
        if (candidate.pointLocal == null) {
          return _none(
            mode,
            normalizedText,
            candidate.metadata,
            allowEnhancement: allowEnhancement,
          );
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
          metadata: _applyEnhancementPolicy(
            candidate.metadata.copyWith(
              normalizedExpression:
                  candidate.metadata.normalizedExpression ?? normalizedText,
            ),
            allowEnhancement: allowEnhancement,
          ),
        );
    }
  }

  static TemporalResolution _none(
      TemporalMode mode, String normalizedText, TemporalMetadata metadata,
      {required bool allowEnhancement}) {
    return TemporalResolution(
      mode: mode,
      confidence: 0,
      resolver: TemporalResolver.none,
      semantics: TemporalSemantics.none,
      metadata: _applyEnhancementPolicy(
        metadata.copyWith(
          normalizedExpression: metadata.normalizedExpression ?? normalizedText,
        ),
        allowEnhancement: allowEnhancement,
      ),
    );
  }

  static TemporalMetadata _applyEnhancementPolicy(
    TemporalMetadata metadata, {
    required bool allowEnhancement,
  }) {
    if (allowEnhancement || !metadata.needsEnhancement) {
      return metadata;
    }
    return metadata.copyWith(needsEnhancement: false);
  }
}
