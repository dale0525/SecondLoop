import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/content_enrichment/content_enrichment_config_store.dart';
import '../../core/content_enrichment/linux_ocr_model_store.dart';
import '../../core/content_enrichment/linux_pdf_compress_resource_store.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'cloud_account_page.dart';
import 'llm_profiles_page.dart';
import 'media_annotation_settings_sections.dart';

part 'media_annotation_settings_page_ocr.dart';
part 'media_annotation_settings_page_linux_ocr.dart';
part 'media_annotation_settings_page_linux_pdf_compress.dart';

class MediaAnnotationSettingsPage extends StatefulWidget {
  const MediaAnnotationSettingsPage({
    super.key,
    this.configStore,
    this.contentConfigStore,
    this.linuxOcrModelStore,
    this.linuxPdfCompressResourceStore,
  });

  final MediaAnnotationConfigStore? configStore;
  final ContentEnrichmentConfigStore? contentConfigStore;
  final LinuxOcrModelStore? linuxOcrModelStore;
  final LinuxPdfCompressResourceStore? linuxPdfCompressResourceStore;

  static const annotateSwitchKey =
      ValueKey('media_annotation_settings_annotate_switch');
  static const searchSwitchKey =
      ValueKey('media_annotation_settings_search_switch');
  static const audioTranscribeSwitchKey =
      ValueKey('media_annotation_settings_audio_transcribe_switch');
  static const ocrSwitchKey = ValueKey('media_annotation_settings_ocr_switch');
  static const pdfCompressSwitchKey =
      ValueKey('media_annotation_settings_pdf_compress_switch');
  static const linuxOcrModelTileKey =
      ValueKey('media_annotation_settings_linux_ocr_model_tile');
  static const linuxOcrModelDownloadButtonKey =
      ValueKey('media_annotation_settings_linux_ocr_download_button');
  static const linuxOcrModelDeleteButtonKey =
      ValueKey('media_annotation_settings_linux_ocr_delete_button');
  static const linuxPdfCompressResourceTileKey =
      ValueKey('media_annotation_settings_linux_pdf_compress_resource_tile');
  static const linuxPdfCompressResourceDownloadButtonKey = ValueKey(
    'media_annotation_settings_linux_pdf_compress_resource_download_button',
  );
  static const linuxPdfCompressResourceDeleteButtonKey = ValueKey(
    'media_annotation_settings_linux_pdf_compress_resource_delete_button',
  );
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

  bool _didKickoffLoad = false;
  MediaAnnotationConfig? _config;
  ContentEnrichmentConfig? _contentConfig;
  List<LlmProfile>? _llmProfiles;
  Object? _loadError;
  Object? _contentLoadError;
  bool _busy = false;
  bool _linuxOcrBusy = false;
  bool _linuxPdfCompressBusy = false;
  LinuxOcrModelStatus _linuxOcrModelStatus = const LinuxOcrModelStatus(
    supported: false,
    installed: false,
    modelDirPath: null,
    modelCount: 0,
    totalBytes: 0,
    source: LinuxOcrModelSource.none,
  );
  LinuxPdfCompressResourceStatus _linuxPdfCompressResourceStatus =
      const LinuxPdfCompressResourceStatus(
    supported: false,
    installed: false,
    resourceDirPath: null,
    fileCount: 0,
    totalBytes: 0,
    source: LinuxPdfCompressResourceSource.none,
  );

