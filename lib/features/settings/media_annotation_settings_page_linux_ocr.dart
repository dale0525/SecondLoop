part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageLinuxOcrExtension
    on _MediaAnnotationSettingsPageState {
  List<Widget> _buildDocumentOcrSection(
    BuildContext context,
  ) {
    final t = context.t.settings.mediaAnnotation;
    final contentConfig = _contentConfig;
    final mediaConfig = _config;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final proUser = subscriptionStatus == SubscriptionStatus.entitled;
    final cloudEnabled = mediaConfig?.providerMode ==
        _MediaAnnotationSettingsPageState._kProviderCloudGateway;
    final children = <Widget>[
      ListTile(
        title: Text(t.documentOcr.enabled.title),
        subtitle: Text(t.documentOcr.enabled.subtitle),
      ),
      if (contentConfig != null && mediaConfig != null)
        ListTile(
          key: MediaAnnotationSettingsPage.ocrModeTileKey,
          title: Text(_documentOcrEngineTitle(context)),
          subtitle: Text(
            _documentOcrEngineSubtitle(
              context,
              proUser: proUser,
              cloudEnabled: cloudEnabled,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                proUser
                    ? (cloudEnabled
                        ? (_isZhOcrLocale(context)
                            ? 'SecondLoop Cloud'
                            : 'SecondLoop Cloud')
                        : _documentOcrEngineLabel(
                            context,
                            contentConfig.ocrEngineMode,
                          ))
                    : _documentOcrEngineLabel(
                        context,
                        contentConfig.ocrEngineMode,
                      ),
              ),
              if (!proUser) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ],
          ),
          onTap: _busy || proUser
              ? null
              : () => _pickDocumentOcrEngineMode(contentConfig, mediaConfig),
        ),
    ];

    final runtimeTile = _buildDesktopRuntimeHealthTile(context);
    if (runtimeTile != null) {
      children.add(runtimeTile);
    }

    return <Widget>[
      mediaAnnotationSectionTitle(context, t.documentOcr.title),
      const SizedBox(height: 8),
      mediaAnnotationSectionCard(children),
    ];
  }

  Widget? _buildDesktopRuntimeHealthTile(BuildContext context) {
    final status = _linuxOcrModelStatus;
    if (!status.supported) return null;

    final actionEnabled = !_busy && !_linuxOcrBusy;
    final colorScheme = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');

    return Padding(
      key: MediaAnnotationSettingsPage.linuxOcrModelTileKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
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
                    Icons.health_and_safety_outlined,
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
                        zh ? '桌面 OCR 运行时' : 'Desktop OCR Runtime',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        zh
                            ? '用于离线 OCR 的内置运行时状态。'
                            : 'Health status for bundled offline OCR runtime.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  status.installed ? Icons.check_circle : Icons.error_outline,
                  color: status.installed
                      ? colorScheme.primary
                      : colorScheme.error,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _desktopRuntimeStatusLabel(context, status),
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: MediaAnnotationSettingsPage
                      .linuxOcrModelDownloadButtonKey,
                  onPressed: actionEnabled ? _downloadLinuxOcrModels : null,
                  icon: const Icon(Icons.build_circle_outlined),
                  label: Text(
                    zh ? '修复安装' : 'Repair Install',
                  ),
                ),
                if (status.installed)
                  OutlinedButton.icon(
                    key: MediaAnnotationSettingsPage
                        .linuxOcrModelDeleteButtonKey,
                    onPressed: actionEnabled ? _deleteLinuxOcrModels : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(zh ? '清除运行时' : 'Clear Runtime'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _desktopRuntimeStatusLabel(
    BuildContext context,
    LinuxOcrModelStatus status,
  ) {
    if (_linuxOcrBusy) {
      return Localizations.localeOf(context)
              .languageCode
              .toLowerCase()
              .startsWith('zh')
          ? '正在修复运行时...'
          : 'Repairing runtime...';
    }
    if (!status.installed) {
      final reason = status.message?.trim();
      if (reason != null && reason.isNotEmpty) {
        return Localizations.localeOf(context)
                .languageCode
                .toLowerCase()
                .startsWith('zh')
            ? '运行时缺失（$reason）'
            : 'Runtime missing ($reason)';
      }
      return Localizations.localeOf(context)
              .languageCode
              .toLowerCase()
              .startsWith('zh')
          ? '运行时缺失'
          : 'Runtime missing';
    }
    final size = _formatDataSize(status.totalBytes);
    return Localizations.localeOf(context)
            .languageCode
            .toLowerCase()
            .startsWith('zh')
        ? '运行时健康（${status.modelCount} 文件, $size）'
        : 'Runtime healthy (${status.modelCount} files, $size)';
  }

  Future<void> _downloadLinuxOcrModels() async {
    if (_busy || _linuxOcrBusy) return;
    _mutateState(() => _linuxOcrBusy = true);
    try {
      final next = await _linuxOcrModelStore.downloadModels();
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

  Future<void> _deleteLinuxOcrModels() async {
    if (_busy || _linuxOcrBusy) return;
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
                    ? '清除后会删除已安装的桌面 OCR 运行时文件。'
                    : 'This removes installed desktop OCR runtime files.',
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
