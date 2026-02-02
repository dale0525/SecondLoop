import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../features/media_enrichment/media_enrichment_runner.dart';
import '../ai/ai_routing.dart';
import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';

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

      final cloudAvailable =
          subscriptionStatus == SubscriptionStatus.entitled &&
              idToken != null &&
              idToken.trim().isNotEmpty &&
              gatewayConfig.baseUrl.trim().isNotEmpty;
      if (!cloudAvailable) {
        _schedule(_kIdleInterval);
        return;
      }

      final runner = MediaEnrichmentRunner(
        store: BackendMediaEnrichmentStore(
          backend: backend,
          sessionKey: Uint8List.fromList(sessionKey),
        ),
        client: CloudGatewayMediaEnrichmentClient(
          backend: backend,
          gatewayBaseUrl: gatewayConfig.baseUrl,
          idToken: idToken,
          annotationModelName: 'gpt-4o-mini',
        ),
        settings: const MediaEnrichmentRunnerSettings(
          annotationEnabled: false,
          annotationWifiOnly: true,
        ),
        getNetwork: () async {
          try {
            return await ConnectivityMediaEnrichmentNetworkProvider().call();
          } catch (_) {
            return MediaEnrichmentNetwork.unknown;
          }
        },
      );

      final result = await runner.runOnce(allowAnnotationCellular: false);

      if (!mounted) return;
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
