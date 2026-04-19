import 'package:flutter/widgets.dart';

enum TemporalMode { retrievalWindow, todoDue, todoFollowupDue }

enum TemporalResolver { rule, localePlugin, llm, none }

enum TemporalSemantics { none, pointInTime, rangePast, rangeFuture, rangeBoth }

final class TemporalMetadata {
  const TemporalMetadata({
    this.inferredTimeOfDay,
    this.inferredCalendarSystem,
    this.ambiguous = false,
    this.needsEnhancement = false,
    this.normalizedExpression,
  });

  final String? inferredTimeOfDay;
  final String? inferredCalendarSystem;
  final bool ambiguous;
  final bool needsEnhancement;
  final String? normalizedExpression;

  TemporalMetadata copyWith({
    String? inferredTimeOfDay,
    String? inferredCalendarSystem,
    bool? ambiguous,
    bool? needsEnhancement,
    String? normalizedExpression,
  }) {
    return TemporalMetadata(
      inferredTimeOfDay: inferredTimeOfDay ?? this.inferredTimeOfDay,
      inferredCalendarSystem:
          inferredCalendarSystem ?? this.inferredCalendarSystem,
      ambiguous: ambiguous ?? this.ambiguous,
      needsEnhancement: needsEnhancement ?? this.needsEnhancement,
      normalizedExpression: normalizedExpression ?? this.normalizedExpression,
    );
  }
}

final class TemporalResolution {
  const TemporalResolution({
    required this.mode,
    required this.confidence,
    required this.resolver,
    required this.semantics,
    this.dueAtLocal,
    this.startLocal,
    this.endLocal,
    this.metadata = const TemporalMetadata(),
  });

  final TemporalMode mode;
  final double confidence;
  final TemporalResolver resolver;
  final TemporalSemantics semantics;
  final DateTime? dueAtLocal;
  final DateTime? startLocal;
  final DateTime? endLocal;
  final TemporalMetadata metadata;
}

final class TemporalCandidate {
  const TemporalCandidate({
    required this.resolver,
    required this.confidence,
    required this.semantics,
    this.pointLocal,
    this.startLocal,
    this.endLocal,
    this.hasExplicitTime = false,
    this.projectedRollForwardDays = 0,
    this.metadata = const TemporalMetadata(),
  });

  final TemporalResolver resolver;
  final double confidence;
  final TemporalSemantics semantics;
  final DateTime? pointLocal;
  final DateTime? startLocal;
  final DateTime? endLocal;
  final bool hasExplicitTime;
  final int projectedRollForwardDays;
  final TemporalMetadata metadata;

  bool get isAmbiguous => metadata.ambiguous;

  TemporalCandidate withResolver(TemporalResolver resolver) {
    return TemporalCandidate(
      resolver: resolver,
      confidence: confidence,
      semantics: semantics,
      pointLocal: pointLocal,
      startLocal: startLocal,
      endLocal: endLocal,
      hasExplicitTime: hasExplicitTime,
      projectedRollForwardDays: projectedRollForwardDays,
      metadata: metadata,
    );
  }
}

final class TemporalPluginRequest {
  const TemporalPluginRequest({
    required this.text,
    required this.normalizedText,
    required this.nowLocal,
    required this.locale,
    required this.timezone,
    required this.firstDayOfWeek,
  });

  final String text;
  final String normalizedText;
  final DateTime nowLocal;
  final Locale locale;
  final String timezone;
  final int firstDayOfWeek;
}
