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
        contentConfig.ocrEnabled &&
        contentConfig.pdfSmartCompressEnabled;
  }

  bool _isZhLocale(BuildContext context) {
    return Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
  }

  String _mediaUnderstandingTitle(BuildContext context) {
    return _isZhLocale(context) ? '媒体理解' : 'Media understanding';
  }

  String _mediaUnderstandingSubtitle(BuildContext context) {
    if (_isZhLocale(context)) {
      return '统一控制音频转写、文档 OCR、PDF 智能压缩和图片注释。关闭后会隐藏下方详细设置。';
    }
    return 'One switch controls audio transcription, document OCR, PDF smart compression, and image annotations. Turn off to hide details below.';
  }

  String _useSecondLoopCloudTitle(BuildContext context) {
    return _isZhLocale(context)
        ? '使用 SecondLoop Cloud'
        : 'Use SecondLoop Cloud';
  }

  String _useSecondLoopCloudSubtitle(BuildContext context) {
    if (_isZhLocale(context)) {
      return '开启后相关媒体数据会上传到 SecondLoop Cloud 处理。我们采用传输加密、严格访问控制与最小化保留策略。在 Pro 生效且用量未耗尽前，下方设置优先使用 SecondLoop Cloud 用量。';
    }
    return 'When enabled, relevant media data is uploaded to SecondLoop Cloud for processing. We protect it with encrypted transport, strict access controls, and minimized retention. While Pro is active and quota remains, settings below prioritize SecondLoop Cloud usage.';
  }

  String _mediaUnderstandingWifiOnlyTitle(BuildContext context) {
    return _isZhLocale(context) ? '仅 Wi-Fi' : 'Wi-Fi only';
  }

  String _mediaUnderstandingWifiOnlySubtitle(BuildContext context) {
    if (_isZhLocale(context)) {
      return '仅在 Wi-Fi 下进行媒体理解处理。关闭后可使用蜂窝网络。';
    }
    return 'Run media understanding only on Wi-Fi. Turn off to allow cellular data.';
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
      pdfSmartCompressEnabled: enabled,
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
