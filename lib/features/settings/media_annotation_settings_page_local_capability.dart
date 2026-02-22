part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageLocalCapabilityExtension
    on _MediaAnnotationSettingsPageState {
  void _scheduleInitialLocalCapabilityCardFocus() {
    if (_didRunLocalCapabilityCardFocus) return;
    if (!widget.focusLocalCapabilityCard) return;
    _didRunLocalCapabilityCardFocus = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToLocalCapabilityCard());
    });
  }

  bool _shouldShowDesktopLocalCapabilityCard() {
    final platform = Theme.of(context).platform;
    return platform != TargetPlatform.android && platform != TargetPlatform.iOS;
  }

  BuildContext? _localCapabilityCardFocusContext() {
    if (_shouldShowWhisperRuntimeCard()) {
      return _localCapabilityCardAnchorKey.currentContext;
    }
    if (_shouldShowDesktopLocalCapabilityCard()) {
      return _desktopLocalCapabilityCardAnchorKey.currentContext;
    }
    return null;
  }

  bool _expectsLocalCapabilityCardFocusTarget() {
    return _shouldShowWhisperRuntimeCard() ||
        _shouldShowDesktopLocalCapabilityCard();
  }

  Future<void> _scrollToLocalCapabilityCard({int attempt = 0}) async {
    if (!mounted) return;

    final targetContext = _localCapabilityCardFocusContext();
    if (targetContext == null) {
      if (!_expectsLocalCapabilityCardFocusTarget() || attempt >= 90) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_scrollToLocalCapabilityCard(attempt: attempt + 1));
      });
      return;
    }

    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration:
          disableAnimations ? Duration.zero : const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    _activateLocalCapabilityCardHighlight(disableAnimations: disableAnimations);
  }

  void _activateLocalCapabilityCardHighlight(
      {required bool disableAnimations}) {
    _clearLocalCapabilityCardHighlightTimer?.cancel();
    _mutateState(() => _highlightLocalCapabilityCard = true);
    if (disableAnimations) return;

    _clearLocalCapabilityCardHighlightTimer =
        Timer(const Duration(milliseconds: 1400), () {
      if (!mounted || !_highlightLocalCapabilityCard) return;
      _mutateState(() => _highlightLocalCapabilityCard = false);
    });
  }

  bool _supportsMobileWhisperRuntimeDownload() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool _shouldShowWhisperRuntimeCard() {
    final store = _audioWhisperModelStore;
    return store.supportsRuntimeDownload &&
        _supportsMobileWhisperRuntimeDownload();
  }

  Future<bool?> _safeIsAudioWhisperModelAvailable(
      {required String model}) async {
    final store = _audioWhisperModelStore;
    if (!_shouldShowWhisperRuntimeCard()) return null;
    try {
      return await store.isModelAvailable(model: model);
    } catch (error) {
      _mutateState(() {
        _audioWhisperRuntimeStatusReady = true;
        _audioWhisperRuntimeStatusError = error;
      });
      return null;
    }
  }

  Future<void> _downloadAudioWhisperRuntime() async {
    if (_busy || _audioWhisperModelDownloading) return;
    if (!_shouldShowWhisperRuntimeCard()) return;

    final messenger = ScaffoldMessenger.of(context);
    final normalizedModel = normalizeAudioTranscribeWhisperModel(
      _audioWhisperModel,
    );

    _mutateState(() {
      _busy = true;
      _audioWhisperModelDownloading = true;
      _audioWhisperModelDownloadingTarget = normalizedModel;
      _audioWhisperModelDownloadReceivedBytes = 0;
      _audioWhisperModelDownloadTotalBytes = null;
    });

    try {
      final result = await _audioWhisperModelStore.ensureModelAvailable(
        model: normalizedModel,
        onProgress: _onAudioWhisperModelDownloadProgress,
      );
      final installed = await _safeIsAudioWhisperModelAvailable(
        model: normalizedModel,
      );

      if (!mounted) return;
      _mutateState(() {
        _audioWhisperRuntimeInstalled = installed ??
            result.status == AudioWhisperModelEnsureStatus.downloaded ||
                result.status == AudioWhisperModelEnsureStatus.alreadyAvailable;
        _audioWhisperRuntimeStatusReady = true;
        _audioWhisperRuntimeStatusError = null;
      });

      if (result.status == AudioWhisperModelEnsureStatus.downloaded) {
        final zh = Localizations.localeOf(context)
            .languageCode
            .toLowerCase()
            .startsWith('zh');
        final modelLabel = _audioWhisperModelLabel(context, normalizedModel);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              zh
                  ? '已下载 $modelLabel 模型，可用于本地转写。'
                  : 'Downloaded $modelLabel for local transcription.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      _mutateState(() {
        _audioWhisperRuntimeInstalled = false;
        _audioWhisperRuntimeStatusReady = true;
        _audioWhisperRuntimeStatusError = error;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$error')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _mutateState(() {
        _busy = false;
        _audioWhisperModelDownloading = false;
        _audioWhisperModelDownloadingTarget = null;
        _audioWhisperModelDownloadReceivedBytes = 0;
        _audioWhisperModelDownloadTotalBytes = null;
      });
    }
  }
}
