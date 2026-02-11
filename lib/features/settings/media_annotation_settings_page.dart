import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/content_enrichment/content_enrichment_config_store.dart';
import '../../core/content_enrichment/linux_ocr_model_store.dart';
import '../../core/content_enrichment/multimodal_ocr.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../audio_transcribe/audio_transcribe_runner.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'cloud_account_page.dart';
import 'llm_profiles_page.dart';
import 'media_annotation_settings_sections.dart';

part 'media_annotation_settings_page_ocr.dart';
part 'media_annotation_settings_page_linux_ocr.dart';
part 'media_annotation_settings_page_media_understanding.dart';

class MediaAnnotationSettingsPage extends StatefulWidget {
  const MediaAnnotationSettingsPage({
    super.key,
    this.configStore,
    this.contentConfigStore,
    this.linuxOcrModelStore,
    this.embedded = false,
  });

  final MediaAnnotationConfigStore? configStore;
  final ContentEnrichmentConfigStore? contentConfigStore;
  final LinuxOcrModelStore? linuxOcrModelStore;
  final bool embedded;

  static const embeddedRootKey =
      ValueKey('media_annotation_settings_embedded_root');
  static const annotateSwitchKey =
      ValueKey('media_annotation_settings_annotate_switch');
  static const searchSwitchKey =
      ValueKey('media_annotation_settings_search_switch');
  static const audioTranscribeSwitchKey =
      ValueKey('media_annotation_settings_audio_transcribe_switch');
  static const ocrSwitchKey = ValueKey('media_annotation_settings_ocr_switch');
  static const ocrModeTileKey =
      ValueKey('media_annotation_settings_ocr_mode_tile');
  static const mediaUnderstandingSwitchKey =
      ValueKey('media_annotation_settings_media_understanding_switch');
  static const wifiOnlySwitchKey =
      ValueKey('media_annotation_settings_wifi_only_switch');
  static const audioApiProfileTileKey =
      ValueKey('media_annotation_settings_audio_api_profile_tile');
  static const imageApiProfileTileKey =
      ValueKey('media_annotation_settings_image_api_profile_tile');
  static const useSecondLoopCloudSwitchKey =
      ValueKey('media_annotation_settings_use_secondloop_cloud_switch');
  static const linuxOcrModelTileKey =
      ValueKey('media_annotation_settings_linux_ocr_model_tile');
  static const linuxOcrModelDownloadButtonKey =
      ValueKey('media_annotation_settings_linux_ocr_download_button');
  static const linuxOcrModelDeleteButtonKey =
      ValueKey('media_annotation_settings_linux_ocr_delete_button');
  static const searchConfirmDialogKey =
      ValueKey('media_annotation_settings_search_confirm_dialog');
  static const searchConfirmCancelKey =
      ValueKey('media_annotation_settings_search_confirm_cancel');
  static const searchConfirmContinueKey =
      ValueKey('media_annotation_settings_search_confirm_continue');

  @override
  State<MediaAnnotationSettingsPage> createState() =>
      _MediaAnnotationSettingsPageState();
}

