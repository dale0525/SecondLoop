part of 'media_enrichment_gate.dart';

final class _AudioTranscribeClientSelection {
  const _AudioTranscribeClientSelection({
    required this.networkClient,
    required this.offlineClient,
  });

  final AudioTranscribeClient? networkClient;
  final AudioTranscribeClient? offlineClient;

  bool get hasAnyClient => networkClient != null || offlineClient != null;
}

extension _MediaEnrichmentGateAudioTranscribeExtension
    on _MediaEnrichmentGateState {
  _AudioTranscribeClientSelection _buildAudioTranscribeClientSelection({
    required MediaSourcePreference preference,
    required bool cloudAvailable,
    required LlmProfile? byokProfile,
    required String effectiveEngine,
    required String whisperModel,
    required String gatewayBaseUrl,
    required String cloudIdToken,
    required Uint8List sessionKey,
  }) {
    final normalizedEngine = normalizeAudioTranscribeEngine(effectiveEngine);
    final useWhisperEngine =
        normalizedEngine == 'whisper' || normalizedEngine == 'local_runtime';
    final supportsLocalRuntime = supportsPlatformLocalRuntimeAudioTranscribe();

    final localRuntimeChain = <AudioTranscribeClient>[
      if (supportsLocalRuntime && useWhisperEngine)
        LocalRuntimeAudioTranscribeClient(
          modelName: 'runtime-whisper-$whisperModel',
          whisperModel: whisperModel,
        ),
    ];

    final cloudClient = cloudAvailable
        ? CloudGatewayWhisperAudioTranscribeClient(
            gatewayBaseUrl: gatewayBaseUrl,
            idToken: cloudIdToken,
            modelName: whisperModel,
          )
        : null;
    final byokChain = <AudioTranscribeClient>[
      if (normalizedEngine == 'multimodal_llm' && byokProfile != null)
        ByokMultimodalAudioTranscribeClient(
          sessionKey: Uint8List.fromList(sessionKey),
          profileId: byokProfile.id,
          modelName: byokProfile.modelName,
        ),
      if (useWhisperEngine && byokProfile != null)
        ByokWhisperAudioTranscribeClient(
          sessionKey: Uint8List.fromList(sessionKey),
          profileId: byokProfile.id,
          modelName: byokProfile.modelName,
        ),
    ];

    final networkChain = <AudioTranscribeClient>[];
    final orderedRoutes = mediaSourceFallbackOrder(preference);
    for (final route in orderedRoutes) {
      switch (route) {
        case MediaSourceRouteKind.cloudGateway:
          if (cloudClient != null) {
            networkChain.add(cloudClient);
          }
          break;
        case MediaSourceRouteKind.byok:
          if (byokChain.isNotEmpty) {
            networkChain.addAll(byokChain);
          }
          break;
        case MediaSourceRouteKind.local:
          if (localRuntimeChain.isNotEmpty) {
            networkChain.addAll(localRuntimeChain);
          }
          break;
      }
    }

    return _AudioTranscribeClientSelection(
      networkClient: _buildFallbackAudioTranscribeClient(networkChain),
      offlineClient: _buildFallbackAudioTranscribeClient(localRuntimeChain),
    );
  }

  AudioTranscribeClient? _buildFallbackAudioTranscribeClient(
    List<AudioTranscribeClient> chain,
  ) {
    if (chain.isEmpty) return null;
    if (chain.length == 1) return chain.first;
    return FallbackAudioTranscribeClient(chain: chain);
  }
}
