import 'package:flutter/foundation.dart';

@immutable
final class ModelCapabilityVerificationResult {
  const ModelCapabilityVerificationResult({
    required this.ok,
    required this.checks,
  });

  static const allRequiredPassed = ModelCapabilityVerificationResult(
    ok: true,
    checks: [
      ModelCapabilityCheckResult(
        code: ModelCapabilityRequiredChecks.structuredOutput,
        passed: true,
      ),
      ModelCapabilityCheckResult(
        code: ModelCapabilityRequiredChecks.secretaryMetadata,
        passed: true,
      ),
      ModelCapabilityCheckResult(
        code: ModelCapabilityRequiredChecks.toolProposalDiscipline,
        passed: true,
      ),
      ModelCapabilityCheckResult(
        code: ModelCapabilityRequiredChecks.multimodalUnderstanding,
        passed: true,
      ),
      ModelCapabilityCheckResult(
        code: ModelCapabilityRequiredChecks.chineseIntentHandling,
        passed: true,
      ),
      ModelCapabilityCheckResult(
        code: ModelCapabilityRequiredChecks.contextWindowLatency,
        passed: true,
      ),
      ModelCapabilityCheckResult(
        code: ModelCapabilityRequiredChecks.clarificationBehavior,
        passed: true,
      ),
      ModelCapabilityCheckResult(
        code: ModelCapabilityRequiredChecks.sideEffectDiscipline,
        passed: true,
      ),
    ],
  );

  final bool ok;
  final List<ModelCapabilityCheckResult> checks;

  String? get firstFailureCode {
    for (final check in checks) {
      if (!check.passed) {
        return check.failureCode ?? check.code;
      }
    }
    return null;
  }

  factory ModelCapabilityVerificationResult.fromJson(
    Map<String, Object?> json,
  ) {
    final checks = json['checks'];
    return ModelCapabilityVerificationResult(
      ok: json['ok'] == true,
      checks: checks is List
          ? checks
              .whereType<Map>()
              .map(
                (item) => ModelCapabilityCheckResult.fromJson(
                  item.map((key, value) => MapEntry('$key', value)),
                ),
              )
              .toList(growable: false)
          : const <ModelCapabilityCheckResult>[],
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ok': ok,
      'failure_code': firstFailureCode,
      'checks': checks.map((check) => check.toJson()).toList(growable: false),
    };
  }
}

final class ModelCapabilityRequiredChecks {
  const ModelCapabilityRequiredChecks._();

  static const structuredOutput = 'structured_output';
  static const secretaryMetadata = 'secretary_metadata';
  static const toolProposalDiscipline = 'tool_proposal_discipline';
  static const multimodalUnderstanding = 'multimodal_understanding';
  static const chineseIntentHandling = 'chinese_intent_handling';
  static const contextWindowLatency = 'context_window_latency';
  static const clarificationBehavior = 'clarification_behavior';
  static const sideEffectDiscipline = 'side_effect_discipline';

  static const all = <String>[
    structuredOutput,
    secretaryMetadata,
    toolProposalDiscipline,
    multimodalUnderstanding,
    chineseIntentHandling,
    contextWindowLatency,
    clarificationBehavior,
    sideEffectDiscipline,
  ];

  static String? firstMissingFrom(
    Iterable<ModelCapabilityCheckResult> checks,
  ) {
    final reported = checks.map((check) => check.code).toSet();
    for (final code in all) {
      if (!reported.contains(code)) {
        return code;
      }
    }
    return null;
  }
}

@immutable
final class ModelCapabilityCheckResult {
  const ModelCapabilityCheckResult({
    required this.code,
    required this.passed,
    this.failureCode,
  });

  final String code;
  final bool passed;
  final String? failureCode;

  factory ModelCapabilityCheckResult.fromJson(Map<String, Object?> json) {
    return ModelCapabilityCheckResult(
      code: _parseString(json['code']) ?? '',
      passed: json['passed'] == true,
      failureCode: _parseString(json['failure_code']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'passed': passed,
      'failure_code': failureCode,
    };
  }
}

String? _parseString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
