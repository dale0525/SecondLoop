part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageLinuxPdfCompressExtension
    on _MediaAnnotationSettingsPageState {
  Widget? _buildLinuxPdfCompressResourceTile(BuildContext context) {
    final status = _linuxPdfCompressResourceStatus;
    if (!status.supported) return null;

    final t = context.t.settings.mediaAnnotation.pdfCompression.linuxResources;
    final actionEnabled = !_busy && !_linuxPdfCompressBusy;
    final statusText = _linuxPdfCompressResourceStatusLabel(context, status);

    return Padding(
      key: MediaAnnotationSettingsPage.linuxPdfCompressResourceTileKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(t.subtitle),
          const SizedBox(height: 6),
          Text(
            statusText,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                key: MediaAnnotationSettingsPage
                    .linuxPdfCompressResourceDownloadButtonKey,
                onPressed:
                    actionEnabled ? _downloadLinuxPdfCompressResources : null,
                child: Text(
                  status.installed ? t.actions.redownload : t.actions.download,
                ),
              ),
              if (status.installed)
                OutlinedButton(
                  key: MediaAnnotationSettingsPage
                      .linuxPdfCompressResourceDeleteButtonKey,
                  onPressed:
                      actionEnabled ? _deleteLinuxPdfCompressResources : null,
                  child: Text(t.actions.delete),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _linuxPdfCompressResourceStatusLabel(
    BuildContext context,
    LinuxPdfCompressResourceStatus status,
  ) {
    final t =
        context.t.settings.mediaAnnotation.pdfCompression.linuxResources.status;
    if (_linuxPdfCompressBusy) return t.downloading;
    if (!status.installed) return t.notInstalled;
    return t.installed(
      count: status.fileCount,
      size: _formatLinuxPdfResourceSize(status.totalBytes),
    );
  }

  Future<void> _downloadLinuxPdfCompressResources() async {
    if (_busy || _linuxPdfCompressBusy) return;
    _mutateState(() => _linuxPdfCompressBusy = true);
    try {
      final next = await _linuxPdfCompressResourceStore.downloadResources();
      if (!mounted) return;
      _mutateState(() => _linuxPdfCompressResourceStatus = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _mutateState(() => _linuxPdfCompressBusy = false);
    }
  }

  Future<void> _deleteLinuxPdfCompressResources() async {
    if (_busy || _linuxPdfCompressBusy) return;
    final t = context
        .t.settings.mediaAnnotation.pdfCompression.linuxResources.confirmDelete;
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

    _mutateState(() => _linuxPdfCompressBusy = true);
    try {
      final next = await _linuxPdfCompressResourceStore.deleteResources();
      if (!mounted) return;
      _mutateState(() => _linuxPdfCompressResourceStatus = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _mutateState(() => _linuxPdfCompressBusy = false);
    }
  }

  String _formatLinuxPdfResourceSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
