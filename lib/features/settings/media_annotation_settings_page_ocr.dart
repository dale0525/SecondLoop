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
