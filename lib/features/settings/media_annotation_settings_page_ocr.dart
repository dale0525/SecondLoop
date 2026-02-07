part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageOcrExtension
    on _MediaAnnotationSettingsPageState {
  String _audioTranscribeEngineLabel(BuildContext context, String engine) {
    final labels =
        context.t.settings.mediaAnnotation.audioTranscribe.engine.labels;
    switch (engine.trim()) {
      case 'multimodal_llm':
        return labels.multimodalLlm;
      default:
        return labels.whisper;
    }
  }

  String _ocrLanguageLabel(BuildContext context, String hints) {
    final labels =
        context.t.settings.mediaAnnotation.documentOcr.languageHints.labels;
    switch (hints.trim()) {
      case 'en':
        return labels.en;
      case 'zh_en':
        return labels.zhEn;
      case 'ja_en':
        return labels.jaEn;
      case 'ko_en':
        return labels.koEn;
      case 'fr_en':
        return labels.frEn;
      case 'de_en':
        return labels.deEn;
      case 'es_en':
        return labels.esEn;
      case 'device_plus_en':
      default:
        return labels.devicePlusEn;
    }
  }

  String _ocrAutoMaxPagesLabel(BuildContext context, int value) {
    final t = context.t.settings.mediaAnnotation.documentOcr.pdfAutoMaxPages;
    if (value <= 0) return t.manualOnly;
    return t.pages(count: value);
  }

  Future<void> _pickOcrLanguageHints(ContentEnrichmentConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.documentOcr.languageHints;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value = config.ocrLanguageHints.trim();
        const allowed = <String>{
          'device_plus_en',
          'en',
          'zh_en',
          'ja_en',
          'ko_en',
          'fr_en',
          'de_en',
          'es_en',
        };
        if (!allowed.contains(value)) value = 'device_plus_en';

        Widget option(String mode, String title,
            void Function(void Function()) setInnerState) {
          return RadioListTile<String>(
            value: mode,
            groupValue: value,
            title: Text(title),
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
              final labels = t.labels;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    option(
                        'device_plus_en', labels.devicePlusEn, setInnerState),
                    option('en', labels.en, setInnerState),
                    option('zh_en', labels.zhEn, setInnerState),
                    option('ja_en', labels.jaEn, setInnerState),
                    option('ko_en', labels.koEn, setInnerState),
                    option('fr_en', labels.frEn, setInnerState),
                    option('de_en', labels.deEn, setInnerState),
                    option('es_en', labels.esEn, setInnerState),
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
    if (selected == config.ocrLanguageHints.trim()) return;
    await _persistContentConfig(
      _copyContentConfig(config, ocrLanguageHints: selected),
    );
  }

  Future<void> _pickOcrPdfDpi(ContentEnrichmentConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.documentOcr.pdfDpi;

    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        var value = config.ocrPdfDpi.toInt().clamp(72, 600);
        const options = <int>[120, 150, 180, 220, 300];

        return AlertDialog(
          title: Text(t.title),
          content: StatefulBuilder(
            builder: (context, setInnerState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final dpi in options)
                      RadioListTile<int>(
                        value: dpi,
                        groupValue: value,
                        title: Text(t.value(dpi: dpi)),
                        onChanged: (next) {
                          if (next == null) return;
                          setInnerState(() => value = next);
                        },
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
    if (selected == config.ocrPdfDpi.toInt()) return;
    await _persistContentConfig(
      _copyContentConfig(config, ocrPdfDpi: selected),
    );
  }

  Future<void> _pickOcrAutoMaxPages(ContentEnrichmentConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.documentOcr.pdfAutoMaxPages;

    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        var value = config.ocrPdfAutoMaxPages.toInt().clamp(0, 1000);
        const options = <int>[0, 10, 20, 30, 50, 100];

        return AlertDialog(
          title: Text(t.title),
          content: StatefulBuilder(
            builder: (context, setInnerState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final pages in options)
                      RadioListTile<int>(
                        value: pages,
                        groupValue: value,
                        title: Text(
                          pages == 0 ? t.manualOnly : t.pages(count: pages),
                        ),
                        onChanged: (next) {
                          if (next == null) return;
                          setInnerState(() => value = next);
                        },
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
    if (selected == config.ocrPdfAutoMaxPages.toInt()) return;
    await _persistContentConfig(
      _copyContentConfig(config, ocrPdfAutoMaxPages: selected),
    );
  }

  Future<void> _pickAudioTranscribeEngine(
      ContentEnrichmentConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.audioTranscribe.engine;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value = config.audioTranscribeEngine.trim();
        if (value != 'whisper' && value != 'multimodal_llm') {
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
    if (selected == config.audioTranscribeEngine.trim()) return;
    await _persistContentConfig(
      _copyContentConfig(config, audioTranscribeEngine: selected),
    );
  }

  Future<void> _openAudioTranscribeConfigHelp() async {
    final t = context.t.settings.mediaAnnotation.audioTranscribe.configureApi;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.title),
          content: Text(t.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.t.common.actions.cancel),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CloudAccountPage()),
                );
              },
              child: Text(t.openCloud),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
                );
              },
              child: Text(t.openApiKeys),
            ),
          ],
        );
      },
    );
  }
}
