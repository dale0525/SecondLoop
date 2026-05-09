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
                        ? t.providerMode.labels.cloudGateway
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
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      return null;
    }

    final status = _linuxOcrModelStatus;

    final mediaAnnotation = context.t.settings.mediaAnnotation;
    final localCapability = mediaAnnotation.localCapability;
    final actionEnabled = !_busy && !_linuxOcrBusy && status.supported;
    final colorScheme = Theme.of(context).colorScheme;
    final isMacOS = platform == TargetPlatform.macOS;
    final isWindows = platform == TargetPlatform.windows;
    final statusIcon = !status.supported
        ? Icons.info_outline
        : (status.installed ? Icons.check_circle : Icons.error_outline);
    final statusIconColor = !status.supported
        ? colorScheme.secondary
        : (status.installed ? colorScheme.primary : colorScheme.error);
    final statusLabel = _desktopRuntimeStatusLabel(context, status);

    return mediaAnnotationCapabilityCard(
      key: MediaAnnotationSettingsPage.linuxOcrModelTileKey,
      anchorKey: _desktopLocalCapabilityCardAnchorKey,
      context: context,
      title: localCapability.title,
      description: isMacOS
          ? localCapability.descriptionMacos
          : isWindows
              ? localCapability.descriptionWindows
              : localCapability.descriptionDesktop,
      statusLabel: _desktopRuntimeSummaryLabel(context, status),
      actions: [
        ListTile(
          key: const ValueKey(
            'media_annotation_settings_local_capability_status_tile',
          ),
          title: Text(localCapability.runtimeStatusTitle),
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
                label: Text(localCapability.actions.repairInstall),
              ),
              if (status.installed && status.supported)
                OutlinedButton.icon(
                  key: MediaAnnotationSettingsPage.linuxOcrModelDeleteButtonKey,
                  onPressed: actionEnabled ? _deleteLinuxOcrModels : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(localCapability.actions.clearRuntime),
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
    final isWindows = Theme.of(context).platform == TargetPlatform.windows;
    final statusText =
        context.t.settings.mediaAnnotation.localCapability.statusSummary;
    if (_linuxOcrBusy) {
      return statusText.repairing;
    }
    if (!status.supported) {
      return statusText.unavailable;
    }
    if (!status.installed) {
      return statusText.runtimeMissing;
    }
    if (isWindows) {
      return statusText.ocrRuntimeHealthy;
    }
    return statusText.healthy;
  }

  String _desktopRuntimeStatusLabel(
    BuildContext context,
    LinuxOcrModelStatus status,
  ) {
    final isWindows = Theme.of(context).platform == TargetPlatform.windows;
    final details =
        context.t.settings.mediaAnnotation.localCapability.statusDetails;
    if (_linuxOcrBusy) {
      return details.repairing;
    }
    if (!status.supported) {
      return details.unavailable;
    }
    if (!status.installed) {
      final reason = status.message?.trim();
      final mapped = _desktopRuntimeMissingReasonLabel(reason: reason);
      if (mapped != null) return mapped;
      if (reason != null && reason.isNotEmpty) {
        return details.runtimeMissingReason(reason: reason);
      }
      return details.runtimeMissing;
    }
    final size = _formatDataSize(status.totalBytes);
    if (isWindows) {
      return details.ocrRuntimeHealthy(count: status.modelCount, size: size);
    }
    return details.healthy(count: status.modelCount, size: size);
  }

  String? _desktopRuntimeMissingReasonLabel({
    required String? reason,
  }) {
    if (reason == null || reason.isEmpty) return null;
    final details =
        context.t.settings.mediaAnnotation.localCapability.statusDetails;
    if (reason == 'runtime_payload_incomplete') {
      return details.runtimeIncomplete;
    }
    if (reason == 'runtime_missing' || reason == 'runtime_not_initialized') {
      return details.runtimeMissing;
    }
    return null;
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
    final isWindows = Theme.of(context).platform == TargetPlatform.windows;
    final confirmDelete =
        context.t.settings.mediaAnnotation.localCapability.confirmDelete;
    final confirmed = (await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(confirmDelete.title),
              content: Text(
                isWindows
                    ? confirmDelete.bodyWindows
                    : confirmDelete.bodyDesktop,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(context.t.common.actions.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(confirmDelete.confirm),
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
