import 'package:flutter/foundation.dart';

@immutable
final class ModelCapabilityVerificationResult {
  const ModelCapabilityVerificationResult({
    required this.ok,
    required this.checks,
  });

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
