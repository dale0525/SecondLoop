part of 'ai_settings_page.dart';

extension _AiSettingsPageUiExtension on _AiSettingsPageState {
  Widget _buildWarningBanner(
    BuildContext context,
    String message, {
    Key? key,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.45),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required GlobalKey anchorKey,
    required Key cardKey,
    required AiSettingsSection section,
    required String title,
    required String description,
    required String statusLabel,
    required List<Widget> actions,
    Widget? warning,
  }) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final highlighted = _highlightedSection == section;
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;

    final borderColor = highlighted ? colorScheme.primary : tokens.borderSubtle;
    final backgroundColor = highlighted
        ? colorScheme.primaryContainer.withOpacity(0.28)
        : colorScheme.surface;

    return Container(
      key: anchorKey,
      child: AnimatedContainer(
        key: cardKey,
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.18),
                    blurRadius: 20,
                    spreadRadius: 1,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SlSurface(
            padding: EdgeInsets.zero,
            child: ColoredBox(
              color: backgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(description),
                        const SizedBox(height: 8),
                        Text(
                          statusLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (warning != null) ...[
                          const SizedBox(height: 12),
                          warning,
                        ],
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) const Divider(height: 1),
                  for (var index = 0; index < actions.length; index++) ...[
                    if (index != 0) const Divider(height: 1),
                    actions[index],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAskAiPreferenceTile(
    BuildContext context, {
    required AskAiSourcePreference value,
    required String title,
    required String subtitle,
    required Key key,
  }) {
    return RadioListTile<AskAiSourcePreference>(
      key: key,
      value: value,
      groupValue: _askAiPreference,
      onChanged: _askAiPreferenceSaving
          ? null
          : (next) {
              if (next == null) return;
              unawaited(_setAskAiPreference(next));
            },
      title: Text(title),
      subtitle: Text(subtitle),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildEmbeddingsPreferenceTile(
    BuildContext context, {
    required EmbeddingsSourcePreference value,
    required String title,
    required String subtitle,
    required Key key,
  }) {
    return RadioListTile<EmbeddingsSourcePreference>(
      key: key,
      value: value,
      groupValue: _embeddingsPreference,
      onChanged: _embeddingsPreferenceSaving
          ? null
          : (next) {
              if (next == null) return;
              unawaited(_setEmbeddingsPreference(next));
            },
      title: Text(title),
      subtitle: Text(subtitle),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildMediaPreferenceTile(
    BuildContext context, {
    required MediaSourcePreference value,
    required String title,
    required String subtitle,
    required Key key,
  }) {
    return RadioListTile<MediaSourcePreference>(
      key: key,
      value: value,
      groupValue: _mediaPreference,
      onChanged: _mediaPreferenceSaving
          ? null
          : (next) {
              if (next == null) return;
              unawaited(_setMediaPreference(next));
            },
      title: Text(title),
      subtitle: Text(subtitle),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildPage(BuildContext context) {
    final t = context.t.settings.aiSelection;
    final askAiPreferenceLabels = t.askAi.preference;
    final embeddingsPreferenceLabels = t.embeddings.preference;
    final mediaPreferenceLabels = t.mediaUnderstanding.preference;

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudUid =
        (CloudAuthScope.maybeOf(context)?.controller.uid ?? '').trim();
    final hasCloudAccount = cloudUid.isNotEmpty;
    final canUseCloudEmbeddings =
        hasCloudAccount && subscriptionStatus == SubscriptionStatus.entitled;
    final canUseSemanticParse = canUseCloudEmbeddings || _byokConfigured;

    final cloudEmbeddingsSubtitle =
        subscriptionStatus == SubscriptionStatus.notEntitled
            ? context.t.settings.cloudEmbeddings.subtitleRequiresPro
            : !_cloudEmbeddingsConfigured
                ? context.t.settings.cloudEmbeddings.subtitleUnset
                : (_cloudEmbeddingsEnabled ?? false)
                    ? context.t.settings.cloudEmbeddings.subtitleEnabled
                    : context.t.settings.cloudEmbeddings.subtitleDisabled;

    final semanticParseSubtitle = !canUseSemanticParse
        ? context.t.settings.semanticParseAutoActions.subtitleRequiresSetup
        : !_semanticParseConfigured
            ? context.t.settings.semanticParseAutoActions.subtitleUnset
            : (_semanticParseEnabled ?? false)
                ? context.t.settings.semanticParseAutoActions.subtitleEnabled
                : context.t.settings.semanticParseAutoActions.subtitleDisabled;

    final askPreferredRoute = _preferredAskAiRoute(_askAiPreference);
    final askAiUnavailable = !_askAiLoading &&
        ((askPreferredRoute == null &&
                _askAiRoute == AskAiRouteKind.needsSetup) ||
            (askPreferredRoute != null && askPreferredRoute != _askAiRoute));

    final embeddingsPreferredRoute =
        _preferredEmbeddingsRoute(_embeddingsPreference);
    final embeddingsUnavailable = !_embeddingsLoading &&
        embeddingsPreferredRoute != null &&
        embeddingsPreferredRoute != _embeddingsRoute;

    final mediaPreferredRoute = _preferredMediaRoute(_mediaPreference);
    final mediaUnavailable = !_mediaLoading &&
        mediaPreferredRoute != null &&
        mediaPreferredRoute != _mediaRoute;

    final askAiWarning = askAiUnavailable
        ? _buildWarningBanner(
            context,
            _askAiPreference == AskAiSourcePreference.auto
                ? t.askAi.setupHint
                : t.askAi.preferenceUnavailableHint,
            key: const ValueKey('ai_settings_ask_ai_setup_hint'),
          )
        : null;

    final embeddingsWarning = embeddingsUnavailable
        ? _buildWarningBanner(
            context,
            t.embeddings.preferenceUnavailableHint,
            key: const ValueKey('ai_settings_embeddings_unavailable_hint'),
          )
        : null;

    final mediaWarning = mediaUnavailable
        ? _buildWarningBanner(
            context,
            _mediaUnavailableHint(context),
            key: const ValueKey('ai_settings_media_unavailable_hint'),
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.subtitle),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            anchorKey: _askAiSectionAnchorKey,
            cardKey: const ValueKey('ai_settings_section_ask_ai'),
            section: AiSettingsSection.askAi,
            title: t.askAi.title,
            description: t.askAi.description,
            statusLabel: _askAiStatusLabel(context),
            warning: askAiWarning,
            actions: [
              _buildAskAiPreferenceTile(
                context,
                key: const ValueKey('ai_settings_ask_ai_mode_auto'),
                value: AskAiSourcePreference.auto,
                title: askAiPreferenceLabels.auto.title,
                subtitle: askAiPreferenceLabels.auto.description,
              ),
              _buildAskAiPreferenceTile(
                context,
                key: const ValueKey('ai_settings_ask_ai_mode_cloud'),
                value: AskAiSourcePreference.cloud,
                title: askAiPreferenceLabels.cloud.title,
                subtitle: askAiPreferenceLabels.cloud.description,
              ),
              _buildAskAiPreferenceTile(
                context,
                key: const ValueKey('ai_settings_ask_ai_mode_byok'),
                value: AskAiSourcePreference.byok,
                title: askAiPreferenceLabels.byok.title,
                subtitle: askAiPreferenceLabels.byok.description,
              ),
              SwitchListTile(
                key: const ValueKey(
                  'ai_settings_semantic_parse_auto_actions_switch',
                ),
                title: Text(context.t.settings.semanticParseAutoActions.title),
                subtitle: Text(semanticParseSubtitle),
                value: _semanticParseEnabled ?? false,
                onChanged: _automationLoading || _automationSaving
                    ? null
                    : (value) async {
                        if (value && !canUseSemanticParse) {
                          if (subscriptionStatus ==
                                  SubscriptionStatus.entitled &&
                              !hasCloudAccount) {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CloudAccountPage(),
                              ),
                            );
                            if (!mounted) return;
                            await _reloadAutomationState(forceLoading: false);
                            return;
                          }

                          await _openLlmProfilesForByokSetupAndRefreshRoutes();
                          return;
                        }

                        await _setSemanticParseEnabled(value);
                      },
              ),
              ListTile(
                key: const ValueKey('ai_settings_open_llm_profiles'),
                title: Text(t.askAi.actions.openByok),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LlmProfilesPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            anchorKey: _embeddingsSectionAnchorKey,
            cardKey: const ValueKey('ai_settings_section_embeddings'),
            section: AiSettingsSection.embeddings,
            title: t.embeddings.title,
            description: t.embeddings.description,
            statusLabel: _embeddingsStatusLabel(context),
            warning: embeddingsWarning,
            actions: [
              SwitchListTile(
                key: const ValueKey('ai_settings_cloud_embeddings_switch'),
                title: Text(context.t.settings.cloudEmbeddings.title),
                subtitle: Text(cloudEmbeddingsSubtitle),
                value: _cloudEmbeddingsEnabled ?? false,
                onChanged: _automationLoading || _automationSaving
                    ? null
                    : (value) async {
                        if (value && !canUseCloudEmbeddings) {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CloudAccountPage(),
                            ),
                          );
                          if (!mounted) return;
                          await _reloadAutomationState(forceLoading: false);
                          await _reloadEmbeddingsState(forceLoading: false);
                          return;
                        }

                        await _setCloudEmbeddingsEnabled(value);
                      },
              ),
              _buildEmbeddingsPreferenceTile(
                context,
                key: const ValueKey('ai_settings_embeddings_mode_auto'),
                value: EmbeddingsSourcePreference.auto,
                title: embeddingsPreferenceLabels.auto.title,
                subtitle: embeddingsPreferenceLabels.auto.description,
              ),
              _buildEmbeddingsPreferenceTile(
                context,
                key: const ValueKey('ai_settings_embeddings_mode_cloud'),
                value: EmbeddingsSourcePreference.cloud,
                title: embeddingsPreferenceLabels.cloud.title,
                subtitle: embeddingsPreferenceLabels.cloud.description,
              ),
              _buildEmbeddingsPreferenceTile(
                context,
                key: const ValueKey('ai_settings_embeddings_mode_byok'),
                value: EmbeddingsSourcePreference.byok,
                title: embeddingsPreferenceLabels.byok.title,
                subtitle: embeddingsPreferenceLabels.byok.description,
              ),
              _buildEmbeddingsPreferenceTile(
                context,
                key: const ValueKey('ai_settings_embeddings_mode_local'),
                value: EmbeddingsSourcePreference.local,
                title: embeddingsPreferenceLabels.local.title,
                subtitle: embeddingsPreferenceLabels.local.description,
              ),
              ListTile(
                key: const ValueKey('ai_settings_open_embedding_profiles'),
                title: Text(t.embeddings.actions.openEmbeddingProfiles),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmbeddingProfilesPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            anchorKey: _mediaSectionAnchorKey,
            cardKey: const ValueKey('ai_settings_section_media_understanding'),
            section: AiSettingsSection.mediaUnderstanding,
            title: context.t.settings.mediaAnnotation.imageCaption.title,
            description:
                context.t.settings.mediaAnnotation.annotateEnabled.subtitle,
            statusLabel: _mediaStatusLabel(context),
            warning: mediaWarning,
            actions: [
              _buildMediaPreferenceTile(
                context,
                key: const ValueKey('ai_settings_media_mode_auto'),
                value: MediaSourcePreference.auto,
                title: mediaPreferenceLabels.auto.title,
                subtitle: mediaPreferenceLabels.auto.description,
              ),
              _buildMediaPreferenceTile(
                context,
                key: const ValueKey('ai_settings_media_mode_cloud'),
                value: MediaSourcePreference.cloud,
                title: mediaPreferenceLabels.cloud.title,
                subtitle: mediaPreferenceLabels.cloud.description,
              ),
              _buildMediaPreferenceTile(
                context,
                key: const ValueKey('ai_settings_media_mode_byok'),
                value: MediaSourcePreference.byok,
                title: mediaPreferenceLabels.byok.title,
                subtitle: mediaPreferenceLabels.byok.description,
              ),
              _buildMediaPreferenceTile(
                context,
                key: const ValueKey('ai_settings_media_mode_local'),
                value: MediaSourcePreference.local,
                title: mediaPreferenceLabels.local.title,
                subtitle: _imageLocalSourceSubtitle(context),
              ),
              SwitchListTile(
                key: const ValueKey('ai_settings_media_image_wifi_only'),
                title: Text(_isZhLocale(context) ? '仅Wi-Fi' : 'Wi-Fi only'),
                subtitle: Text(_wifiOnlyHint(context)),
                value: _imageWifiOnly,
                onChanged: _mediaLoading || _imageWifiSaving
                    ? null
                    : (value) {
                        unawaited(_setImageWifiOnly(value));
                      },
              ),
              ListTile(
                key: const ValueKey('ai_settings_open_media_llm_profiles'),
                title: Text(t.mediaUnderstanding.actions.openByok),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LlmProfilesPage(
                        providerFilter:
                            LlmProfilesProviderFilter.openAiCompatibleOnly,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          if (AppBackendScope.maybeOf(context) != null &&
              SessionScope.maybeOf(context) != null) ...[
            const SizedBox(height: 12),
            MediaAnnotationSettingsPage(
              embedded: true,
              focusLocalCapabilityCard: widget.focusMediaLocalCapabilityCard,
            ),
          ],
        ],
      ),
    );
  }
}
