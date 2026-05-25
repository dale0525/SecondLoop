import 'package:flutter/foundation.dart';

import 'model_capability_verification.dart';
import 'runtime_manifest.dart';

export 'model_capability_verification.dart';

enum SelfManagedSetupStep {
  idle,
  authorizing,
  cloudflareReady,
  deploying,
  verifying,
  ready,
  failed,
}

enum SelfManagedCloudflareAuthorizationMethod {
  oauth,
  manual,
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
    if (usesManualCloudflareCredentials) {
      return cloudflareAccountId.trim();
    }
    return cloudflareAccountLabel.trim();
  }

  String? get firstMissingCloudflareAuthorizationField {
    if (usesManualCloudflareCredentials) {
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
  bool get isCloudflareReady =>
      step == SelfManagedSetupStep.cloudflareReady ||
      step == SelfManagedSetupStep.deploying ||
      step == SelfManagedSetupStep.verifying ||
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
