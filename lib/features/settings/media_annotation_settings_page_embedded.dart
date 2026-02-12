part of 'media_annotation_settings_page.dart';

extension _MediaAnnotationSettingsPageEmbeddedExtension
    on _MediaAnnotationSettingsPageState {
  bool _isZhLocale(BuildContext context) {
    return Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
  }

  String _wifiOnlyTitle(BuildContext context) {
    return _isZhLocale(context) ? '仅Wi-Fi' : 'Wi-Fi only';
  }

  String _wifiOnlySubtitle(BuildContext context) {
    if (_isZhLocale(context)) {
      return '仅对 SecondLoop Cloud / BYOK 生效，本地能力不受此限制。';
    }
    return 'Only applies to SecondLoop Cloud and BYOK. Local capability is unaffected.';
  }

  bool _isCloudAvailableForCapability(BuildContext context) {
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    if (subscriptionStatus != SubscriptionStatus.entitled) {
      return false;
    }

    final cloudScope = CloudAuthScope.maybeOf(context);
    final hasGateway =
        (cloudScope?.gatewayConfig.baseUrl ?? '').trim().isNotEmpty;
    final hasCloudAccount =
        (cloudScope?.controller.uid ?? '').trim().isNotEmpty;
    return hasGateway && hasCloudAccount;
  }

  bool _hasOpenAiByokProfile() {
    final profiles = _llmProfiles;
    if (profiles == null) return false;
    return profiles
        .any((p) => p.isActive && p.providerType == 'openai-compatible');
  }

  MediaSourceRouteKind _resolveCapabilityRoute(
      MediaSourcePreference preference) {
    return resolveMediaSourceRoute(
      preference,
      cloudAvailable: _isCloudAvailableForCapability(context),
      hasByokProfile: _hasOpenAiByokProfile(),
    );
  }

  String _capabilityRouteLabel(MediaSourceRouteKind route) {
    final status = context.t.settings.aiSelection.mediaUnderstanding.status;
    return switch (route) {
      MediaSourceRouteKind.cloudGateway => status.cloud,
      MediaSourceRouteKind.byok => status.byok,
      MediaSourceRouteKind.local => status.local,
    };
  }

  Widget _buildOpenApiKeysTile({required Key tileKey}) {
    return ListTile(
      key: tileKey,
      title: Text(
          context.t.settings.aiSelection.mediaUnderstanding.actions.openByok),
      trailing: const Icon(Icons.chevron_right),
      onTap: _busy
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LlmProfilesPage(
                    providerFilter:
                        LlmProfilesProviderFilter.openAiCompatibleOnly,
                  ),
                ),
              );
            },
    );
  }

  Widget _buildScopedWifiOnlyTile({
    required Key tileKey,
    required bool wifiOnly,
    required Future<void> Function(bool wifiOnly) onChanged,
  }) {
    return SwitchListTile(
      key: tileKey,
      title: Text(_wifiOnlyTitle(context)),
      subtitle: Text(_wifiOnlySubtitle(context)),
      value: wifiOnly,
      onChanged: _busy
          ? null
          : (nextWifiOnly) async {
              await onChanged(nextWifiOnly);
            },
    );
  }

  Widget _buildSourcePreferenceTile({
    required MediaSourcePreference value,
    required MediaSourcePreference groupValue,
    required Future<void> Function(MediaSourcePreference next) onChanged,
    required Key tileKey,
    required String title,
    required String subtitle,
  }) {
    return RadioListTile<MediaSourcePreference>(
      key: tileKey,
      value: value,
      groupValue: groupValue,
      onChanged: _busy
          ? null
          : (next) {
              if (next == null) return;
              unawaited(onChanged(next));
            },
      title: Text(title),
      subtitle: Text(subtitle),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildAudioByokEngineTile(ContentEnrichmentConfig? contentConfig) {
    final t = context.t.settings.mediaAnnotation.audioTranscribe.engine;
    return ListTile(
      title: Text(t.title),
      subtitle: Text(
        contentConfig == null
            ? t.notAvailable
            : _audioTranscribeEngineLabel(
                context,
                contentConfig.audioTranscribeEngine,
              ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _busy || contentConfig == null
          ? null
          : () => _pickAudioByokEngine(contentConfig),
    );
  }

  Future<void> _pickAudioByokEngine(ContentEnrichmentConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.audioTranscribe.engine;
    final zh = _isZhLocale(context);

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value =
            normalizeAudioTranscribeEngine(config.audioTranscribeEngine);
        if (!isByokAudioTranscribeEngine(value)) {
          value = 'whisper';
        }

        return AlertDialog(
          title: Text(t.title),
          content: StatefulBuilder(
            builder: (context, setInnerState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      value: 'whisper',
                      groupValue: value,
                      title: Text(t.labels.whisper),
                      subtitle: Text(
                        zh
                            ? '通过 BYOK Whisper 能力执行转写。'
                            : 'Transcribe with BYOK Whisper capability.',
                      ),
                      onChanged: (next) {
                        if (next == null) return;
                        setInnerState(() => value = next);
                      },
                    ),
                    RadioListTile<String>(
                      value: 'multimodal_llm',
                      groupValue: value,
                      title: Text(t.labels.multimodalLlm),
                      subtitle: Text(
                        zh
                            ? '通过 BYOK 多模态模型执行转写。'
                            : 'Transcribe with BYOK multimodal model.',
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
    final normalizedSelected = normalizeAudioTranscribeEngine(selected);
    if (!isByokAudioTranscribeEngine(normalizedSelected)) return;
    if (normalizedSelected ==
        normalizeAudioTranscribeEngine(config.audioTranscribeEngine)) {
      return;
    }

    await _persistContentConfig(
      _copyContentConfig(
        config,
        audioTranscribeEngine: normalizedSelected,
      ),
    );
  }

  List<Widget> _buildSettingsChildren(BuildContext context) {
    final config = _config;
    final contentConfig = _contentConfig;
    final t = context.t.settings.mediaAnnotation;
    final embedded = widget.embedded;

    return [
      if (_loadError != null)
        SlSurface(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.t.errors.loadFailed(error: '$_loadError'),
          ),
        ),
      if (_contentLoadError != null)
        SlSurface(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.t.errors.loadFailed(error: '$_contentLoadError'),
          ),
        ),
      if (config == null && _loadError == null && !embedded)
        const Center(child: CircularProgressIndicator()),
      if (config != null)
        ...() {
          final mediaUnderstandingEnabled =
              _isMediaUnderstandingEnabled(config, contentConfig);
          final shouldShowDetailedSettings =
              embedded || mediaUnderstandingEnabled;
          final subscriptionStatus =
              SubscriptionScope.maybeOf(context)?.status ??
                  SubscriptionStatus.unknown;
          final showSecondLoopCloudSwitch =
              !embedded && subscriptionStatus == SubscriptionStatus.entitled;
          final useSecondLoopCloud = config.providerMode ==
              _MediaAnnotationSettingsPageState._kProviderCloudGateway;
          final sourceLabels =
              context.t.settings.aiSelection.mediaUnderstanding.preference;
          final audioRoute = _resolveCapabilityRoute(_audioSourcePreference);

          return <Widget>[
            if (!embedded) ...[
              mediaAnnotationSectionTitle(
                context,
                _mediaUnderstandingTitle(context),
              ),
              const SizedBox(height: 8),
              mediaAnnotationSectionCard([
                SwitchListTile(
                  key: MediaAnnotationSettingsPage.mediaUnderstandingSwitchKey,
                  title: Text(_mediaUnderstandingTitle(context)),
                  subtitle: Text(_mediaUnderstandingSubtitle(context)),
                  value: mediaUnderstandingEnabled,
                  onChanged: _busy || contentConfig == null
                      ? null
                      : (value) async {
                          await _setMediaUnderstandingEnabled(
                            enabled: value,
                            config: config,
                            contentConfig: contentConfig,
                          );
                        },
                ),
              ]),
            ],
            if (shouldShowDetailedSettings) ...[
              const SizedBox(height: 16),
              if (!embedded)
                mediaAnnotationSectionCard([
                  if (showSecondLoopCloudSwitch)
                    SwitchListTile(
                      key: MediaAnnotationSettingsPage
                          .useSecondLoopCloudSwitchKey,
                      title: Text(_useSecondLoopCloudTitle(context)),
                      subtitle: Text(_useSecondLoopCloudSubtitle(context)),
                      value: useSecondLoopCloud,
                      onChanged: _busy
                          ? null
                          : (value) async {
                              await _setUseSecondLoopCloudEnabled(
                                enabled: value,
                                config: config,
                              );
                            },
                    ),
                  SwitchListTile(
                    key: MediaAnnotationSettingsPage.wifiOnlySwitchKey,
                    title: Text(_mediaUnderstandingWifiOnlyTitle(context)),
                    subtitle:
                        Text(_mediaUnderstandingWifiOnlySubtitle(context)),
                    value: !config.allowCellular,
                    onChanged: _busy
                        ? null
                        : (wifiOnly) async {
                            await _setMediaUnderstandingWifiOnly(
                              wifiOnly: wifiOnly,
                              config: config,
                            );
                          },
                  ),
                ]),
              if (!embedded) const SizedBox(height: 16),
              if (embedded)
                mediaAnnotationCapabilityCard(
                  key: const ValueKey('media_annotation_settings_audio_card'),
                  context: context,
                  title: t.audioTranscribe.title,
                  description: t.audioTranscribe.enabled.subtitle,
                  statusLabel: _capabilityRouteLabel(audioRoute),
                  actions: [
                    _buildSourcePreferenceTile(
                      value: MediaSourcePreference.auto,
                      groupValue: _audioSourcePreference,
                      onChanged: _setAudioSourcePreference,
                      tileKey: const ValueKey(
                        'media_annotation_settings_audio_mode_auto',
                      ),
                      title: sourceLabels.auto.title,
                      subtitle: sourceLabels.auto.description,
                    ),
                    _buildSourcePreferenceTile(
                      value: MediaSourcePreference.cloud,
                      groupValue: _audioSourcePreference,
                      onChanged: _setAudioSourcePreference,
                      tileKey: const ValueKey(
                        'media_annotation_settings_audio_mode_cloud',
                      ),
                      title: sourceLabels.cloud.title,
                      subtitle: sourceLabels.cloud.description,
                    ),
                    _buildSourcePreferenceTile(
                      value: MediaSourcePreference.byok,
                      groupValue: _audioSourcePreference,
                      onChanged: _setAudioSourcePreference,
                      tileKey: const ValueKey(
                        'media_annotation_settings_audio_mode_byok',
                      ),
                      title: sourceLabels.byok.title,
                      subtitle: sourceLabels.byok.description,
                    ),
                    _buildSourcePreferenceTile(
                      value: MediaSourcePreference.local,
                      groupValue: _audioSourcePreference,
                      onChanged: _setAudioSourcePreference,
                      tileKey: const ValueKey(
                        'media_annotation_settings_audio_mode_local',
                      ),
                      title: sourceLabels.local.title,
                      subtitle: sourceLabels.local.description,
                    ),
                    _buildScopedWifiOnlyTile(
                      tileKey:
                          MediaAnnotationSettingsPage.audioWifiOnlySwitchKey,
                      wifiOnly: _audioWifiOnly,
                      onChanged: (wifiOnly) => _setCapabilityWifiOnly(
                        scope: MediaCapabilityWifiScope.audioTranscribe,
                        wifiOnly: wifiOnly,
                      ),
                    ),
                    _buildOpenApiKeysTile(
                      tileKey: const ValueKey(
                        'media_annotation_settings_audio_open_api_keys',
                      ),
                    ),
                    if (_audioSourcePreference == MediaSourcePreference.byok)
                      _buildAudioByokEngineTile(contentConfig),
                  ],
                )
              else ...[
                mediaAnnotationSectionTitle(context, t.audioTranscribe.title),
                const SizedBox(height: 8),
                mediaAnnotationSectionCard([
                  ListTile(
                    title: Text(t.audioTranscribe.enabled.title),
                    subtitle: Text(t.audioTranscribe.enabled.subtitle),
                  ),
                  ListTile(
                    title: Text(t.audioTranscribe.engine.title),
                    subtitle: Text(t.audioTranscribe.engine.subtitle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          contentConfig == null
                              ? t.audioTranscribe.engine.notAvailable
                              : _audioTranscribeEngineLabel(
                                  context,
                                  contentConfig.audioTranscribeEngine,
                                ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: _busy || contentConfig == null
                        ? null
                        : () => _pickAudioTranscribeEngine(contentConfig),
                  ),
                  ListTile(
                    key: MediaAnnotationSettingsPage.audioApiProfileTileKey,
                    title: Text(t.audioTranscribe.configureApi.title),
                    subtitle: Text(
                      _audioTranscribeApiProfileSubtitle(
                        context,
                        localRuntime: contentConfig != null &&
                            _isLocalRuntimeAudioTranscribeEngine(
                              contentConfig.audioTranscribeEngine,
                            ),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          contentConfig != null &&
                                  _isLocalRuntimeAudioTranscribeEngine(
                                    contentConfig.audioTranscribeEngine,
                                  )
                              ? (_isZhOcrLocale(context)
                                  ? '本地模式'
                                  : 'Local mode')
                              : _apiProfileLabel(context, config.byokProfileId),
                        ),
                        if (!(contentConfig != null &&
                            _isLocalRuntimeAudioTranscribeEngine(
                              contentConfig.audioTranscribeEngine,
                            ))) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right),
                        ],
                      ],
                    ),
                    onTap: _busy ||
                            (contentConfig != null &&
                                _isLocalRuntimeAudioTranscribeEngine(
                                  contentConfig.audioTranscribeEngine,
                                ))
                        ? null
                        : () => _pickApiProfileOverride(config),
                  ),
                ]),
              ],
              const SizedBox(height: 16),
              ..._buildDocumentOcrSection(
                context,
                showWifiOnly: embedded,
                mediaConfig: config,
              ),
              if (!embedded) ...[
                const SizedBox(height: 16),
                mediaAnnotationSectionTitle(
                  context,
                  t.providerSettings.title,
                ),
                const SizedBox(height: 8),
                mediaAnnotationSectionCard([
                  ListTile(
                    key: MediaAnnotationSettingsPage.imageApiProfileTileKey,
                    title: Text(t.byokProfile.title),
                    subtitle: Text(_imageApiProfileSubtitle(context)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_apiProfileLabel(context, config.byokProfileId)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: _busy ? null : () => _pickApiProfileOverride(config),
                  ),
                ]),
              ],
              ...() {
                final runtimeTile = _buildDesktopRuntimeHealthTile(context);
                if (runtimeTile == null) {
                  return const <Widget>[];
                }
                return <Widget>[
                  const SizedBox(height: 16),
                  runtimeTile,
                ];
              }(),
            ],
          ];
        }(),
    ];
  }

  Widget _buildSettingsListView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _buildSettingsChildren(context),
    );
  }

  Widget _buildEmbeddedSettings(BuildContext context) {
    return Container(
      key: MediaAnnotationSettingsPage.embeddedRootKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildSettingsChildren(context),
      ),
    );
  }
}