  MediaAnnotationConfigStore get _store =>
      widget.configStore ?? const RustMediaAnnotationConfigStore();
  ContentEnrichmentConfigStore get _contentStore =>
      widget.contentConfigStore ?? const RustContentEnrichmentConfigStore();
  LinuxOcrModelStore get _linuxOcrModelStore =>
      widget.linuxOcrModelStore ?? createLinuxOcrModelStore();
  LinuxPdfCompressResourceStore get _linuxPdfCompressResourceStore =>
      widget.linuxPdfCompressResourceStore ??
      createLinuxPdfCompressResourceStore();

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
      LinuxPdfCompressResourceStatus linuxPdfCompressResourceStatus =
          const LinuxPdfCompressResourceStatus(
        supported: false,
        installed: false,
        resourceDirPath: null,
        fileCount: 0,
        totalBytes: 0,
        source: LinuxPdfCompressResourceSource.none,
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
      try {
        linuxPdfCompressResourceStatus =
            await _linuxPdfCompressResourceStore.readStatus();
      } catch (_) {
        linuxPdfCompressResourceStatus = const LinuxPdfCompressResourceStatus(
          supported: false,
          installed: false,
          resourceDirPath: null,
          fileCount: 0,
          totalBytes: 0,
          source: LinuxPdfCompressResourceSource.none,
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
        _linuxPdfCompressResourceStatus = linuxPdfCompressResourceStatus;
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
    String? ocrLanguageHints,
    int? ocrPdfDpi,
    int? ocrPdfAutoMaxPages,
    bool? pdfSmartCompressEnabled,
  }) {
    return ContentEnrichmentConfig(
      urlFetchEnabled: source.urlFetchEnabled,
      documentExtractEnabled: source.documentExtractEnabled,
      documentKeepOriginalMaxBytes: source.documentKeepOriginalMaxBytes,
      pdfSmartCompressEnabled:
          pdfSmartCompressEnabled ?? source.pdfSmartCompressEnabled,
      audioTranscribeEnabled:
          audioTranscribeEnabled ?? source.audioTranscribeEnabled,
      audioTranscribeEngine:
          audioTranscribeEngine ?? source.audioTranscribeEngine,
      videoExtractEnabled: source.videoExtractEnabled,
      videoProxyEnabled: source.videoProxyEnabled,
      videoProxyMaxDurationMs: source.videoProxyMaxDurationMs,
      videoProxyMaxBytes: source.videoProxyMaxBytes,
      ocrEnabled: ocrEnabled ?? source.ocrEnabled,
      ocrEngineMode: source.ocrEngineMode,
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

  Future<bool> _confirmSearchToggle({required bool enabled}) async {
    final t = context.t.settings.mediaAnnotation.searchToggleConfirm;

    return (await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              key: MediaAnnotationSettingsPage.searchConfirmDialogKey,
              title: Text(t.title),
              content: Text(
                enabled ? t.bodyEnable : t.bodyDisable,
              ),
              actions: [
                TextButton(
                  key: MediaAnnotationSettingsPage.searchConfirmCancelKey,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(context.t.common.actions.cancel),
                ),
                FilledButton(
                  key: MediaAnnotationSettingsPage.searchConfirmContinueKey,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(context.t.common.actions.continueLabel),
                ),
              ],
            );
          },
        )) ==
        true;
  }

  String _providerModeLabel(BuildContext context, String mode) {
    final t = context.t.settings.mediaAnnotation.providerMode.labels;
    return switch (mode) {
      _kProviderCloudGateway => t.cloudGateway,
      _kProviderByokProfile => t.byokProfile,
      _ => t.followAskAi,
    };
  }

