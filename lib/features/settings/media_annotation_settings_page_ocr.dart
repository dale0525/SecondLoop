part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageOcrExtension
    on _MediaAnnotationSettingsPageState {
  String _documentOcrEngineTitle(BuildContext context) {
    return context.t.settings.mediaAnnotation.documentOcr.engineMode.title;
  }

  String _documentOcrEngineLabel(BuildContext context, String mode) {
    final labels =
        context.t.settings.mediaAnnotation.documentOcr.engineMode.labels;
    return switch (normalizeOcrEngineMode(mode)) {
      'multimodal_llm' => labels.multimodalLlm,
      _ => labels.platformNative,
    };
  }

  String _documentOcrEngineSubtitle(
    BuildContext context, {
    required bool proUser,
    required bool cloudEnabled,
  }) {
    final subtitles =
        context.t.settings.mediaAnnotation.documentOcr.engineMode.subtitles;
    if (proUser) {
      return cloudEnabled
          ? subtitles.proCloudEnabled
          : subtitles.proCloudDisabled;
    }
    return subtitles.free;
  }

  Future<void> _pickDocumentOcrEngineMode(
    ContentEnrichmentConfig contentConfig,
    MediaAnnotationConfig mediaConfig,
  ) async {
    if (_busy) return;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    if (subscriptionStatus == SubscriptionStatus.entitled) return;

    final t = context.t.settings.mediaAnnotation.documentOcr.engineMode;
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
                      title: t.labels.platformNative,
                      subtitle: t.descriptions.platformNative,
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

  String _audioTranscribeApiProfileSubtitle(BuildContext context) {
    return context.t.settings.mediaAnnotation.audioTranscribe.apiProfile
        .followActiveSubtitle;
  }

  String _audioTranscribeEngineLabel(BuildContext context, String engine) {
    final labels =
        context.t.settings.mediaAnnotation.audioTranscribe.engine.labels;
    switch (normalizeAudioTranscribeEngine(engine)) {
      case 'multimodal_llm':
        return labels.multimodalLlm;
      default:
        return labels.whisper;
    }
  }

  String _audioWhisperModelTitle(BuildContext context) {
    return context
        .t.settings.mediaAnnotation.audioTranscribe.whisperModel.title;
  }

  String _audioWhisperModelLabel(BuildContext context, String model) {
    final labels =
        context.t.settings.mediaAnnotation.audioTranscribe.whisperModel.labels;
    return switch (normalizeAudioTranscribeWhisperModel(model)) {
      'tiny' => labels.tiny,
      'base' => labels.base,
      'small' => labels.small,
      'medium' => labels.medium,
      'large-v3-turbo' => labels.largeV3Turbo,
      'large-v3' => labels.largeV3,
      _ => normalizeAudioTranscribeWhisperModel(model),
    };
  }

  String _audioWhisperModelSubtitle(BuildContext context) {
    final whisperModel =
        context.t.settings.mediaAnnotation.audioTranscribe.whisperModel;

    if (_audioWhisperModelDownloading) {
      final targetModel = normalizeAudioTranscribeWhisperModel(
        _audioWhisperModelDownloadingTarget ?? _audioWhisperModel,
      );
      final targetLabel = _audioWhisperModelLabel(context, targetModel);
      final received = _audioWhisperModelDownloadReceivedBytes;
      final total = _audioWhisperModelDownloadTotalBytes;

      final receivedLabel = _formatWhisperModelByteSize(received);
      if (total != null && total > 0) {
        final percent =
            ((received / total) * 100).clamp(0, 100).toStringAsFixed(1);
        final totalLabel = _formatWhisperModelByteSize(total);
        return whisperModel.downloadingWithTotal(
          modelLabel: targetLabel,
          percent: percent,
          received: receivedLabel,
          total: totalLabel,
        );
      }

      return whisperModel.downloading(
        modelLabel: targetLabel,
        received: receivedLabel,
      );
    }

    return whisperModel.subtitle;
  }

  String _audioWhisperRuntimeCardTitle(BuildContext context) {
    return context
        .t.settings.mediaAnnotation.audioTranscribe.localRuntime.title;
  }

  String _audioWhisperRuntimeCardDescription(BuildContext context) {
    final localRuntime =
        context.t.settings.mediaAnnotation.audioTranscribe.localRuntime;
    if (_supportsMobileWhisperRuntimeDownload()) {
      return localRuntime.descriptionMobile;
    }
    return localRuntime.descriptionDesktop;
  }

  String _audioWhisperRuntimeStatusLabel(BuildContext context) {
    final statusSummary = context
        .t.settings.mediaAnnotation.audioTranscribe.localRuntime.statusSummary;
    if (_audioWhisperModelDownloading) {
      return statusSummary.downloading;
    }
    if (!_audioWhisperRuntimeStatusReady) {
      return statusSummary.checking;
    }
    if (_audioWhisperRuntimeInstalled) {
      return statusSummary.installed;
    }
    return statusSummary.missing;
  }

  String _audioWhisperRuntimeStatusSubtitle(BuildContext context) {
    final statusDetails = context
        .t.settings.mediaAnnotation.audioTranscribe.localRuntime.statusDetails;
    if (_audioWhisperModelDownloading) {
      return _audioWhisperModelSubtitle(context);
    }
    if (!_audioWhisperRuntimeStatusReady) {
      return statusDetails.checking;
    }
    final error = _audioWhisperRuntimeStatusError;
    if (error != null) {
      return statusDetails.error(error: '$error');
    }
    if (_audioWhisperRuntimeInstalled) {
      final modelLabel = _audioWhisperModelLabel(context, _audioWhisperModel);
      return statusDetails.installed(modelLabel: modelLabel);
    }
    return statusDetails.missing;
  }

  Future<void> _pickAudioWhisperModel() async {
    if (_busy) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value = normalizeAudioTranscribeWhisperModel(_audioWhisperModel);

        Widget option(
          String model,
          void Function(void Function()) setInnerState,
        ) {
          return RadioListTile<String>(
            value: model,
            groupValue: value,
            title: Text(_audioWhisperModelLabel(context, model)),
            onChanged: (next) {
              if (next == null) return;
              setInnerState(() => value = next);
            },
          );
        }

        return AlertDialog(
          title: Text(_audioWhisperModelTitle(context)),
          content: StatefulBuilder(
            builder: (context, setInnerState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final model in audioTranscribeWhisperModelOptions)
                      option(model, setInnerState),
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
    await _setAudioWhisperModel(selected);
  }

  Future<void> _pickAudioTranscribeEngine(
    ContentEnrichmentConfig config,
  ) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.audioTranscribe.engine;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value =
            normalizeAudioTranscribeEngine(config.audioTranscribeEngine);
        if (value == 'local_runtime') {
          value = 'whisper';
        }

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
