import 'package:meta/meta.dart';

import 'model_capability_verification.dart';
import 'runtime_manifest.dart';

export 'model_capability_verification.dart';

enum SelfManagedSetupStep {
  idle,
  authorizing,
  cloudflareReady,
  deploying,
  verifying,
  uninstalling,
  uninstalled,
  ready,
  failed,
}

enum SelfManagedCloudflareAuthorizationMethod {
  oauth,
  manual,
}

@immutable
class SelfManagedCloudflareAuthorizationResult {
  const SelfManagedCloudflareAuthorizationResult({
    required this.cloudflareAccountId,
    this.cloudflareAccountName = '',
    this.cloudflareUserEmail = '',
  });

  final String cloudflareAccountId;
  final String cloudflareAccountName;
  final String cloudflareUserEmail;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cloudflare_account_id': cloudflareAccountId,
      if (cloudflareAccountName.isNotEmpty)
        'cloudflare_account_name': cloudflareAccountName,
      if (cloudflareUserEmail.isNotEmpty)
        'cloudflare_user_email': cloudflareUserEmail,
    };
  }

  factory SelfManagedCloudflareAuthorizationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return SelfManagedCloudflareAuthorizationResult(
      cloudflareAccountId: (json['cloudflare_account_id'] as String?) ?? '',
      cloudflareAccountName: (json['cloudflare_account_name'] as String?) ?? '',
      cloudflareUserEmail: (json['cloudflare_user_email'] as String?) ?? '',
    );
  }
}

@immutable
class SelfManagedSetupRequest {
  const SelfManagedSetupRequest({
    required this.cloudflareAccountLabel,
    required this.provider,
    required this.apiKey,
    this.embeddingApiKey = '',
    this.multimodalApiKey = '',
    this.requiresMultimodalLlm = true,
    this.cloudflareAuthorizationMethod =
        SelfManagedCloudflareAuthorizationMethod.oauth,
    this.cloudflareAccountId = '',
    this.cloudflareApiToken = '',
  });

  final String cloudflareAccountLabel;
  final String provider;
  final String apiKey;
  final String embeddingApiKey;
  final String multimodalApiKey;
  final bool requiresMultimodalLlm;
  final SelfManagedCloudflareAuthorizationMethod cloudflareAuthorizationMethod;
  final String cloudflareAccountId;
  final String cloudflareApiToken;

  bool get hasRequiredAiProviderConfig {
    final hasLlm = apiKey.trim().isNotEmpty;
    final hasEmbeddings = embeddingApiKey.trim().isNotEmpty;
    final hasMultimodal =
        !requiresMultimodalLlm || multimodalApiKey.trim().isNotEmpty || hasLlm;
    return hasLlm && hasEmbeddings && hasMultimodal;
  }

  bool get usesManualCloudflareCredentials =>
      cloudflareAuthorizationMethod ==
      SelfManagedCloudflareAuthorizationMethod.manual;

  String get cloudflareDeploymentAccountId {
    return resolveSelfManagedCloudflareDeploymentAccountId(
      cloudflareAuthorizationMethod: cloudflareAuthorizationMethod,
      cloudflareAccountId: cloudflareAccountId,
      cloudflareAccountLabel: cloudflareAccountLabel,
    );
  }

  String? get firstMissingCloudflareAuthorizationField {
    return firstMissingSelfManagedCloudflareAuthorizationField(
      cloudflareAuthorizationMethod: cloudflareAuthorizationMethod,
      cloudflareAccountId: cloudflareAccountId,
      cloudflareApiToken: cloudflareApiToken,
      cloudflareAccountLabel: cloudflareAccountLabel,
    );
  }
}

@immutable
class SelfManagedRuntimeUninstallRequest {
  const SelfManagedRuntimeUninstallRequest({
    required this.cloudflareAccountLabel,
    this.cloudflareAuthorizationMethod =
        SelfManagedCloudflareAuthorizationMethod.oauth,
    this.cloudflareAccountId = '',
    this.cloudflareApiToken = '',
    this.runtimeId = '',
  });

  final String cloudflareAccountLabel;
  final SelfManagedCloudflareAuthorizationMethod cloudflareAuthorizationMethod;
  final String cloudflareAccountId;
  final String cloudflareApiToken;
  final String runtimeId;

  bool get usesManualCloudflareCredentials =>
      cloudflareAuthorizationMethod ==
      SelfManagedCloudflareAuthorizationMethod.manual;

  String get cloudflareDeploymentAccountId {
    return resolveSelfManagedCloudflareDeploymentAccountId(
      cloudflareAuthorizationMethod: cloudflareAuthorizationMethod,
      cloudflareAccountId: cloudflareAccountId,
      cloudflareAccountLabel: cloudflareAccountLabel,
    );
  }

