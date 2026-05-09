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
      final requiredMediaConfig =
          RequiredAiCapabilityPolicy.requireMediaAnnotationConfig(mediaConfig);
      final requiredContentConfig =
          RequiredAiCapabilityPolicy.requireContentEnrichmentConfig(
        contentConfig,
      );
      await _store.write(sessionKey, requiredMediaConfig);
      await _contentStore.writeContentEnrichment(
        sessionKey,
        requiredContentConfig,
      );
      if (!mounted) return;
      _mutateState(() {
        _config = requiredMediaConfig;
        _contentConfig = requiredContentConfig;
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

  String _mediaUnderstandingTitle(BuildContext context) {
    return context.t.settings.mediaAnnotation.legacyEntry.title;
  }

  String _mediaUnderstandingSubtitle(BuildContext context) {
    return context.t.settings.mediaAnnotation.legacyEntry.subtitle;
  }

  String _mediaUnderstandingWifiOnlyTitle(BuildContext context) {
    return context.t.settings.mediaAnnotation.legacyEntry.wifiOnlyTitle;
  }

  String _mediaUnderstandingWifiOnlySubtitle(BuildContext context) {
    return context.t.settings.mediaAnnotation.legacyEntry.wifiOnlySubtitle;
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
}
