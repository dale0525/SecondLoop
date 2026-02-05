import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../features/media_enrichment/media_enrichment_runner.dart';
import '../ai/ai_routing.dart';
import '../backend/app_backend.dart';
import '../backend/native_app_dir.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_auth_scope.dart';
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

      if (!geoReverseEnabled && !annotationEnabled) {
        _schedule(_kIdleInterval);
        return;
      }

      final syncEngine = SyncEngineScope.maybeOf(context);

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

      MediaEnrichmentNetwork? lastNetwork;
      final runner = MediaEnrichmentRunner(
        store: store,
        client: client,
        settings: MediaEnrichmentRunnerSettings(
          annotationEnabled: annotationEnabled,
          annotationWifiOnly: true,
        ),
        getNetwork: () async {
          try {
            final network =
                await ConnectivityMediaEnrichmentNetworkProvider().call();
            lastNetwork = network;
            return network;
          } catch (_) {
            return MediaEnrichmentNetwork.unknown;
          }
        },
      );

      final result = await runner.runOnce(
        allowAnnotationCellular: mediaAnnotationConfig.allowCellular,
      );
      if (!mounted) return;
      if (result.didEnrichAny) {
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

      if (!result.didEnrichAny) {
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