  String? _byokProfileName(String? id) {
    final profiles = _llmProfiles;
    if (id == null || id.trim().isEmpty || profiles == null) return null;
    for (final p in profiles) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  Future<void> _pickProviderMode(MediaAnnotationConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.providerMode;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value = config.providerMode;

        return AlertDialog(
          title: Text(t.title),
          content: StatefulBuilder(
            builder: (context, setInnerState) {
              Widget option({
                required String mode,
                required String title,
                required String body,
              }) {
                return RadioListTile<String>(
                  value: mode,
                  groupValue: value,
                  title: Text(title),
                  subtitle: Text(body),
                  onChanged: (next) {
                    if (next == null) return;
                    setInnerState(() => value = next);
                  },
                );
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    option(
                      mode: _kProviderFollowAskAi,
                      title: t.labels.followAskAi,
                      body: t.descriptions.followAskAi,
                    ),
                    option(
                      mode: _kProviderCloudGateway,
                      title: t.labels.cloudGateway,
                      body: t.descriptions.cloudGateway,
                    ),
                    option(
                      mode: _kProviderByokProfile,
                      title: t.labels.byokProfile,
                      body: t.descriptions.byokProfile,
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
    if (selected == null || !mounted) return;
    if (selected == config.providerMode) return;

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: selected,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      ),
    );
  }

  Future<void> _pickCloudModelName(MediaAnnotationConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.cloudModelName;

    final controller = TextEditingController(text: config.cloudModelName ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: t.hint,
            ),
            textInputAction: TextInputAction.done,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(context.t.common.actions.save),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (saved == null || !mounted) return;

    final trimmed = saved.trim();
    final nextCloudModelName = trimmed.isEmpty ? null : trimmed;
    if (nextCloudModelName == config.cloudModelName) return;

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: nextCloudModelName,
      ),
    );
  }

  Future<void> _pickByokProfile(MediaAnnotationConfig config) async {
    if (_busy) return;
    final selectedId = await _promptOpenAiCompatibleProfileId();
    if (selectedId == null || !mounted) return;
    if (selectedId == config.byokProfileId) return;

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: selectedId,
        cloudModelName: config.cloudModelName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final contentConfig = _contentConfig;
    final t = context.t.settings.mediaAnnotation;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          if (config == null && _loadError == null)
            const Center(child: CircularProgressIndicator()),
          if (config != null) ...[
            mediaAnnotationRoutingGuideCard(
              context: context,
              title: t.routingGuide.title,
              pro: t.routingGuide.pro,
              byok: t.routingGuide.byok,
            ),
            const SizedBox(height: 16),
            mediaAnnotationSectionTitle(context, t.audioTranscribe.title),
            const SizedBox(height: 8),
            mediaAnnotationSectionCard([
              SwitchListTile(
                key: MediaAnnotationSettingsPage.audioTranscribeSwitchKey,
                title: Text(t.audioTranscribe.enabled.title),
                subtitle: Text(t.audioTranscribe.enabled.subtitle),
                value: contentConfig?.audioTranscribeEnabled ?? false,
                onChanged: _busy || contentConfig == null
                    ? null
                    : (value) async {
                        await _persistContentConfig(
                          _copyContentConfig(
                            contentConfig,
                            audioTranscribeEnabled: value,
                          ),
                        );
                      },
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
                title: Text(t.audioTranscribe.configureApi.title),
                subtitle: Text(t.audioTranscribe.configureApi.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _openAudioTranscribeConfigHelp,
              ),
            ]),
            const SizedBox(height: 16),
            ..._buildDocumentOcrSection(context, contentConfig),
            const SizedBox(height: 16),
            mediaAnnotationSectionTitle(context, t.pdfCompression.title),
            const SizedBox(height: 8),
            mediaAnnotationSectionCard([
              SwitchListTile(
                key: MediaAnnotationSettingsPage.pdfCompressSwitchKey,
                title: Text(t.pdfCompression.enabled.title),
                subtitle: Text(t.pdfCompression.enabled.subtitle),
                value: contentConfig?.pdfSmartCompressEnabled ?? false,
                onChanged: _busy || contentConfig == null
                    ? null
                    : (value) async {
                        await _persistContentConfig(
                          _copyContentConfig(
                            contentConfig,
                            pdfSmartCompressEnabled: value,
                          ),
                        );
                      },
              ),
              if (_buildLinuxPdfCompressResourceTile(context) case final tile?)
                tile,
            ]),
            const SizedBox(height: 16),
            mediaAnnotationSectionTitle(context, t.imageCaption.title),
            const SizedBox(height: 8),
            mediaAnnotationSectionCard([
              SwitchListTile(
                key: MediaAnnotationSettingsPage.annotateSwitchKey,
                title: Text(t.annotateEnabled.title),
                subtitle: Text(t.annotateEnabled.subtitle),
                value: config.annotateEnabled,
                onChanged: _busy
                    ? null
                    : (value) async {
                        if (!value) {
                          await _persist(
                            MediaAnnotationConfig(
                              annotateEnabled: false,
                              searchEnabled: config.searchEnabled,
                              allowCellular: config.allowCellular,
                              providerMode: config.providerMode,
                              byokProfileId: config.byokProfileId,
                              cloudModelName: config.cloudModelName,
                            ),
                          );
                          return;
                        }

                        final prepared =
                            await _prepareEnableAnnotateConfig(config);
                        if (prepared == null || !mounted) return;
                        await _persist(prepared);
                      },
              ),
              SwitchListTile(
                key: MediaAnnotationSettingsPage.searchSwitchKey,
                title: Text(t.searchEnabled.title),
                subtitle: Text(t.searchEnabled.subtitle),
                value: config.searchEnabled,
                onChanged: _busy
                    ? null
                    : (value) async {
                        final confirmed =
                            await _confirmSearchToggle(enabled: value);
                        if (!confirmed || !mounted) return;
                        await _persist(
                          MediaAnnotationConfig(
                            annotateEnabled: config.annotateEnabled,
                            searchEnabled: value,
                            allowCellular: config.allowCellular,
                            providerMode: config.providerMode,
                            byokProfileId: config.byokProfileId,
                            cloudModelName: config.cloudModelName,
                          ),
                        );
                      },
              ),
            ]),
            const SizedBox(height: 16),
            mediaAnnotationSectionTitle(context, t.providerSettings.title),
            const SizedBox(height: 8),
            mediaAnnotationSectionCard([
              ListTile(
                title: Text(t.providerMode.title),
                subtitle: Text(t.providerMode.subtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_providerModeLabel(context, config.providerMode)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: _busy ? null : () => _pickProviderMode(config),
              ),
              if (config.providerMode == _kProviderCloudGateway)
                ListTile(
                  title: Text(t.cloudModelName.title),
                  subtitle: Text(t.cloudModelName.subtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text((config.cloudModelName ??
                              t.cloudModelName.followAskAi)
                          .trim()),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: _busy ? null : () => _pickCloudModelName(config),
                ),
              if (config.providerMode == _kProviderByokProfile)
                ListTile(
                  title: Text(t.byokProfile.title),
                  subtitle: Text(t.byokProfile.subtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _byokProfileName(config.byokProfileId) ??
                            t.byokProfile.unset,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: _busy ? null : () => _pickByokProfile(config),
                ),
              SwitchListTile(
                title: Text(t.allowCellular.title),
                subtitle: Text(t.allowCellular.subtitle),
                value: config.allowCellular,
                onChanged: _busy
                    ? null
                    : (value) async {
                        await _persist(
                          MediaAnnotationConfig(
                            annotateEnabled: config.annotateEnabled,
                            searchEnabled: config.searchEnabled,
                            allowCellular: value,
                            providerMode: config.providerMode,
                            byokProfileId: config.byokProfileId,
                            cloudModelName: config.cloudModelName,
                          ),
                        );
                      },
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
