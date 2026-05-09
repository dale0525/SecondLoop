import 'package:flutter/foundation.dart';

import 'model_capability_verification.dart';
import 'runtime_manifest.dart';

export 'model_capability_verification.dart';

enum SelfManagedSetupStep {
  idle,
  authorizing,
  deploying,
  verifying,
  ready,
  failed,
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
  });

  final String cloudflareAccountLabel;
  final String provider;
  final String apiKey;
  final String embeddingApiKey;
  final String multimodalApiKey;
  final bool requiresMultimodalLlm;

  bool get hasRequiredAiProviderConfig {
    final hasLlm = apiKey.trim().isNotEmpty;
    final hasEmbeddings = embeddingApiKey.trim().isNotEmpty;
    final hasMultimodal =
        !requiresMultimodalLlm || multimodalApiKey.trim().isNotEmpty || hasLlm;
    return hasLlm && hasEmbeddings && hasMultimodal;
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