  String? get firstMissingCloudflareAuthorizationField {
    return firstMissingSelfManagedCloudflareAuthorizationField(
      cloudflareAuthorizationMethod: cloudflareAuthorizationMethod,
      cloudflareAccountId: cloudflareAccountId,
      cloudflareApiToken: cloudflareApiToken,
      cloudflareAccountLabel: cloudflareAccountLabel,
    );
  }
}

@immutable
class SelfManagedRuntimeUninstallResult {
  const SelfManagedRuntimeUninstallResult({
    required this.ok,
    required this.runtimeMode,
    required this.cloudflareAccountId,
    required this.removedWorkers,
    required this.removedBindings,
    required this.removedSecrets,
  });

  final bool ok;
  final String runtimeMode;
  final String cloudflareAccountId;
  final List<String> removedWorkers;
  final List<String> removedBindings;
  final List<String> removedSecrets;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ok': ok,
      'runtime_mode': runtimeMode,
      'cloudflare_account_id': cloudflareAccountId,
      'removed_workers': removedWorkers,
      'removed_bindings': removedBindings,
      'removed_secrets': removedSecrets,
    };
  }
}

@immutable
class SelfManagedSetupProgress {
  const SelfManagedSetupProgress({
    required this.step,
    required this.message,
  });

  final SelfManagedSetupStep step;
  final String message;
}

@immutable
class SelfManagedSetupResult {
  const SelfManagedSetupResult({
    required this.manifest,
    required this.authToken,
    required this.capabilityManifestId,
    this.verification,
  });

  final CloudRuntimeManifest manifest;
  final String authToken;
  final String capabilityManifestId;
  final ModelCapabilityVerificationResult? verification;
}

@immutable
class SelfManagedSetupState {
  const SelfManagedSetupState({
    required this.step,
    required this.statusMessage,
    this.errorCode,
    this.manifest,
    this.verification,
  });

  const SelfManagedSetupState.idle()
      : step = SelfManagedSetupStep.idle,
        statusMessage = '',
        errorCode = null,
        manifest = null,
        verification = null;

  final SelfManagedSetupStep step;
  final String statusMessage;
  final String? errorCode;
  final CloudRuntimeManifest? manifest;
  final ModelCapabilityVerificationResult? verification;

  bool get isReady => step == SelfManagedSetupStep.ready;
  bool get isUninstalled => step == SelfManagedSetupStep.uninstalled;
  bool get isCloudflareReady =>
      step == SelfManagedSetupStep.cloudflareReady ||
      step == SelfManagedSetupStep.deploying ||
      step == SelfManagedSetupStep.verifying ||
      step == SelfManagedSetupStep.uninstalling ||
      step == SelfManagedSetupStep.ready;
  bool get hasError => step == SelfManagedSetupStep.failed;

  SelfManagedSetupState copyWith({
    SelfManagedSetupStep? step,
    String? statusMessage,
    Object? errorCode = _sentinel,
    Object? manifest = _sentinel,
    Object? verification = _sentinel,
  }) {
    return SelfManagedSetupState(
      step: step ?? this.step,
      statusMessage: statusMessage ?? this.statusMessage,
      errorCode: identical(errorCode, _sentinel)
          ? this.errorCode
          : errorCode as String?,
      manifest: identical(manifest, _sentinel)
          ? this.manifest
          : manifest as CloudRuntimeManifest?,
      verification: identical(verification, _sentinel)
          ? this.verification
          : verification as ModelCapabilityVerificationResult?,
    );
  }

  static const Object _sentinel = Object();
}

String resolveSelfManagedCloudflareDeploymentAccountId({
  required SelfManagedCloudflareAuthorizationMethod
      cloudflareAuthorizationMethod,
  required String cloudflareAccountId,
  required String cloudflareAccountLabel,
}) {
  if (cloudflareAuthorizationMethod ==
      SelfManagedCloudflareAuthorizationMethod.manual) {
    return cloudflareAccountId.trim();
  }
  return cloudflareAccountLabel.trim();
}

String? firstMissingSelfManagedCloudflareAuthorizationField({
  required SelfManagedCloudflareAuthorizationMethod
      cloudflareAuthorizationMethod,
  required String cloudflareAccountId,
  required String cloudflareApiToken,
  required String cloudflareAccountLabel,
}) {
  if (cloudflareAuthorizationMethod ==
      SelfManagedCloudflareAuthorizationMethod.manual) {
    if (cloudflareAccountId.trim().isEmpty) {
      return 'missing_cloudflare_account_id';
    }
    if (cloudflareApiToken.trim().isEmpty) {
      return 'missing_cloudflare_api_token';
    }
    return null;
  }
  if (cloudflareAccountLabel.trim().isEmpty) {
    return 'missing_cloudflare_account_label';
  }
  return null;
}
