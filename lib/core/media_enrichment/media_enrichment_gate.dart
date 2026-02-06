import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../features/media_enrichment/media_enrichment_runner.dart';
import '../../features/url_enrichment/url_enrichment_runner.dart';
import '../ai/ai_routing.dart';
import '../backend/app_backend.dart';
import '../backend/native_app_dir.dart';
import '../backend/native_backend.dart';
import '../attachments/attachment_metadata_store.dart';
import '../cloud/cloud_auth_scope.dart';
import '../content_enrichment/content_enrichment_config_store.dart';
import '../media_annotation/media_annotation_config_store.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine_gate.dart';
import 'media_enrichment_availability.dart';
import '../../src/rust/api/media_annotation.dart' as rust_media_annotation;
import '../../src/rust/db.dart';
import '../../i18n/strings.g.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      _timer?.cancel();
      _timer = null;
      _nextRunAt = null;
      return;
    }

    _schedule(const Duration(seconds: 2));
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
      final contentRequiresWifi =
          contentConfig?.mobileBackgroundRequiresWifi ?? true;

      MediaEnrichmentClient? annotationClient;
      var annotationModelName = gatewayConfig.modelName;

      final desiredMode = mediaAnnotationConfig.providerMode.trim();
      final hasGateway = gatewayConfig.baseUrl.trim().isNotEmpty;
      final hasIdToken = (idToken?.trim() ?? '').isNotEmpty;

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

      LlmProfile? activeProfile() {
        for (final p in llmProfiles) {
          if (p.isActive) return p;
        }
        return null;
      }

      if (mediaAnnotationConfig.annotateEnabled) {
        if (desiredMode == 'cloud_gateway') {
          if (subscriptionStatus == SubscriptionStatus.entitled &&
              hasGateway &&
              hasIdToken) {
            annotationModelName =
                mediaAnnotationConfig.cloudModelName?.trim().isNotEmpty == true
                    ? mediaAnnotationConfig.cloudModelName!.trim()
                    : gatewayConfig.modelName;
          }
        } else if (desiredMode == 'byok_profile') {
          final id = mediaAnnotationConfig.byokProfileId?.trim();
          final profile = id == null || id.isEmpty ? null : findProfile(id);
          if (profile != null && profile.providerType == 'openai-compatible') {
            annotationClient = _ByokMediaEnrichmentClient(
              sessionKey: Uint8List.fromList(sessionKey),
              profileId: profile.id,
              modelName: profile.modelName,
              appDirProvider: getNativeAppDir,
            );
          }
        } else {
          // Follow Ask AI, but with "automation" routing rules (Cloud only when entitled).
          final active = activeProfile();
          final allowCloud = subscriptionStatus == SubscriptionStatus.entitled;
          final route = (allowCloud && hasGateway && hasIdToken)
              ? AskAiRouteKind.cloudGateway
              : (active != null
                  ? AskAiRouteKind.byok
                  : AskAiRouteKind.needsSetup);

          if (route == AskAiRouteKind.cloudGateway) {
            annotationModelName = gatewayConfig.modelName;
          } else if (route == AskAiRouteKind.byok &&
              active != null &&
              active.providerType == 'openai-compatible') {
            annotationClient = _ByokMediaEnrichmentClient(
              sessionKey: Uint8List.fromList(sessionKey),
              profileId: active.id,
              modelName: active.modelName,
              appDirProvider: getNativeAppDir,
            );
          }
        }
      }

      final annotationEnabled = mediaAnnotationConfig.annotateEnabled &&
          (annotationClient != null ||
              (annotationModelName.trim().isNotEmpty &&
                  subscriptionStatus == SubscriptionStatus.entitled &&
                  hasGateway &&
                  hasIdToken));

      if (!geoReverseEnabled &&
          !annotationEnabled &&
          !urlFetchEnabled &&
          !documentExtractEnabled) {
        _schedule(_kIdleInterval);
        return;
      }

      final syncEngine = SyncEngineScope.maybeOf(context);

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
      if (documentExtractEnabled) {
        try {
          processedDocs = await backend.processPendingDocumentExtractions(
            Uint8List.fromList(sessionKey),
            limit: 5,
          );
        } catch (_) {
          processedDocs = 0;
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

        final client = annotationClient == null
            ? cloudClient
            : _CompositeMediaEnrichmentClient(
                placeClient: cloudClient,
                annotationClient: annotationClient,
              );

        final runner = MediaEnrichmentRunner(
          store: store,
          client: client,
          settings: MediaEnrichmentRunnerSettings(
            annotationEnabled: annotationEnabled,
            annotationWifiOnly: true,
          ),
          getNetwork: getNetwork,
        );

        result = await runner.runOnce(
          allowAnnotationCellular: mediaAnnotationConfig.allowCellular,
        );
        if (!mounted) return;
      }

      final didEnrichAny =
          processedUrl > 0 || processedDocs > 0 || result.didEnrichAny;
      if (didEnrichAny) {
        syncEngine?.notifyExternalChange();
      }

      if (result.needsAnnotationCellularConfirmation &&
          !_cellularPromptShown &&
          !mediaAnnotationConfig.allowCellular &&
          lastNetwork == MediaEnrichmentNetwork.cellular) {
        _cellularPromptShown = true;
        final allowed = await _promptAllowCellular();
        if (!mounted) return;
        if (allowed) {
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

final class _CompositeMediaEnrichmentClient implements MediaEnrichmentClient {
  const _CompositeMediaEnrichmentClient({
    required this.placeClient,
    required this.annotationClient,
  });

  final MediaEnrichmentClient placeClient;
  final MediaEnrichmentClient annotationClient;

  @override
  String get annotationModelName => annotationClient.annotationModelName;

  @override
  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  }) =>
      placeClient.reverseGeocode(lat: lat, lon: lon, lang: lang);

  @override
  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) =>
      annotationClient.annotateImage(
        lang: lang,
        mimeType: mimeType,
        imageBytes: imageBytes,
      );
}

