part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageLinuxPdfCompressExtension
    on _MediaAnnotationSettingsPageState {
  // ignore: unused_element
  Widget? _buildLinuxPdfCompressResourceTile(BuildContext context) {
    final status = _linuxPdfCompressResourceStatus;
    if (!status.supported) return null;

    final actionEnabled = !_busy && !_linuxPdfCompressBusy;
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');

    return Padding(
      key: MediaAnnotationSettingsPage.linuxPdfCompressResourceTileKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            zh ? '桌面 PDF 压缩运行时' : 'Desktop PDF Compression Runtime',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            zh
                ? '用于离线 PDF 智能压缩的运行时状态。'
                : 'Health status for offline PDF smart compression runtime.',
          ),
          const SizedBox(height: 6),
          Text(
            _linuxPdfCompressResourceStatusLabel(context, status),
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
                child: Text(zh ? '修复安装' : 'Repair Install'),
              ),
              if (status.installed)
                OutlinedButton(
                  key: MediaAnnotationSettingsPage
                      .linuxPdfCompressResourceDeleteButtonKey,
                  onPressed:
                      actionEnabled ? _deleteLinuxPdfCompressResources : null,
                  child: Text(zh ? '清除运行时' : 'Clear Runtime'),
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
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    if (_linuxPdfCompressBusy) {
      return zh ? '正在修复运行时...' : 'Repairing runtime...';
    }
    if (!status.installed) {
      final reason = status.message?.trim();
      if (reason != null && reason.isNotEmpty) {
        return zh ? '运行时缺失（$reason）' : 'Runtime missing ($reason)';
      }
      return zh ? '运行时缺失' : 'Runtime missing';
    }
    return zh
        ? '运行时健康（${status.fileCount} 文件, ${_formatLinuxPdfResourceSize(status.totalBytes)}）'
        : 'Runtime healthy (${status.fileCount} files, ${_formatLinuxPdfResourceSize(status.totalBytes)})';
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
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    final confirmed = (await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(zh ? '清除桌面运行时' : 'Clear Desktop Runtime'),
              content: Text(
                zh
                    ? '清除后会删除已安装的桌面 OCR/PDF 运行时文件。'
                    : 'This removes installed desktop OCR/PDF runtime files.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(context.t.common.actions.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(zh ? '确认清除' : 'Clear Runtime'),
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
