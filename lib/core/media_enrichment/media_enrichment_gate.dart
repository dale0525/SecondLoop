import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/audio_transcribe/audio_transcribe_runner.dart';
import '../../features/attachments/platform_pdf_ocr.dart';
import '../../features/attachments/video_keyframe_ocr_worker.dart';
import '../../features/media_enrichment/media_enrichment_runner.dart';
import '../../features/media_enrichment/ocr_fallback_media_annotation_client.dart';
import '../../features/url_enrichment/url_enrichment_runner.dart';
import '../ai/ai_routing.dart';
import '../ai/audio_transcribe_whisper_model_prefs.dart';
import '../ai/media_capability_source_prefs.dart';
import '../ai/media_capability_wifi_prefs.dart';
import '../ai/media_source_prefs.dart';
import '../backend/app_backend.dart';
import '../backend/native_app_dir.dart';
import '../backend/native_backend.dart';
import '../attachments/attachment_metadata_store.dart';
import '../cloud/cloud_auth_scope.dart';
import '../content_enrichment/content_enrichment_config_store.dart';
import '../content_enrichment/docx_ocr.dart';
import '../content_enrichment/docx_ocr_policy.dart';
import '../content_enrichment/multimodal_ocr.dart';
import '../content_enrichment/ocr_result_preference.dart';
import '../content_enrichment/pdf_ocr_auto_policy.dart';
import '../content_enrichment/video_ocr_auto_policy.dart';
import '../media_annotation/media_annotation_config_store.dart';
import '../session/session_scope.dart';
import '../sync/sync_engine.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine_gate.dart';
import 'media_enrichment_availability.dart';
import '../../src/rust/api/media_annotation.dart' as rust_media_annotation;
import '../../src/rust/db.dart';
import '../../i18n/strings.g.dart';

part 'media_enrichment_gate_clients.dart';
part 'media_enrichment_gate_audio_transcribe.dart';
part 'media_enrichment_gate_auto_ocr.dart';

class MediaEnrichmentGate extends StatefulWidget {
  const MediaEnrichmentGate({required this.child, super.key});

  final Widget child;

  @override
  State<MediaEnrichmentGate> createState() => _MediaEnrichmentGateState();
}

