part of 'media_enrichment_gate.dart';

const bool _kEnableMacosNativeSttFallback = bool.fromEnvironment(
  'SECONDLOOP_ENABLE_MACOS_NATIVE_STT_FALLBACK',
  defaultValue: true,
);

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
    required String gatewayBaseUrl,
    required String cloudIdToken,
    required Uint8List sessionKey,
  }) {
    final shouldEnableLocalFallback = effectiveEngine == 'local_runtime' ||
        isByokAudioTranscribeEngine(effectiveEngine) ||
        byokProfile != null ||
        cloudEnabled;
    final offlineChain = <AudioTranscribeClient>[
      if (shouldEnableLocalFallback)
        LocalRuntimeAudioTranscribeClient(
          modelName: 'local_runtime',
        ),
      ..._buildOptionalNativeSttAudioTranscribeFallbacks(),
    ];

    final networkChain = <AudioTranscribeClient>[
      if (cloudEnabled)
        CloudGatewayWhisperAudioTranscribeClient(
          gatewayBaseUrl: gatewayBaseUrl,
          idToken: cloudIdToken,
          modelName: 'cloud',
        ),
      if (effectiveEngine == 'multimodal_llm' && byokProfile != null)
        ByokMultimodalAudioTranscribeClient(
          sessionKey: Uint8List.fromList(sessionKey),
          profileId: byokProfile.id,
          modelName: byokProfile.modelName,
        ),
      if (effectiveEngine == 'whisper' && byokProfile != null)
        ByokWhisperAudioTranscribeClient(
          sessionKey: Uint8List.fromList(sessionKey),
          profileId: byokProfile.id,
          modelName: byokProfile.modelName,
        ),
      ...offlineChain,
    ];

    return _AudioTranscribeClientSelection(
      networkClient: _buildFallbackAudioTranscribeClient(networkChain),
      offlineClient: _buildFallbackAudioTranscribeClient(offlineChain),
    );
  }

  bool _shouldEnableMacosSpeechFallback() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return true;
    }
    return _kEnableMacosNativeSttFallback;
  }

  List<AudioTranscribeClient>
      _buildOptionalNativeSttAudioTranscribeFallbacks() {
    if (!_shouldEnableMacosSpeechFallback()) {
      return const <AudioTranscribeClient>[];
    }
    return <AudioTranscribeClient>[
      NativeSttAudioTranscribeClient(
        modelName: 'macos_native_stt',
      ),
    ];
  }

  AudioTranscribeClient? _buildFallbackAudioTranscribeClient(
    List<AudioTranscribeClient> chain,
  ) {
    if (chain.isEmpty) return null;
    if (chain.length == 1) return chain.first;
    return FallbackAudioTranscribeClient(chain: chain);
  }
}
