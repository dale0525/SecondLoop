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
    required bool cloudEnabled,
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

    final networkChain = <AudioTranscribeClient>[
      if (cloudEnabled)
        CloudGatewayWhisperAudioTranscribeClient(
          gatewayBaseUrl: gatewayBaseUrl,
          idToken: cloudIdToken,
          modelName: whisperModel,
        ),
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
      ...localRuntimeChain,
    ];

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
