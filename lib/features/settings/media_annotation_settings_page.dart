import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/ai/audio_transcribe_whisper_model_prefs.dart';
import '../../core/ai/audio_transcribe_whisper_model_store.dart';
import '../../core/ai/media_capability_source_prefs.dart';
import '../../core/ai/media_capability_wifi_prefs.dart';
import '../../core/ai/media_source_prefs.dart';
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
part 'media_annotation_settings_page_embedded.dart';
part 'media_annotation_settings_page_media_understanding.dart';

class MediaAnnotationSettingsPage extends StatefulWidget {
  const MediaAnnotationSettingsPage({
    super.key,
    this.configStore,
    this.contentConfigStore,
    this.linuxOcrModelStore,
    this.audioWhisperModelStore,
    this.embedded = false,
  });

  final MediaAnnotationConfigStore? configStore;
  final ContentEnrichmentConfigStore? contentConfigStore;
  final LinuxOcrModelStore? linuxOcrModelStore;
  final AudioTranscribeWhisperModelStore? audioWhisperModelStore;
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
  static const audioWifiOnlySwitchKey =
      ValueKey('media_annotation_settings_audio_wifi_only_switch');
  static const ocrWifiOnlySwitchKey =
      ValueKey('media_annotation_settings_ocr_wifi_only_switch');
  static const imageWifiOnlySwitchKey =
      ValueKey('media_annotation_settings_image_wifi_only_switch');
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
  bool _audioWifiOnly = true;
  bool _ocrWifiOnly = true;
  MediaSourcePreference _audioSourcePreference = MediaSourcePreference.auto;
  MediaSourcePreference _ocrSourcePreference = MediaSourcePreference.auto;
  String _audioWhisperModel = kDefaultAudioTranscribeWhisperModel;
  AudioTranscribeWhisperModelStore? _audioWhisperModelStoreCached;
  bool _audioWhisperModelDownloading = false;
  String? _audioWhisperModelDownloadingTarget;
  int _audioWhisperModelDownloadReceivedBytes = 0;
  int? _audioWhisperModelDownloadTotalBytes;

  MediaAnnotationConfigStore get _store =>
      widget.configStore ?? const RustMediaAnnotationConfigStore();
  ContentEnrichmentConfigStore get _contentStore =>
      widget.contentConfigStore ?? const RustContentEnrichmentConfigStore();
  LinuxOcrModelStore get _linuxOcrModelStore =>
      widget.linuxOcrModelStore ?? createLinuxOcrModelStore();
  AudioTranscribeWhisperModelStore get _audioWhisperModelStore =>
      widget.audioWhisperModelStore ??
      (_audioWhisperModelStoreCached ??=
          createAudioTranscribeWhisperModelStore());

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
            MaterialPageRoute(
              builder: (_) => const LlmProfilesPage(
                providerFilter: LlmProfilesProviderFilter.openAiCompatibleOnly,
              ),
            ),
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
          MaterialPageRoute(
            builder: (_) => const LlmProfilesPage(
              providerFilter: LlmProfilesProviderFilter.openAiCompatibleOnly,
            ),
          ),
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

      final fallbackWifiOnly = !config.allowCellular;
      var audioWifiOnly = fallbackWifiOnly;
      var ocrWifiOnly = fallbackWifiOnly;
      try {
        audioWifiOnly = await MediaCapabilityWifiPrefs.readAudioWifiOnly(
          fallbackWifiOnly: fallbackWifiOnly,
        );
        ocrWifiOnly = await MediaCapabilityWifiPrefs.readOcrWifiOnly(
          fallbackWifiOnly: fallbackWifiOnly,
        );
      } catch (_) {
        audioWifiOnly = fallbackWifiOnly;
        ocrWifiOnly = fallbackWifiOnly;
      }

