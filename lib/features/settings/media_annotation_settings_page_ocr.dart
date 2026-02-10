part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageOcrExtension
    on _MediaAnnotationSettingsPageState {
  bool _isZhOcrLocale(BuildContext context) {
    return Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
  }

  String _documentOcrEngineTitle(BuildContext context) {
    return _isZhOcrLocale(context) ? 'OCR 识别方案' : 'OCR recognition mode';
  }

  String _documentOcrEngineLabel(BuildContext context, String mode) {
    final normalized = normalizeOcrEngineMode(mode);
    final zh = _isZhOcrLocale(context);
    if (normalized == 'multimodal_llm') {
      return zh ? 'BYOK 多模态' : 'BYOK multimodal';
    }
    return zh ? '本地 OCR' : 'Local OCR';
  }

  String _documentOcrEngineSubtitle(
    BuildContext context, {
    required bool proUser,
    required bool cloudEnabled,
  }) {
    final zh = _isZhOcrLocale(context);
    if (proUser) {
      if (zh) {
        return cloudEnabled
            ? 'Pro 订阅用户跟随媒体理解开关，云端 OCR 用量计入 Ask AI。'
            : 'Pro 订阅用户跟随媒体理解开关。开启“使用 SecondLoop Cloud”后，OCR 将走云端并计入 Ask AI 用量。';
      }
      return cloudEnabled
          ? 'Pro follows the media understanding switch. Cloud OCR usage is counted under Ask AI.'
          : 'Pro follows the media understanding switch. Turn on Use SecondLoop Cloud to run OCR in cloud and count usage under Ask AI.';
    }
    if (zh) {
      return '免费版可在本地 OCR 与 BYOK 多模态 OCR 之间选择。';
    }
    return 'Free users can choose between local OCR and BYOK multimodal OCR.';
  }

  Future<void> _pickDocumentOcrEngineMode(
    ContentEnrichmentConfig contentConfig,
    MediaAnnotationConfig mediaConfig,
  ) async {
    if (_busy) return;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    if (subscriptionStatus == SubscriptionStatus.entitled) return;

    final zh = _isZhOcrLocale(context);
    final currentMode = normalizeOcrEngineMode(contentConfig.ocrEngineMode);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value = currentMode;

        Widget option({
          required String mode,
          required String title,
          required String subtitle,
          required void Function(void Function()) setInnerState,
        }) {
          return RadioListTile<String>(
            value: mode,
            groupValue: value,
            title: Text(title),
            subtitle: Text(subtitle),
            onChanged: (next) {
              if (next == null) return;
              setInnerState(() => value = next);
            },
          );
        }

        return AlertDialog(
          title: Text(_documentOcrEngineTitle(context)),
          content: StatefulBuilder(
            builder: (context, setInnerState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    option(
                      mode: 'platform_native',
                      title: zh ? '本地 OCR' : 'Local OCR',
                      subtitle: zh
                          ? '完全在设备端完成识别，不上传内容。'
                          : 'Runs entirely on-device and does not upload content.',
                      setInnerState: setInnerState,
                    ),
                    option(
                      mode: 'multimodal_llm',
                      title: zh ? 'BYOK 多模态' : 'BYOK multimodal',
                      subtitle: zh
                          ? '使用你配置的 OpenAI-compatible API 识别文字。'
                          : 'Use your OpenAI-compatible API profile for OCR.',
                      setInnerState: setInnerState,
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(context.t.common.actions.save),
            ),
          ],
        );
      },
    );

    if (!mounted || selected == null || selected == currentMode) return;
    if (selected == 'platform_native') {
      await _persistContentConfig(
        _copyContentConfig(contentConfig, ocrEngineMode: 'platform_native'),
      );
      return;
    }

    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    final sessionKey = SessionScope.of(context).sessionKey;
    List<LlmProfile> profiles = _llmProfiles ?? const <LlmProfile>[];
    if (profiles.isEmpty && backend != null) {
      profiles =
          await backend.listLlmProfiles(sessionKey).catchError((_) => profiles);
    }
    if (!mounted) return;

    var byokProfile = resolveMultimodalOcrByokProfile(
      profiles: profiles,
      preferredProfileId: mediaConfig.byokProfileId,
    );

    if (byokProfile == null) {
      final picked = await _promptOpenAiCompatibleProfileId();
      if (!mounted || picked == null || picked.trim().isEmpty) return;
      final pickedId = picked.trim();
      for (final profile in profiles) {
        if (profile.id == pickedId) {
          byokProfile = profile;
          break;
        }
      }

      final nextMediaConfig = MediaAnnotationConfig(
        annotateEnabled: mediaConfig.annotateEnabled,
        searchEnabled: mediaConfig.searchEnabled,
        allowCellular: mediaConfig.allowCellular,
        providerMode: mediaConfig.providerMode,
        byokProfileId: pickedId,
        cloudModelName: mediaConfig.cloudModelName,
      );
      final nextContentConfig =
          _copyContentConfig(contentConfig, ocrEngineMode: 'multimodal_llm');
      await _persistBoth(
        mediaConfig: nextMediaConfig,
        contentConfig: nextContentConfig,
      );
      return;
    }

    await _persistContentConfig(
      _copyContentConfig(contentConfig, ocrEngineMode: 'multimodal_llm'),
    );
  }

  String _audioTranscribeApiProfileSubtitle(
    BuildContext context, {
    required bool localRuntime,
  }) {
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    if (localRuntime) {
      return zh
          ? '当前使用本地转写，不依赖 BYOK profile。'
          : 'Local runtime transcription is active and does not use a BYOK profile.';
    }
    if (zh) {
      return '默认跟随 Ask AI，可改为已有 OpenAI-compatible API profile。';
    }
    return 'Default follows Ask AI. You can choose an existing OpenAI-compatible API profile.';
  }

  bool _isLocalRuntimeAudioTranscribeEngine(String engine) {
    return normalizeAudioTranscribeEngine(engine) == 'local_runtime';
  }

  String _audioTranscribeEngineLabel(BuildContext context, String engine) {
    final labels =
        context.t.settings.mediaAnnotation.audioTranscribe.engine.labels;
    switch (normalizeAudioTranscribeEngine(engine)) {
      case 'local_runtime':
        return _isZhOcrLocale(context) ? '本地转写' : 'Local runtime';
      case 'multimodal_llm':
        return labels.multimodalLlm;
      default:
        return labels.whisper;
    }
  }

  Future<void> _pickAudioTranscribeEngine(
    ContentEnrichmentConfig config,
  ) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.audioTranscribe.engine;
    final zh = _isZhOcrLocale(context);

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value =
            normalizeAudioTranscribeEngine(config.audioTranscribeEngine);

        Widget option({
          required String mode,
          required String title,
          required String subtitle,
          required void Function(void Function()) setInnerState,
        }) {
          return RadioListTile<String>(
            value: mode,
            groupValue: value,
            title: Text(title),
            subtitle: Text(subtitle),
            onChanged: (next) {
              if (next == null) return;
              setInnerState(() => value = next);
            },
          );
        }

        return AlertDialog(
          title: Text(t.title),
          content: StatefulBuilder(
            builder: (context, setInnerState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    option(
                      mode: 'local_runtime',
                      title: zh ? '本地转写' : 'Local runtime',
                      subtitle: zh
                          ? '优先本地 runtime 转写，失败时回落设备原生 STT（若可用）。'
                          : 'Prefer local runtime transcription, then fallback to native STT when available.',
                      setInnerState: setInnerState,
                    ),
                    option(
                      mode: 'whisper',
                      title: t.labels.whisper,
                      subtitle: t.descriptions.whisper,
                      setInnerState: setInnerState,
                    ),
                    option(
                      mode: 'multimodal_llm',
                      title: t.labels.multimodalLlm,
                      subtitle: t.descriptions.multimodalLlm,
                      setInnerState: setInnerState,
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(context.t.common.actions.save),
            ),
          ],
        );
      },
    );

    if (!mounted || selected == null) return;
    final normalizedSelected = normalizeAudioTranscribeEngine(selected);
    if (normalizedSelected ==
        normalizeAudioTranscribeEngine(config.audioTranscribeEngine)) {
      return;
    }

    final nextContentConfig = _copyContentConfig(
      config,
      audioTranscribeEngine: normalizedSelected,
    );

    if (normalizedSelected == 'local_runtime') {
      await _persistContentConfig(nextContentConfig);
      return;
    }

    final mediaConfig = _config;
    if (mediaConfig == null) {
      await _persistContentConfig(nextContentConfig);
      return;
    }

    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    final sessionKey = SessionScope.of(context).sessionKey;
    List<LlmProfile> profiles = _llmProfiles ?? const <LlmProfile>[];
    if (profiles.isEmpty && backend != null) {
      profiles =
          await backend.listLlmProfiles(sessionKey).catchError((_) => profiles);
    }
    if (!mounted) return;

    final existingByokId = mediaConfig.byokProfileId?.trim();
    var hasValidSelected = false;
    if (existingByokId != null && existingByokId.isNotEmpty) {
      for (final profile in profiles) {
        if (profile.id == existingByokId &&
            profile.providerType == 'openai-compatible') {
          hasValidSelected = true;
          break;
        }
      }
    }

    var resolvedByokId = existingByokId;
    if (!hasValidSelected) {
      resolvedByokId = await _promptOpenAiCompatibleProfileId();
      final trimmed = resolvedByokId?.trim();
      if (!mounted || trimmed == null || trimmed.isEmpty) return;
      resolvedByokId = trimmed;
    }

    final shouldUpdateMediaConfig =
        (mediaConfig.byokProfileId ?? '').trim() != resolvedByokId;
    if (!shouldUpdateMediaConfig) {
      await _persistContentConfig(nextContentConfig);
      return;
    }

    await _persistBoth(
      mediaConfig: MediaAnnotationConfig(
        annotateEnabled: mediaConfig.annotateEnabled,
        searchEnabled: mediaConfig.searchEnabled,
        allowCellular: mediaConfig.allowCellular,
        providerMode: mediaConfig.providerMode,
        byokProfileId: resolvedByokId,
        cloudModelName: mediaConfig.cloudModelName,
      ),
      contentConfig: nextContentConfig,
    );
  }
}
