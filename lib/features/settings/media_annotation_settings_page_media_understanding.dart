part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageMediaUnderstandingExtension
    on _MediaAnnotationSettingsPageState {
  Future<void> _persistBoth({
    required MediaAnnotationConfig mediaConfig,
    required ContentEnrichmentConfig contentConfig,
  }) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    _mutateState(() => _busy = true);
    try {
      await _store.write(sessionKey, mediaConfig);
      await _contentStore.writeContentEnrichment(sessionKey, contentConfig);
      if (!mounted) return;
      _mutateState(() {
        _config = mediaConfig;
        _contentConfig = contentConfig;
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _mutateState(() => _busy = false);
    }
  }

  bool _isMediaUnderstandingEnabled(
    MediaAnnotationConfig config,
    ContentEnrichmentConfig? contentConfig,
  ) {
    if (contentConfig == null) return false;
    return config.annotateEnabled &&
        config.searchEnabled &&
        contentConfig.audioTranscribeEnabled &&
        contentConfig.ocrEnabled;
  }

  bool _isZhLocale(BuildContext context) {
    return Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
  }

  String _mediaUnderstandingTitle(BuildContext context) {
    return _isZhLocale(context) ? '智能化（旧版入口）' : 'Intelligence (legacy entry)';
  }

  String _mediaUnderstandingSubtitle(BuildContext context) {
    if (_isZhLocale(context)) {
      return '旧版兼容入口：统一控制音频转写、文档 OCR 和图片注释。';
    }
    return 'Legacy compatibility entry: one switch controls audio transcription, document OCR, and image annotations.';
  }

  String _useSecondLoopCloudTitle(BuildContext context) {
    return _isZhLocale(context)
        ? '使用 SecondLoop Cloud'
        : 'Use SecondLoop Cloud';
  }

  String _useSecondLoopCloudSubtitle(BuildContext context) {
    if (_isZhLocale(context)) {
      return '开启后相关媒体数据会上传到 SecondLoop Cloud 处理。我们采用传输加密、严格访问控制与最小化保留策略。';
    }
    return 'When enabled, relevant media data is uploaded to SecondLoop Cloud for processing. We protect it with encrypted transport, strict access controls, and minimized retention.';
  }

  String _mediaUnderstandingWifiOnlyTitle(BuildContext context) {
    return _isZhLocale(context) ? '仅 Wi-Fi' : 'Wi-Fi only';
  }

  String _mediaUnderstandingWifiOnlySubtitle(BuildContext context) {
    if (_isZhLocale(context)) {
      return '仅在 Wi-Fi 下执行云端/BYOK 处理，本地能力不受影响。';
    }
    return 'Run cloud/BYOK processing only on Wi-Fi. Local capability is unaffected.';
  }

  Future<void> _setMediaUnderstandingEnabled({
    required bool enabled,
    required MediaAnnotationConfig config,
    required ContentEnrichmentConfig contentConfig,
  }) async {
    if (_busy) return;
    final nextMediaConfig = MediaAnnotationConfig(
      annotateEnabled: enabled,
      searchEnabled: enabled,
      allowCellular: config.allowCellular,
      providerMode: config.providerMode,
      byokProfileId: config.byokProfileId,
      cloudModelName: config.cloudModelName,
    );

    final nextContentConfig = _copyContentConfig(
      contentConfig,
      audioTranscribeEnabled: enabled,
      ocrEnabled: enabled,
    );

    await _persistBoth(
      mediaConfig: nextMediaConfig,
      contentConfig: nextContentConfig,
    );
  }

  Future<void> _setMediaUnderstandingWifiOnly({
    required bool wifiOnly,
    required MediaAnnotationConfig config,
  }) async {
    if (_busy) return;
    try {
      await MediaCapabilityWifiPrefs.writeAll(wifiOnly: wifiOnly);
      if (mounted) {
        _mutateState(() {
          _audioWifiOnly = wifiOnly;
          _ocrWifiOnly = wifiOnly;
        });
      }
    } catch (_) {
      // Fall back to legacy config persistence below.
    }

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: !wifiOnly,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      ),
    );
  }

  Future<void> _setUseSecondLoopCloudEnabled({
    required bool enabled,
    required MediaAnnotationConfig config,
  }) async {
    if (_busy) return;
    if (!enabled) {
      final hasByokOverride =
          (config.byokProfileId?.trim().isNotEmpty ?? false);
      await _persist(
        MediaAnnotationConfig(
          annotateEnabled: config.annotateEnabled,
          searchEnabled: config.searchEnabled,
          allowCellular: config.allowCellular,
          providerMode: hasByokOverride
              ? _MediaAnnotationSettingsPageState._kProviderByokProfile
              : _MediaAnnotationSettingsPageState._kProviderFollowAskAi,
          byokProfileId: config.byokProfileId,
          cloudModelName: config.cloudModelName,
        ),
      );
      return;
    }

    final prepared = await _prepareEnableAnnotateConfig(
      MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: _MediaAnnotationSettingsPageState._kProviderCloudGateway,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      ),
    );
    if (prepared == null || !mounted) return;

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: prepared.allowCellular,
        providerMode: _MediaAnnotationSettingsPageState._kProviderCloudGateway,
        byokProfileId: prepared.byokProfileId,
        cloudModelName: prepared.cloudModelName,
      ),
    );
  }
}
