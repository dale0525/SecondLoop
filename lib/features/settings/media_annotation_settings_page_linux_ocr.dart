part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageLinuxOcrExtension
    on _MediaAnnotationSettingsPageState {
  List<Widget> _buildDocumentOcrSection(
    BuildContext context,
    ContentEnrichmentConfig? contentConfig,
  ) {
    final t = context.t.settings.mediaAnnotation;
    final children = <Widget>[
      SwitchListTile(
        key: MediaAnnotationSettingsPage.ocrSwitchKey,
        title: Text(t.documentOcr.enabled.title),
        subtitle: Text(t.documentOcr.enabled.subtitle),
        value: contentConfig?.ocrEnabled ?? false,
        onChanged: _busy || contentConfig == null
            ? null
            : (value) async {
                await _persistContentConfig(
                  _copyContentConfig(contentConfig, ocrEnabled: value),
                );
              },
      ),
    ];

    final linuxTile = _buildLinuxOcrModelTile(context);
    if (linuxTile != null) {
      children.add(linuxTile);
    }

    return <Widget>[
      mediaAnnotationSectionTitle(context, t.documentOcr.title),
      const SizedBox(height: 8),
      mediaAnnotationSectionCard(children),
    ];
  }

  Widget? _buildLinuxOcrModelTile(BuildContext context) {
    final status = _linuxOcrModelStatus;
    if (!status.supported) return null;

    final t = context.t.settings.mediaAnnotation.documentOcr.linuxModels;
    final actionEnabled = !_busy && !_linuxOcrBusy;
    final statusText = _linuxOcrStatusLabel(context, status);
    final colorScheme = Theme.of(context).colorScheme;
    final showQualityWarning = !status.installed;

    return Padding(
      key: MediaAnnotationSettingsPage.linuxOcrModelTileKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant,
          ),
          color: colorScheme.surfaceVariant.withOpacity(0.45),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: colorScheme.primaryContainer,
                  ),
                  child: Icon(
                    Icons.model_training_outlined,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (status.installed)
                  Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 18,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              statusText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_linuxOcrBusy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(
                key: ValueKey(
                    'media_annotation_settings_linux_ocr_download_progress'),
                minHeight: 6,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
            ],
            if (showQualityWarning) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey(
                    'media_annotation_settings_linux_ocr_quality_warning'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: colorScheme.errorContainer.withOpacity(0.4),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _linuxOcrQualityWarning(context),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: MediaAnnotationSettingsPage
                      .linuxOcrModelDownloadButtonKey,
                  onPressed: actionEnabled ? _downloadLinuxOcrModels : null,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    status.installed
                        ? t.actions.redownload
                        : t.actions.download,
                  ),
                ),
                if (status.installed)
                  OutlinedButton.icon(
                    key: MediaAnnotationSettingsPage
                        .linuxOcrModelDeleteButtonKey,
                    onPressed: actionEnabled ? _deleteLinuxOcrModels : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(t.actions.delete),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _linuxOcrQualityWarning(BuildContext context) {
    final languageCode =
        Localizations.localeOf(context).languageCode.toLowerCase();
    if (languageCode.startsWith('zh')) {
      return '未下载模型时，桌面端 PDF/视频 OCR 识别效果会明显变差。';
    }
    return 'Without downloaded models, desktop PDF/video OCR quality will be noticeably worse.';
  }

  String _linuxOcrStatusLabel(
    BuildContext context,
    LinuxOcrModelStatus status,
  ) {
    final t = context.t.settings.mediaAnnotation.documentOcr.linuxModels.status;
    if (_linuxOcrBusy) return t.downloading;
    if (!status.installed) {
      if (_linuxOcrRuntimeMissing(status)) {
        final detail = _linuxOcrRuntimeMissingDetail(status);
        if (detail != null) {
          return '${t.runtimeMissing} ($detail)';
        }
        return t.runtimeMissing;
      }
      return t.notInstalled;
    }
    return t.installed(
      count: status.modelCount,
      size: _formatDataSize(status.totalBytes),
    );
  }

  Future<void> _downloadLinuxOcrModels() async {
    if (_busy || _linuxOcrBusy) return;
    _mutateState(() => _linuxOcrBusy = true);
    try {
      final next = await _linuxOcrModelStore.downloadModels();
      if (!mounted) return;
      _mutateState(() => _linuxOcrModelStatus = next);
      if (_linuxOcrRuntimeMissing(next)) {
        var message = context.t.settings.mediaAnnotation.documentOcr.linuxModels
            .status.runtimeMissing;
        final detail = _linuxOcrRuntimeMissingDetail(next);
        if (detail != null) {
          message = '$message ($detail)';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _mutateState(() => _linuxOcrBusy = false);
    }
  }

  bool _linuxOcrRuntimeMissing(LinuxOcrModelStatus status) {
    final message = status.message?.trim() ?? '';
    if (message.isEmpty) return false;
    return message.startsWith('runtime_missing');
  }

  String? _linuxOcrRuntimeMissingDetail(LinuxOcrModelStatus status) {
    final message = status.message?.trim() ?? '';
    const prefix = 'runtime_missing:';
    if (!message.startsWith(prefix)) return null;
    final detail = message.substring(prefix.length).trim();
    if (detail.isEmpty) return null;
    return detail;
  }

  Future<void> _deleteLinuxOcrModels() async {
    if (_busy || _linuxOcrBusy) return;
    final t = context
        .t.settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete;
    final confirmed = (await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(t.title),
              content: Text(t.body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(context.t.common.actions.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(t.confirm),
                ),
              ],
            );
          },
        )) ==
        true;
    if (!confirmed) return;

    _mutateState(() => _linuxOcrBusy = true);
    try {
      final next = await _linuxOcrModelStore.deleteModels();
      if (!mounted) return;
      _mutateState(() => _linuxOcrModelStatus = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _mutateState(() => _linuxOcrBusy = false);
    }
  }

  String _formatDataSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
