part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageLinuxOcrExtension
    on _MediaAnnotationSettingsPageState {
  List<Widget> _buildDocumentOcrSection(
    BuildContext context, {
    required bool showWifiOnly,
    required MediaAnnotationConfig mediaConfig,
  }) {
    final t = context.t.settings.mediaAnnotation;
    if (showWifiOnly) {
      final sourceLabels =
          context.t.settings.aiSelection.mediaUnderstanding.preference;
      final ocrRoute = _resolveCapabilityRoute(_ocrSourcePreference);
      return <Widget>[
        mediaAnnotationCapabilityCard(
          key: const ValueKey('media_annotation_settings_ocr_card'),
          context: context,
          title: t.documentOcr.title,
          description: t.documentOcr.enabled.subtitle,
          statusLabel: _capabilityRouteLabel(ocrRoute),
          actions: [
            _buildSourcePreferenceTile(
              value: MediaSourcePreference.auto,
              groupValue: _ocrSourcePreference,
              onChanged: _setOcrSourcePreference,
              tileKey:
                  const ValueKey('media_annotation_settings_ocr_mode_auto'),
              title: sourceLabels.auto.title,
              subtitle: sourceLabels.auto.description,
            ),
            _buildSourcePreferenceTile(
              value: MediaSourcePreference.cloud,
              groupValue: _ocrSourcePreference,
              onChanged: _setOcrSourcePreference,
              tileKey:
                  const ValueKey('media_annotation_settings_ocr_mode_cloud'),
              title: sourceLabels.cloud.title,
              subtitle: sourceLabels.cloud.description,
            ),
            _buildSourcePreferenceTile(
              value: MediaSourcePreference.byok,
              groupValue: _ocrSourcePreference,
              onChanged: _setOcrSourcePreference,
              tileKey:
                  const ValueKey('media_annotation_settings_ocr_mode_byok'),
              title: sourceLabels.byok.title,
              subtitle: sourceLabels.byok.description,
            ),
            _buildSourcePreferenceTile(
              value: MediaSourcePreference.local,
              groupValue: _ocrSourcePreference,
              onChanged: _setOcrSourcePreference,
              tileKey:
                  const ValueKey('media_annotation_settings_ocr_mode_local'),
              title: sourceLabels.local.title,
              subtitle: sourceLabels.local.description,
            ),
            _buildScopedWifiOnlyTile(
              tileKey: MediaAnnotationSettingsPage.ocrWifiOnlySwitchKey,
              wifiOnly: _ocrWifiOnly,
              onChanged: (wifiOnly) => _setCapabilityWifiOnly(
                scope: MediaCapabilityWifiScope.documentOcr,
                wifiOnly: wifiOnly,
              ),
            ),
            _buildOpenApiKeysTile(
              tileKey:
                  const ValueKey('media_annotation_settings_ocr_open_api_keys'),
            ),
          ],
        ),
      ];
    }

    final contentConfig = _contentConfig;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final proUser = subscriptionStatus == SubscriptionStatus.entitled;
    final cloudEnabled = mediaConfig.providerMode ==
        _MediaAnnotationSettingsPageState._kProviderCloudGateway;
    final children = <Widget>[
      ListTile(
        title: Text(t.documentOcr.enabled.title),
        subtitle: Text(t.documentOcr.enabled.subtitle),
      ),
      if (contentConfig != null)
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
    return <Widget>[
      mediaAnnotationSectionTitle(context, t.documentOcr.title),
      const SizedBox(height: 8),
      mediaAnnotationSectionCard(children),
    ];
  }

  Widget? _buildDesktopRuntimeHealthTile(BuildContext context) {
    final status = _linuxOcrModelStatus;

    final actionEnabled = !_busy && !_linuxOcrBusy && status.supported;
    final colorScheme = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final statusIcon = !status.supported
        ? Icons.info_outline
        : (status.installed ? Icons.check_circle : Icons.error_outline);
    final statusIconColor = !status.supported
        ? colorScheme.secondary
        : (status.installed ? colorScheme.primary : colorScheme.error);
    final statusLabel = _desktopRuntimeStatusLabel(context, status);

    return mediaAnnotationCapabilityCard(
      key: MediaAnnotationSettingsPage.linuxOcrModelTileKey,
      context: context,
      title: zh ? '本地能力引擎' : 'Local Capability Engine',
      description: isMacOS
          ? (zh
              ? 'macOS 默认优先使用系统原生 STT；此处展示共享 runtime 状态（与 OCR 共用）。'
              : 'macOS prefers native STT by default; this shows shared runtime health (also used by OCR).')
          : (zh
              ? '本地转写与 OCR 共用同一套桌面 runtime，可在此修复或清理。'
              : 'Local transcription and OCR share this desktop runtime. You can repair or clear it here.'),
      statusLabel: _desktopRuntimeSummaryLabel(context, status),
      actions: [
        ListTile(
          key: const ValueKey(
            'media_annotation_settings_local_capability_status_tile',
          ),
          title: Text(zh ? '运行时状态' : 'Runtime status'),
          subtitle: Text(statusLabel),
          trailing: Icon(
            statusIcon,
            color: statusIconColor,
            size: 18,
          ),
        ),
        if (_linuxOcrBusy)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: LinearProgressIndicator(
              key: ValueKey(
                'media_annotation_settings_linux_ocr_download_progress',
              ),
              minHeight: 6,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: MediaAnnotationSettingsPage.linuxOcrModelDownloadButtonKey,
                onPressed: actionEnabled ? _downloadLinuxOcrModels : null,
                icon: const Icon(Icons.build_circle_outlined),
                label: Text(
                  zh ? '修复安装' : 'Repair Install',
                ),
              ),
              if (status.installed && status.supported)
                OutlinedButton.icon(
                  key: MediaAnnotationSettingsPage.linuxOcrModelDeleteButtonKey,
                  onPressed: actionEnabled ? _deleteLinuxOcrModels : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(zh ? '清除运行时' : 'Clear Runtime'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _desktopRuntimeSummaryLabel(
    BuildContext context,
    LinuxOcrModelStatus status,
  ) {
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    if (_linuxOcrBusy) {
      return zh ? '状态：修复中' : 'Status: repairing';
    }
    if (!status.supported) {
      return zh ? '状态：不可用' : 'Status: unavailable';
    }
    if (!status.installed) {
      return zh ? '状态：未安装' : 'Status: runtime missing';
    }
    return zh ? '状态：健康' : 'Status: healthy';
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
    if (!status.supported) {
      return Localizations.localeOf(context)
              .languageCode
              .toLowerCase()
              .startsWith('zh')
          ? '当前无法读取本地 runtime 状态。可先尝试“修复安装”。'
          : 'Runtime status unavailable right now. Try Repair Install first.';
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
              title: Text(zh ? '清除本地运行时' : 'Clear Local Runtime'),
              content: Text(
                zh
                    ? '清除后会删除本地 OCR/转写共用的桌面 runtime 文件。'
                    : 'This removes shared desktop runtime files used by local OCR/transcription.',
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