      var audioSourcePreference = MediaSourcePreference.auto;
      var ocrSourcePreference = MediaSourcePreference.auto;
      var audioWhisperModel = kDefaultAudioTranscribeWhisperModel;
      try {
        audioSourcePreference = await MediaCapabilitySourcePrefs.readAudio();
        if (audioSourcePreference == MediaSourcePreference.local) {
          audioSourcePreference = MediaSourcePreference.auto;
          unawaited(
            MediaCapabilitySourcePrefs.write(
              MediaCapabilitySourceScope.audioTranscribe,
              preference: audioSourcePreference,
            ),
          );
        }
        ocrSourcePreference =
            await MediaCapabilitySourcePrefs.readDocumentOcr();
        audioWhisperModel = await AudioTranscribeWhisperModelPrefs.read();
      } catch (_) {
        audioSourcePreference = MediaSourcePreference.auto;
        ocrSourcePreference = MediaSourcePreference.auto;
        audioWhisperModel = kDefaultAudioTranscribeWhisperModel;
      }
      if (!mounted) return;
      setState(() {
        _config = config;
        _contentConfig = contentConfig;
        _contentLoadError = contentLoadError;
        _linuxOcrModelStatus = linuxOcrModelStatus;
        _llmProfiles = profiles;
        _audioWifiOnly = audioWifiOnly;
        _ocrWifiOnly = ocrWifiOnly;
        _audioSourcePreference = audioSourcePreference;
        _ocrSourcePreference = ocrSourcePreference;
        _audioWhisperModel = audioWhisperModel;
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

  Future<void> _setCapabilityWifiOnly({
    required MediaCapabilityWifiScope scope,
    required bool wifiOnly,
  }) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      await MediaCapabilityWifiPrefs.write(scope, wifiOnly: wifiOnly);
      if (!mounted) return;
      setState(() {
        switch (scope) {
          case MediaCapabilityWifiScope.audioTranscribe:
            _audioWifiOnly = wifiOnly;
            break;
          case MediaCapabilityWifiScope.documentOcr:
            _ocrWifiOnly = wifiOnly;
            break;
          case MediaCapabilityWifiScope.imageCaption:
            break;
        }
      });
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

  Future<void> _setAudioSourcePreference(MediaSourcePreference next) async {
    final normalizedNext =
        next == MediaSourcePreference.local ? MediaSourcePreference.auto : next;
    if (_busy || _audioSourcePreference == normalizedNext) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      await MediaCapabilitySourcePrefs.write(
        MediaCapabilitySourceScope.audioTranscribe,
        preference: normalizedNext,
      );
      if (!mounted) return;
      setState(() => _audioSourcePreference = normalizedNext);
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

  Future<void> _setOcrSourcePreference(MediaSourcePreference next) async {
    if (_busy || _ocrSourcePreference == next) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      await MediaCapabilitySourcePrefs.write(
        MediaCapabilitySourceScope.documentOcr,
        preference: next,
      );
      if (!mounted) return;
      setState(() => _ocrSourcePreference = next);
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

  bool _supportsDesktopWhisperModelRuntimeDownload() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Future<void> _setAudioWhisperModel(String next) async {
    if (_busy) return;
    final normalized = normalizeAudioTranscribeWhisperModel(next);
    if (_audioWhisperModel == normalized) return;

    final messenger = ScaffoldMessenger.of(context);
    final store = _audioWhisperModelStore;
    final shouldDownload = store.supportsRuntimeDownload &&
        _supportsDesktopWhisperModelRuntimeDownload();

    setState(() {
      _busy = true;
      _audioWhisperModelDownloading = shouldDownload;
      _audioWhisperModelDownloadingTarget = normalized;
      _audioWhisperModelDownloadReceivedBytes = 0;
      _audioWhisperModelDownloadTotalBytes = null;
    });

    try {
      AudioWhisperModelEnsureResult? ensureResult;
      if (shouldDownload) {
        ensureResult = await store.ensureModelAvailable(
          model: normalized,
          onProgress: _onAudioWhisperModelDownloadProgress,
        );
      }

      await AudioTranscribeWhisperModelPrefs.write(normalized);

      if (!mounted) return;
      setState(() => _audioWhisperModel = normalized);

      if (ensureResult?.status == AudioWhisperModelEnsureStatus.downloaded) {
        final zh = Localizations.localeOf(context)
            .languageCode
            .toLowerCase()
            .startsWith('zh');
        final modelLabel = _audioWhisperModelLabel(context, normalized);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              zh
                  ? '已下载 $modelLabel 模型，可用于本地转写。'
                  : 'Downloaded $modelLabel for local transcription.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _audioWhisperModelDownloading = false;
          _audioWhisperModelDownloadingTarget = null;
          _audioWhisperModelDownloadReceivedBytes = 0;
          _audioWhisperModelDownloadTotalBytes = null;
        });
      }
    }
  }

  void _onAudioWhisperModelDownloadProgress(
    AudioWhisperModelDownloadProgress progress,
  ) {
    if (!mounted) return;

    final received = progress.receivedBytes < 0 ? 0 : progress.receivedBytes;
    final total = (progress.totalBytes != null && progress.totalBytes! > 0)
        ? progress.totalBytes
        : null;

    if (_audioWhisperModelDownloadReceivedBytes == received &&
        _audioWhisperModelDownloadTotalBytes == total &&
        _audioWhisperModelDownloadingTarget == progress.model &&
        _audioWhisperModelDownloading) {
      return;
    }

    setState(() {
      _audioWhisperModelDownloading = true;
      _audioWhisperModelDownloadingTarget = progress.model;
      _audioWhisperModelDownloadReceivedBytes = received;
      _audioWhisperModelDownloadTotalBytes = total;
    });
  }

  String _formatWhisperModelByteSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
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
      return '默认跟随当前激活的 API profile，可改为已有 OpenAI-compatible API profile。';
    }
    return 'Default follows the active API profile. You can choose an existing OpenAI-compatible API profile.';
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