final class _ByokMediaEnrichmentClient implements MediaEnrichmentClient {
  const _ByokMediaEnrichmentClient({
    required Uint8List sessionKey,
    required this.profileId,
    required this.modelName,
    required this.appDirProvider,
  }) : _sessionKey = sessionKey;

  final Uint8List _sessionKey;
  final String profileId;
  final String modelName;
  final Future<String> Function() appDirProvider;

  @override
  String get annotationModelName => modelName;

  @override
  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  }) {
    throw StateError('reverse_geocode_not_available_for_byok_annotation');
  }

  @override
  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    final appDir = await appDirProvider();
    return rust_media_annotation.mediaAnnotationByokProfile(
      appDir: appDir,
      key: _sessionKey,
      profileId: profileId,
      localDay: _MediaEnrichmentGateState._formatLocalDayKey(DateTime.now()),
      lang: lang,
      mimeType: mimeType,
      imageBytes: imageBytes,
    );
  }
}

final class _GatedMediaEnrichmentStore implements MediaEnrichmentStore {
  const _GatedMediaEnrichmentStore({
    required this.baseStore,
    required this.placesEnabled,
    required this.annotationEnabled,
  });

  final MediaEnrichmentStore baseStore;
  final bool placesEnabled;
  final bool annotationEnabled;

  @override
  Future<List<MediaEnrichmentPlaceItem>> listDuePlaces({
    required int nowMs,
    int limit = 5,
  }) {
    if (!placesEnabled) return Future.value(const <MediaEnrichmentPlaceItem>[]);
    return baseStore.listDuePlaces(nowMs: nowMs, limit: limit);
  }

  @override
  Future<List<MediaEnrichmentAnnotationItem>> listDueAnnotations({
    required int nowMs,
    int limit = 5,
  }) {
    if (!annotationEnabled) {
      return Future.value(const <MediaEnrichmentAnnotationItem>[]);
    }
    return baseStore.listDueAnnotations(nowMs: nowMs, limit: limit);
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata({
    required String attachmentSha256,
  }) =>
      baseStore.readAttachmentExifMetadata(attachmentSha256: attachmentSha256);

  @override
  Future<Uint8List> readAttachmentBytes({required String attachmentSha256}) =>
      baseStore.readAttachmentBytes(attachmentSha256: attachmentSha256);

  @override
  Future<void> markPlaceOk({
    required String attachmentSha256,
    required String lang,
    required String payloadJson,
    required int nowMs,
  }) =>
      baseStore.markPlaceOk(
        attachmentSha256: attachmentSha256,
        lang: lang,
        payloadJson: payloadJson,
        nowMs: nowMs,
      );

  @override
  Future<void> markPlaceFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) =>
      baseStore.markPlaceFailed(
        attachmentSha256: attachmentSha256,
        error: error,
        attempts: attempts,
        nextRetryAtMs: nextRetryAtMs,
        nowMs: nowMs,
      );

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) =>
      baseStore.markAnnotationOk(
        attachmentSha256: attachmentSha256,
        lang: lang,
        modelName: modelName,
        payloadJson: payloadJson,
        nowMs: nowMs,
      );

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) =>
      baseStore.markAnnotationFailed(
        attachmentSha256: attachmentSha256,
        error: error,
        attempts: attempts,
        nextRetryAtMs: nextRetryAtMs,
        nowMs: nowMs,
      );
}

final class _BackendUrlEnrichmentStore implements UrlEnrichmentStore {
  _BackendUrlEnrichmentStore({
    required this.backend,
    required Uint8List sessionKey,
    AttachmentMetadataStore? metadataStore,
  })  : _sessionKey = Uint8List.fromList(sessionKey),
        _metadataStore = metadataStore ?? const RustAttachmentMetadataStore();

  final NativeAppBackend backend;
  final Uint8List _sessionKey;
  final AttachmentMetadataStore _metadataStore;

  @override
  Future<List<UrlEnrichmentJob>> listDueUrlAnnotations({
    required int nowMs,
    int limit = 5,
  }) async {
    final rows = await backend.listDueUrlManifestAttachmentAnnotations(
      _sessionKey,
      nowMs: nowMs,
      limit: limit,
    );
    return rows
        .map(
          (r) => UrlEnrichmentJob(
            attachmentSha256: r.attachmentSha256,
            lang: r.lang,
            status: r.status,
            attempts: r.attempts,
            nextRetryAtMs: r.nextRetryAtMs,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Uint8List> readAttachmentBytes({required String attachmentSha256}) =>
      backend.readAttachmentBytes(_sessionKey, sha256: attachmentSha256);

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) =>
      backend.markAttachmentAnnotationOkJson(
        _sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        modelName: modelName,
        payloadJson: payloadJson,
        nowMs: nowMs,
      );

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) =>
      backend.markAttachmentAnnotationFailed(
        _sessionKey,
        attachmentSha256: attachmentSha256,
        attempts: attempts,
        nextRetryAtMs: nextRetryAtMs,
        lastError: error,
        nowMs: nowMs,
      );

  @override
  Future<void> upsertAttachmentTitle({
    required String attachmentSha256,
    required String title,
  }) =>
      _metadataStore.upsert(
        _sessionKey,
        attachmentSha256: attachmentSha256,
        title: title,
      );
}