class _MediaAnnotationSettingsPageState
    extends State<MediaAnnotationSettingsPage> {
  static const _kProviderFollowAskAi = 'follow_ask_ai';
  static const _kProviderCloudGateway = 'cloud_gateway';
  static const _kProviderByokProfile = 'byok_profile';
  static const _kApiProfileFollowChoice = '__follow_ask_ai__';

  bool _didKickoffLoad = false;
  MediaAnnotationConfig? _config;
  ContentEnrichmentConfig? _contentConfig;
  List<LlmProfile>? _llmProfiles;
  Object? _loadError;
  Object? _contentLoadError;
  bool _busy = false;
  bool _linuxOcrBusy = false;
  LinuxOcrModelStatus _linuxOcrModelStatus = const LinuxOcrModelStatus(
    supported: false,
    installed: false,
    modelDirPath: null,
    modelCount: 0,
    totalBytes: 0,
    source: LinuxOcrModelSource.none,
  );

  MediaAnnotationConfigStore get _store =>
      widget.configStore ?? const RustMediaAnnotationConfigStore();
  ContentEnrichmentConfigStore get _contentStore =>
      widget.contentConfigStore ?? const RustContentEnrichmentConfigStore();
  LinuxOcrModelStore get _linuxOcrModelStore =>
      widget.linuxOcrModelStore ?? createLinuxOcrModelStore();

  Future<void> _showSetupRequiredDialog({
    required String reason,
    Future<void> Function()? onOpen,
  }) async {
    final t = context.t.settings.mediaAnnotation.setupRequired;
    final body = [t.body, reason].join('\n\n');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.t.common.actions.notNow),
            ),
            if (onOpen != null)
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(onOpen());
                },
                child: Text(context.t.common.actions.open),
              ),
          ],
        );
      },
    );
  }

  Future<String?> _promptOpenAiCompatibleProfileId() async {
    final t = context.t.settings.mediaAnnotation.byokProfile;
    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    final sessionKey = SessionScope.of(context).sessionKey;
    if (backend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.missingBackend),
          duration: const Duration(seconds: 3),
        ),
      );
      return null;
    }

    final profiles = await backend
        .listLlmProfiles(sessionKey)
        .catchError((_) => <LlmProfile>[]);
    if (!mounted) return null;

    final openAiCompatible = profiles
        .where((p) => p.providerType == 'openai-compatible')
        .toList(growable: false);
    if (openAiCompatible.isEmpty) {
      await _showSetupRequiredDialog(
        reason: context.t.settings.mediaAnnotation.setupRequired.reasons
            .byokOpenAiCompatible,
        onOpen: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
          );
        },
      );
      return null;
    }

    final selectedId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(t.title),
          children: [
            for (final p in openAiCompatible)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(p.id),
                child: Text(p.name),
              ),
          ],
        );
      },
    );
    if (!mounted) return null;
    return selectedId;
  }

  Future<String?> _promptApiProfileOverrideChoice() async {
    final t = context.t.settings.mediaAnnotation;
    final byok = t.byokProfile;
    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    final sessionKey = SessionScope.of(context).sessionKey;
    if (backend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(byok.missingBackend),
          duration: const Duration(seconds: 3),
        ),
      );
      return null;
    }

    final profiles = await backend
        .listLlmProfiles(sessionKey)
        .catchError((_) => <LlmProfile>[]);
    if (!mounted) return null;

    final openAiCompatible = profiles
        .where((p) => p.providerType == 'openai-compatible')
        .toList(growable: false);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(byok.title),
          children: [
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_kApiProfileFollowChoice),
              child: Text(t.providerMode.labels.followAskAi),
            ),
            if (openAiCompatible.isNotEmpty)
              for (final p in openAiCompatible)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(p.id),
                  child: Text(p.name),
                ),
            if (openAiCompatible.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(byok.noOpenAiCompatibleProfiles),
              ),
          ],
        );
      },
    );
    if (!mounted) return null;
    return selected;
  }

  Future<MediaAnnotationConfig?> _prepareEnableAnnotateConfig(
    MediaAnnotationConfig config,
  ) async {
    final desiredMode = config.providerMode.trim();

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final gatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

    final hasGateway = gatewayConfig.baseUrl.trim().isNotEmpty;
    String? idToken;
    if (subscriptionStatus == SubscriptionStatus.entitled) {
      try {
        idToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        idToken = null;
      }
    }
    final hasIdToken = (idToken?.trim() ?? '').isNotEmpty;
    if (!mounted) return null;

    if (desiredMode == _kProviderCloudGateway) {
      if (!hasGateway) {
        await _showSetupRequiredDialog(
          reason: context.t.settings.mediaAnnotation.setupRequired.reasons
              .cloudUnavailable,
        );
        return null;
      }
      if (subscriptionStatus != SubscriptionStatus.entitled) {
        await _showSetupRequiredDialog(
          reason: context.t.settings.mediaAnnotation.setupRequired.reasons
              .cloudRequiresPro,
          onOpen: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CloudAccountPage()),
            );
          },
        );
        return null;
      }
      if (!hasIdToken) {
        await _showSetupRequiredDialog(
          reason: context
              .t.settings.mediaAnnotation.setupRequired.reasons.cloudSignIn,
          onOpen: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CloudAccountPage()),
            );
          },
        );
        return null;
      }
      return MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      );
    }

    if (desiredMode == _kProviderByokProfile) {
      final byokId = config.byokProfileId?.trim();
      final cachedProfiles = _llmProfiles ?? const <LlmProfile>[];
      var hasValidSelected = false;
      if (byokId != null && byokId.isNotEmpty) {
        for (final p in cachedProfiles) {
          if (p.id == byokId && p.providerType == 'openai-compatible') {
            hasValidSelected = true;
            break;
          }
        }
      }

      var resolvedId = byokId;
      if (!hasValidSelected) {
        resolvedId = await _promptOpenAiCompatibleProfileId();
        final trimmed = resolvedId?.trim();
        if (trimmed == null || trimmed.isEmpty) return null;
        resolvedId = trimmed;
      }

      return MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: resolvedId,
        cloudModelName: config.cloudModelName,
      );
    }

    final canUseCloud = subscriptionStatus == SubscriptionStatus.entitled &&
        hasGateway &&
        hasIdToken;
    if (canUseCloud) {
      return MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      );
    }

    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    final sessionKey = SessionScope.of(context).sessionKey;

    List<LlmProfile> profiles = _llmProfiles ?? const <LlmProfile>[];
    if (profiles.isEmpty && backend != null) {
      profiles =
          await backend.listLlmProfiles(sessionKey).catchError((_) => profiles);
    }
    if (!mounted) return null;

    LlmProfile? active;
    for (final p in profiles) {
      if (p.isActive) {
        active = p;
        break;
      }
    }

    final canUseByok =
        active != null && active.providerType == 'openai-compatible';
    if (canUseByok) {
      return MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      );
    }

    await _showSetupRequiredDialog(
      reason:
          context.t.settings.mediaAnnotation.setupRequired.reasons.followAskAi,
      onOpen: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
        );
      },
    );
    return null;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didKickoffLoad) return;
    _didKickoffLoad = true;
    unawaited(_load());
  }

  void _mutateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _load() async {
    final sessionKey = SessionScope.of(context).sessionKey;
    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    try {
      final config = await _store.read(sessionKey);
      ContentEnrichmentConfig? contentConfig;
      Object? contentLoadError;
      LinuxOcrModelStatus linuxOcrModelStatus = const LinuxOcrModelStatus(
        supported: false,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      );
      try {
        contentConfig = await _contentStore.readContentEnrichment(sessionKey);
      } catch (e) {
        contentConfig = null;
        contentLoadError = e;
      }
      try {
        linuxOcrModelStatus = await _linuxOcrModelStore.readStatus();
      } catch (_) {
        linuxOcrModelStatus = const LinuxOcrModelStatus(
          supported: false,
          installed: false,
          modelDirPath: null,
          modelCount: 0,
          totalBytes: 0,
          source: LinuxOcrModelSource.none,
        );
      }
      List<LlmProfile>? profiles;
      if (backend != null) {
        try {
          profiles = await backend.listLlmProfiles(sessionKey);
        } catch (_) {
          profiles = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _config = config;
        _contentConfig = contentConfig;
        _contentLoadError = contentLoadError;
        _linuxOcrModelStatus = linuxOcrModelStatus;
        _llmProfiles = profiles;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _config = null;
        _contentConfig = null;
      });
    }
  }

  Future<void> _persist(MediaAnnotationConfig next) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    setState(() => _busy = true);
    try {
      await _store.write(sessionKey, next);
      if (!mounted) return;
      setState(() => _config = next);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ContentEnrichmentConfig _copyContentConfig(
    ContentEnrichmentConfig source, {
    bool? audioTranscribeEnabled,
    String? audioTranscribeEngine,
    bool? ocrEnabled,
    String? ocrEngineMode,
  }) {
    return ContentEnrichmentConfig(
      urlFetchEnabled: source.urlFetchEnabled,
      documentExtractEnabled: source.documentExtractEnabled,
      documentKeepOriginalMaxBytes: source.documentKeepOriginalMaxBytes,
      audioTranscribeEnabled:
          audioTranscribeEnabled ?? source.audioTranscribeEnabled,
      audioTranscribeEngine:
          audioTranscribeEngine ?? source.audioTranscribeEngine,
      videoExtractEnabled: source.videoExtractEnabled,
      videoProxyEnabled: source.videoProxyEnabled,
      videoProxyMaxDurationMs: source.videoProxyMaxDurationMs,
      videoProxyMaxBytes: source.videoProxyMaxBytes,
      ocrEnabled: ocrEnabled ?? source.ocrEnabled,
      ocrEngineMode: ocrEngineMode ?? source.ocrEngineMode,
      // OCR language hints are fixed to "device language + English".
      ocrLanguageHints: 'device_plus_en',
      // OCR DPI is fixed to 180 for stable quality/perf tradeoff.
      ocrPdfDpi: 180,
      // Auto OCR no longer exposes a page cap in settings.
      ocrPdfAutoMaxPages: 0,
      // OCR page cap is removed.
      ocrPdfMaxPages: 0,
      mobileBackgroundEnabled: source.mobileBackgroundEnabled,
      mobileBackgroundRequiresWifi: source.mobileBackgroundRequiresWifi,
      mobileBackgroundRequiresCharging: source.mobileBackgroundRequiresCharging,
    );
  }

  Future<void> _persistContentConfig(ContentEnrichmentConfig next) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    setState(() => _busy = true);
    try {
      await _contentStore.writeContentEnrichment(sessionKey, next);
      if (!mounted) return;
      setState(() => _contentConfig = next);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _byokProfileName(String? id) {
    final profiles = _llmProfiles;
    if (id == null || id.trim().isEmpty || profiles == null) return null;
    for (final p in profiles) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  String _apiProfileLabel(BuildContext context, String? profileId) {
    return _byokProfileName(profileId) ??
        context.t.settings.mediaAnnotation.providerMode.labels.followAskAi;
  }

  String _imageApiProfileSubtitle(BuildContext context) {
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    if (zh) {
      return '默认跟随 Ask AI，可改为已有 OpenAI-compatible API profile。';
    }
    return 'Default follows Ask AI. You can choose an existing OpenAI-compatible API profile.';
  }

  Future<void> _pickApiProfileOverride(MediaAnnotationConfig config) async {
    if (_busy) return;
    final selected = await _promptApiProfileOverrideChoice();
    if (selected == null || !mounted) return;

    final useFollowAskAi = selected == _kApiProfileFollowChoice;
    final nextByokProfileId = useFollowAskAi ? null : selected;
    final nextMode = config.providerMode == _kProviderCloudGateway
        ? _kProviderCloudGateway
        : (useFollowAskAi ? _kProviderFollowAskAi : _kProviderByokProfile);
    final sameProfile =
        (nextByokProfileId ?? '').trim() == (config.byokProfileId ?? '').trim();
    if (sameProfile && nextMode == config.providerMode) return;

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: nextMode,
        byokProfileId: nextByokProfileId,
        cloudModelName: config.cloudModelName,
      ),
    );
  }

  List<Widget> _buildSettingsChildren(BuildContext context) {
    final config = _config;
    final contentConfig = _contentConfig;
    final t = context.t.settings.mediaAnnotation;

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
      if (config == null && _loadError == null && !widget.embedded)
        const Center(child: CircularProgressIndicator()),
      if (config != null)
        ...() {
          final mediaUnderstandingEnabled =
              _isMediaUnderstandingEnabled(config, contentConfig);
          final subscriptionStatus =
              SubscriptionScope.maybeOf(context)?.status ??
                  SubscriptionStatus.unknown;
          final showSecondLoopCloudSwitch =
              subscriptionStatus == SubscriptionStatus.entitled;
          final useSecondLoopCloud =
              config.providerMode == _kProviderCloudGateway;

          return <Widget>[
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
            if (mediaUnderstandingEnabled) ...[
              const SizedBox(height: 16),
              mediaAnnotationSectionCard([
                if (showSecondLoopCloudSwitch)
                  SwitchListTile(
                    key:
                        MediaAnnotationSettingsPage.useSecondLoopCloudSwitchKey,
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
                  subtitle: Text(_mediaUnderstandingWifiOnlySubtitle(context)),
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
              const SizedBox(height: 16),
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
                            ? (_isZhOcrLocale(context) ? '本地模式' : 'Local mode')
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
              ...() {
                final runtimeTile = _buildDesktopRuntimeHealthTile(context);
                if (runtimeTile == null) {
                  return const <Widget>[];
                }
                return <Widget>[
                  const SizedBox(height: 12),
                  runtimeTile,
                ];
              }(),
              const SizedBox(height: 16),
              ..._buildDocumentOcrSection(context),
              const SizedBox(height: 16),
              mediaAnnotationSectionTitle(context, t.providerSettings.title),
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
    return Padding(
      key: MediaAnnotationSettingsPage.embeddedRootKey,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildSettingsChildren(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.mediaAnnotation;
    if (widget.embedded) {
      return _buildEmbeddedSettings(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.title),
      ),
      body: _buildSettingsListView(context),
    );
  }
}