class _MediaEnrichmentGateState extends State<MediaEnrichmentGate>
    with WidgetsBindingObserver {
  static const _kIdleInterval = Duration(seconds: 30);
  static const _kDrainInterval = Duration(seconds: 2);
  static const _kFailureInterval = Duration(seconds: 10);

  Timer? _timer;
  DateTime? _nextRunAt;
  bool _running = false;
  bool _cellularPromptShown = false;
  final Set<String> _autoOcrCompletedShas = <String>{};
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachSyncEngine();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _schedule(const Duration(milliseconds: 800));
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
        _nextRunAt = null;
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final backend = AppBackendScope.of(context);
    if (backend is! NativeAppBackend) {
      _detachSyncEngine();
      _timer?.cancel();
      _timer = null;
      _nextRunAt = null;
      return;
    }

    _attachSyncEngine(SyncEngineScope.maybeOf(context));
    _schedule(const Duration(seconds: 2));
  }

  void _attachSyncEngine(SyncEngine? engine) {
    if (identical(engine, _syncEngine)) return;
    _detachSyncEngine();

    _syncEngine = engine;
    if (engine == null) return;

    void onChange() {
      _schedule(const Duration(milliseconds: 800));
    }

    _syncListener = onChange;
    engine.changes.addListener(onChange);
  }

  void _detachSyncEngine() {
    final engine = _syncEngine;
    final listener = _syncListener;
    if (engine != null && listener != null) {
      engine.changes.removeListener(listener);
    }
    _syncEngine = null;
    _syncListener = null;
  }

  void _schedule(Duration delay) {
    if (!mounted) return;

    final now = DateTime.now();
    final desired = now.add(delay);
    final nextRunAt = _nextRunAt;
    if (nextRunAt != null && nextRunAt.isBefore(desired)) {
      return;
    }

    _timer?.cancel();
    _nextRunAt = desired;
    _timer = Timer(delay, () {
      _nextRunAt = null;
      unawaited(_runOnce());
    });
  }

  static String _formatLocalDayKey(DateTime value) {
    final dt = value.toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      return int.tryParse(raw.trim()) ?? 0;
    }
    return 0;
  }

  static Map<String, Object?>? _decodePayloadObject(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _promptAllowCellular() async {
    final t = context.t.settings.mediaAnnotation.allowCellularConfirm;
    return (await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(t.title),
              content: Text(t.body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(context.t.common.actions.notNow),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(context.t.common.actions.allow),
                ),
              ],
            );
          },
        )) ==
        true;
  }

  Future<void> _runOnce() async {
    if (_running) return;
    if (!mounted) return;

    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);

    _running = true;
    try {
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

      String? idToken;
      try {
        idToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        idToken = null;
      }
      if (!mounted) return;

      final availability = resolveMediaEnrichmentAvailability(
        subscriptionStatus: subscriptionStatus,
        cloudIdToken: idToken?.trim(),
        gatewayBaseUrl: gatewayConfig.baseUrl,
      );

      const configStore = RustMediaAnnotationConfigStore();
      final mediaAnnotationConfig = await configStore
          .read(Uint8List.fromList(sessionKey))
          .catchError((_) {
        return const MediaAnnotationConfig(
          annotateEnabled: false,
          searchEnabled: false,
          allowCellular: false,
          providerMode: 'follow_ask_ai',
        );
      });

      final fallbackWifiOnly = !mediaAnnotationConfig.allowCellular;
      var audioWifiOnly = fallbackWifiOnly;
      var ocrWifiOnly = fallbackWifiOnly;
      var imageWifiOnly = fallbackWifiOnly;
      var audioWhisperModel = kDefaultAudioTranscribeWhisperModel;
      try {
        audioWifiOnly = await MediaCapabilityWifiPrefs.readAudioWifiOnly(
          fallbackWifiOnly: fallbackWifiOnly,
        );
        ocrWifiOnly = await MediaCapabilityWifiPrefs.readOcrWifiOnly(
          fallbackWifiOnly: fallbackWifiOnly,
        );
        imageWifiOnly = await MediaCapabilityWifiPrefs.readImageWifiOnly(
          fallbackWifiOnly: fallbackWifiOnly,
        );
        audioWhisperModel = await AudioTranscribeWhisperModelPrefs.read();
      } catch (_) {
        audioWifiOnly = fallbackWifiOnly;
        ocrWifiOnly = fallbackWifiOnly;
        imageWifiOnly = fallbackWifiOnly;
        audioWhisperModel = kDefaultAudioTranscribeWhisperModel;
      }

      final geoReverseEnabled = availability.geoReverseAvailable;

      ContentEnrichmentConfig? contentConfig;
      try {
        contentConfig = await const RustContentEnrichmentConfigStore()
            .readContentEnrichment(Uint8List.fromList(sessionKey));
      } catch (_) {
        contentConfig = null;
      }

      final contentBackgroundEnabled =
          contentConfig?.mobileBackgroundEnabled ?? true;
      final urlFetchEnabled =
          contentBackgroundEnabled && (contentConfig?.urlFetchEnabled ?? true);
      final documentExtractEnabled = contentBackgroundEnabled &&
          (contentConfig?.documentExtractEnabled ?? true);
      final videoExtractEnabled = contentBackgroundEnabled &&
          (contentConfig?.videoExtractEnabled ?? false);
      final contentRequiresWifi =
          contentConfig?.mobileBackgroundRequiresWifi ?? true;
      final audioTranscribeConfigured = contentBackgroundEnabled &&
          (contentConfig?.audioTranscribeEnabled ?? false);

      MediaEnrichmentClient? annotationPrimaryClient;
      var annotationModelName = gatewayConfig.modelName;

      final hasGateway = gatewayConfig.baseUrl.trim().isNotEmpty;
      final hasIdToken = (idToken?.trim() ?? '').isNotEmpty;
      final cloudAvailable =
          subscriptionStatus == SubscriptionStatus.entitled &&
              hasGateway &&
              hasIdToken;

      List<LlmProfile> llmProfiles = const <LlmProfile>[];
      try {
        llmProfiles =
            await backend.listLlmProfiles(Uint8List.fromList(sessionKey));
      } catch (_) {
        llmProfiles = const <LlmProfile>[];
      }
      if (!mounted) return;

      LlmProfile? findProfile(String id) {
        for (final p in llmProfiles) {
          if (p.id == id) return p;
        }
        return null;
      }

      LlmProfile? selectedOpenAiProfile() {
        final id = mediaAnnotationConfig.byokProfileId?.trim();
        if (id == null || id.isEmpty) return null;
        final selected = findProfile(id);
        if (selected == null) return null;
        if (selected.providerType != 'openai-compatible') return null;
        return selected;
      }

      LlmProfile? activeOpenAiProfile() {
        for (final p in llmProfiles) {
          if (!p.isActive) continue;
          if (p.providerType != 'openai-compatible') continue;
          return p;
        }
        return null;
      }

      LlmProfile? effectiveOpenAiProfile() {
        final selected = selectedOpenAiProfile();
        if (selected != null) return selected;
        return activeOpenAiProfile();
      }

      final hasOpenAiByokProfile = effectiveOpenAiProfile() != null;
      MediaSourcePreference imagePreference;
      MediaSourcePreference audioPreference;
      MediaSourcePreference ocrPreference;
      try {
        imagePreference = await MediaSourcePrefs.read();
      } catch (_) {
        imagePreference = MediaSourcePreference.auto;
      }
      try {
        audioPreference = await MediaCapabilitySourcePrefs.readAudio();
      } catch (_) {
        audioPreference = MediaSourcePreference.auto;
      }
      try {
        ocrPreference = await MediaCapabilitySourcePrefs.readDocumentOcr();
      } catch (_) {
        ocrPreference = MediaSourcePreference.auto;
      }

      final effectiveRoute = resolveMediaSourceRoute(
        imagePreference,
        cloudAvailable: cloudAvailable,
        hasByokProfile: hasOpenAiByokProfile,
      );
      final audioRoute = resolveMediaSourceRoute(
        audioPreference,
        cloudAvailable: cloudAvailable,
        hasByokProfile: hasOpenAiByokProfile,
        hasLocalCapability: false,
      );
      final ocrRoute = resolveMediaSourceRoute(
        ocrPreference,
        cloudAvailable: cloudAvailable,
        hasByokProfile: hasOpenAiByokProfile,
      );
      final effectiveDesiredMode = switch (effectiveRoute) {
        MediaSourceRouteKind.cloudGateway => 'cloud_gateway',
        MediaSourceRouteKind.byok => 'byok_profile',
        MediaSourceRouteKind.local => 'follow_ask_ai',
      };

      final effectiveMediaAnnotationConfig = MediaAnnotationConfig(
        annotateEnabled: mediaAnnotationConfig.annotateEnabled,
        searchEnabled: mediaAnnotationConfig.searchEnabled,
        allowCellular: mediaAnnotationConfig.allowCellular,
        providerMode: effectiveDesiredMode,
        byokProfileId: effectiveRoute == MediaSourceRouteKind.local
            ? null
            : mediaAnnotationConfig.byokProfileId,
        cloudModelName: mediaAnnotationConfig.cloudModelName,
      );

      var hasCloudAnnotationModel = false;
      if (effectiveMediaAnnotationConfig.annotateEnabled) {
        if (effectiveDesiredMode == 'cloud_gateway') {
          if (cloudAvailable) {
            annotationModelName = effectiveMediaAnnotationConfig.cloudModelName
                        ?.trim()
                        .isNotEmpty ==
                    true
                ? effectiveMediaAnnotationConfig.cloudModelName!.trim()
                : gatewayConfig.modelName;
            hasCloudAnnotationModel = annotationModelName.trim().isNotEmpty;
          }
        } else if (effectiveDesiredMode == 'byok_profile') {
          final profile = effectiveOpenAiProfile();
          if (profile != null) {
            annotationPrimaryClient = _ByokMediaEnrichmentClient(
              sessionKey: Uint8List.fromList(sessionKey),
              profileId: profile.id,
              modelName: profile.modelName,
              appDirProvider: getNativeAppDir,
            );
          }
        }
      }

      final allowImageOcrFallback =
          effectiveMediaAnnotationConfig.annotateEnabled &&
              (contentConfig?.ocrEnabled ?? true) &&
              effectiveRoute != MediaSourceRouteKind.cloudGateway;

      final annotationEnabled =
          effectiveMediaAnnotationConfig.annotateEnabled &&
              (annotationPrimaryClient != null ||
                  hasCloudAnnotationModel ||
                  allowImageOcrFallback);
      final audioTranscribeCloudEnabled =
          audioRoute != MediaSourceRouteKind.byok && cloudAvailable;
      final audioTranscribeByokProfile =
          audioRoute == MediaSourceRouteKind.cloudGateway
              ? null
              : effectiveOpenAiProfile();
      final effectiveAudioEngine = normalizeAudioTranscribeEngine(
        contentConfig?.audioTranscribeEngine ?? 'whisper',
      );
      final audioTranscribeSelection = _buildAudioTranscribeClientSelection(
        cloudEnabled: audioTranscribeCloudEnabled,
        byokProfile: audioTranscribeByokProfile,
        effectiveEngine: effectiveAudioEngine,
        whisperModel: audioWhisperModel,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        cloudIdToken: idToken?.trim() ?? '',
        sessionKey: Uint8List.fromList(sessionKey),
      );
      final audioTranscribeEnabled =
          audioTranscribeConfigured && audioTranscribeSelection.hasAnyClient;

      if (!geoReverseEnabled &&
          !annotationEnabled &&
          !urlFetchEnabled &&
          !documentExtractEnabled &&
          !videoExtractEnabled &&
          !audioTranscribeEnabled) {
        _schedule(_kIdleInterval);
        return;
      }

      MediaEnrichmentNetwork? lastNetwork;
      MediaEnrichmentNetwork? cachedNetwork;
      Future<MediaEnrichmentNetwork> getNetwork() async {
        final existing = cachedNetwork;
        if (existing != null) return existing;
        try {
          final network =
              await ConnectivityMediaEnrichmentNetworkProvider().call();
          cachedNetwork = network;
          lastNetwork = network;
          return network;
        } catch (_) {
          cachedNetwork = MediaEnrichmentNetwork.unknown;
          lastNetwork = MediaEnrichmentNetwork.unknown;
          return MediaEnrichmentNetwork.unknown;
        }
      }

      var processedUrl = 0;
      if (urlFetchEnabled) {
        final network = await getNetwork();
        final allowedByNetwork = network != MediaEnrichmentNetwork.offline &&
            (!contentRequiresWifi || network == MediaEnrichmentNetwork.wifi);
        if (allowedByNetwork) {
          final store = _BackendUrlEnrichmentStore(
            backend: backend,
            sessionKey: Uint8List.fromList(sessionKey),
          );
          final runner = UrlEnrichmentRunner(
            store: store,
            fetcher: HttpUrlEnrichmentFetcher(
              securityPolicy: UrlEnrichmentSecurityPolicy(),
            ),
          );
          final result = await runner.runOnce(limit: 5);
          processedUrl = result.processed;
        }
      }

      var processedDocs = 0;
      if (documentExtractEnabled || videoExtractEnabled) {
        try {
          processedDocs = await backend.processPendingDocumentExtractions(
            Uint8List.fromList(sessionKey),
            limit: 5,
          );
        } catch (_) {
          processedDocs = 0;
        }
      }

      final rawConfiguredOcrHints = contentConfig?.ocrLanguageHints ?? '';
      final configuredOcrHints = rawConfiguredOcrHints.trim().isEmpty
          ? 'device_plus_en'
          : rawConfiguredOcrHints.trim();

      final shouldTryMultimodalOcr = ocrRoute != MediaSourceRouteKind.local;
      final networkForOcr = await getNetwork();
      final canUseNetworkOcr =
          networkForOcr != MediaEnrichmentNetwork.offline &&
              (!ocrWifiOnly || networkForOcr == MediaEnrichmentNetwork.wifi);

      var processedAutoPdfOcr = 0;
      if (documentExtractEnabled) {
        try {
          processedAutoPdfOcr = await _runAutoPdfOcrForRecentScannedPdfs(
            backend: backend,
            sessionKey: Uint8List.fromList(sessionKey),
            contentConfig: contentConfig,
            runMultimodalPdfOcr: shouldTryMultimodalOcr && canUseNetworkOcr
                ? (bytes, {required pageCount}) {
                    return tryConfiguredMultimodalPdfOcr(
                      backend: backend,
                      sessionKey: Uint8List.fromList(sessionKey),
                      pdfBytes: bytes,
                      pageCountHint: pageCount,
                      languageHints: configuredOcrHints,
                      subscriptionStatus: subscriptionStatus,
                      mediaAnnotationConfig: effectiveMediaAnnotationConfig,
                      llmProfiles: llmProfiles,
                      cloudGatewayBaseUrl: gatewayConfig.baseUrl,
                      cloudIdToken: idToken?.trim() ?? '',
                      cloudModelName: gatewayConfig.modelName,
                    );
                  }
                : (bytes, {required pageCount}) async => null,
            onAutoPdfOcrStatusChanged: () {
              syncEngine?.notifyExternalChange();
            },
          );
        } catch (_) {
          processedAutoPdfOcr = 0;
        }
      }

      var processedAutoDocxOcr = 0;
      if (documentExtractEnabled &&
          shouldTryMultimodalOcr &&
          canUseNetworkOcr) {
        try {
          processedAutoDocxOcr = await _runAutoDocxOcrForRecentOfficeDocs(
            backend: backend,
            sessionKey: Uint8List.fromList(sessionKey),
            contentConfig: contentConfig,
            runDocxOcr: (bytes,
                {required pageCount, required languageHints}) async {
              return tryConfiguredDocxOcr(
                backend: backend,
                sessionKey: Uint8List.fromList(sessionKey),
                docxBytes: bytes,
                pageCountHint: pageCount,
                languageHints: languageHints,
                subscriptionStatus: subscriptionStatus,
                mediaAnnotationConfig: effectiveMediaAnnotationConfig,
                llmProfiles: llmProfiles,
                cloudGatewayBaseUrl: gatewayConfig.baseUrl,
                cloudIdToken: idToken?.trim() ?? '',
                cloudModelName: gatewayConfig.modelName,
              );
            },
          );
        } catch (_) {
          processedAutoDocxOcr = 0;
        }
      }

      var processedAudioTranscripts = 0;
      if (audioTranscribeEnabled) {
        final network = await getNetwork();
        final audioRequiresWifi = contentRequiresWifi || audioWifiOnly;
        final allowedByNetwork = network != MediaEnrichmentNetwork.offline &&
            (!audioRequiresWifi || network == MediaEnrichmentNetwork.wifi);

        final client = allowedByNetwork
            ? audioTranscribeSelection.networkClient
            : audioTranscribeSelection.offlineClient;
        if (client != null) {
          final store = BackendAudioTranscribeStore(
            backend: backend,
            sessionKey: Uint8List.fromList(sessionKey),
          );
          final runner = AudioTranscribeRunner(
            store: store,
            client: client,
          );
          final result = await runner.runOnce(limit: 5);
          processedAudioTranscripts = result.processed;
        }
      }

      var processedAutoVideoOcr = 0;
      if (videoExtractEnabled) {
        try {
          processedAutoVideoOcr =
              await _runAutoVideoManifestOcrForRecentAttachments(
            backend: backend,
            sessionKey: Uint8List.fromList(sessionKey),
            contentConfig: contentConfig,
            shouldTryMultimodalOcr: shouldTryMultimodalOcr,
            canUseNetworkOcr: canUseNetworkOcr,
            audioTranscribeEnabled: audioTranscribeEnabled,
            subscriptionStatus: subscriptionStatus,
            mediaAnnotationConfig: effectiveMediaAnnotationConfig,
            llmProfiles: llmProfiles,
            cloudGatewayBaseUrl: gatewayConfig.baseUrl,
            cloudIdToken: idToken?.trim() ?? '',
            cloudModelName: gatewayConfig.modelName,
          );
        } catch (_) {
          processedAutoVideoOcr = 0;
        }
      }

      MediaEnrichmentRunResult result = const MediaEnrichmentRunResult(
        processedPlaces: 0,
        processedAnnotations: 0,
        needsAnnotationCellularConfirmation: false,
      );
      if (geoReverseEnabled || annotationEnabled) {
        final baseStore = BackendMediaEnrichmentStore(
          backend: backend,
          sessionKey: Uint8List.fromList(sessionKey),
        );
        final store = _GatedMediaEnrichmentStore(
          baseStore: baseStore,
          placesEnabled: geoReverseEnabled,
          annotationEnabled: annotationEnabled,
        );

        final cloudClient = CloudGatewayMediaEnrichmentClient(
          backend: backend,
          gatewayBaseUrl: gatewayConfig.baseUrl,
          idToken: idToken?.trim() ?? '',
          annotationModelName: annotationModelName,
        );

        MediaEnrichmentClient? annotationClientForRunner =
            annotationPrimaryClient;
        if (annotationClientForRunner == null && hasCloudAnnotationModel) {
          annotationClientForRunner = cloudClient;
        }
        if (allowImageOcrFallback) {
          annotationClientForRunner = OcrFallbackMediaAnnotationClient(
            primaryClient: annotationClientForRunner,
            languageHints: configuredOcrHints,
          );
        }

        final client = (!geoReverseEnabled || annotationClientForRunner == null)
            ? (annotationClientForRunner ?? cloudClient)
            : _CompositeMediaEnrichmentClient(
                placeClient: cloudClient,
                annotationClient: annotationClientForRunner,
              );

        final runner = MediaEnrichmentRunner(
          store: store,
          client: client,
          settings: MediaEnrichmentRunnerSettings(
            annotationEnabled: annotationEnabled,
            annotationWifiOnly: true,
            annotationRequiresNetwork:
                annotationPrimaryClient != null || hasCloudAnnotationModel,
          ),
          getNetwork: getNetwork,
        );

        result = await runner.runOnce(
          allowAnnotationCellular: !imageWifiOnly,
        );
        if (!mounted) return;
      }

      final didEnrichAny = processedUrl > 0 ||
          processedDocs > 0 ||
          processedAutoPdfOcr > 0 ||
          processedAutoDocxOcr > 0 ||
          processedAutoVideoOcr > 0 ||
          processedAudioTranscripts > 0 ||
          result.didEnrichAny;
      if (didEnrichAny) {
        syncEngine?.notifyExternalChange();
      }

      if (result.needsAnnotationCellularConfirmation &&
          !_cellularPromptShown &&
          imageWifiOnly &&
          lastNetwork == MediaEnrichmentNetwork.cellular) {
        _cellularPromptShown = true;
        final allowed = await _promptAllowCellular();
        if (!mounted) return;
        if (allowed) {
          try {
            await MediaCapabilityWifiPrefs.write(
              MediaCapabilityWifiScope.imageCaption,
              wifiOnly: false,
            );
            imageWifiOnly = false;
          } catch (_) {
            imageWifiOnly = false;
          }
          await configStore.write(
            Uint8List.fromList(sessionKey),
            MediaAnnotationConfig(
              annotateEnabled: mediaAnnotationConfig.annotateEnabled,
              searchEnabled: mediaAnnotationConfig.searchEnabled,
              allowCellular: true,
              providerMode: mediaAnnotationConfig.providerMode,
              byokProfileId: mediaAnnotationConfig.byokProfileId,
              cloudModelName: mediaAnnotationConfig.cloudModelName,
            ),
          );
          if (!mounted) return;
          _schedule(const Duration(milliseconds: 600));
          return;
        }
      }

      if (!didEnrichAny) {
        _schedule(_kIdleInterval);
        return;
      }
      _schedule(_kDrainInterval);
    } catch (_) {
      if (!mounted) return;
      _schedule(_kFailureInterval);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
