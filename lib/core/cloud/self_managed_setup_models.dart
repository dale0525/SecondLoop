import 'package:flutter/foundation.dart';

import 'runtime_manifest.dart';

enum SelfManagedSetupStep {
  idle,
  authorizing,
  deploying,
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
  });

  final CloudRuntimeManifest manifest;
  final String authToken;
  final String capabilityManifestId;
}

@immutable
class SelfManagedSetupState {
  const SelfManagedSetupState({
    required this.step,
    required this.statusMessage,
    this.errorCode,
    this.manifest,
  });

  const SelfManagedSetupState.idle()
      : step = SelfManagedSetupStep.idle,
        statusMessage = '',
        errorCode = null,
        manifest = null;

  final SelfManagedSetupStep step;
  final String statusMessage;
  final String? errorCode;
  final CloudRuntimeManifest? manifest;

  bool get isReady => step == SelfManagedSetupStep.ready;
  bool get hasError => step == SelfManagedSetupStep.failed;

  SelfManagedSetupState copyWith({
    SelfManagedSetupStep? step,
    String? statusMessage,
    Object? errorCode = _sentinel,
    Object? manifest = _sentinel,
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
    );
  }

  static const Object _sentinel = Object();
}
