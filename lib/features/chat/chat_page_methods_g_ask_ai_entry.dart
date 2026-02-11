part of 'chat_page.dart';

extension _ChatPageStateAskAiEntry on _ChatPageState {
  bool get _canAskAiNow =>
      !_composerAskAiRouteLoading &&
      _composerAskAiRoute != AskAiRouteKind.needsSetup;

  bool get _showConfigureAiEntry =>
      !_composerAskAiRouteLoading &&
      _composerAskAiRoute == AskAiRouteKind.needsSetup;

  Future<AskAiRouteKind> _resolveAskAiRouteWithPreference(
    AppBackend backend,
    Uint8List sessionKey, {
    required String? cloudIdToken,
    required CloudGatewayConfig cloudGatewayConfig,
    required SubscriptionStatus subscriptionStatus,
  }) async {
    AskAiRouteKind defaultRoute;
    try {
      defaultRoute = await decideAskAiRoute(
        backend,
        sessionKey,
        cloudIdToken: cloudIdToken,
        cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
        subscriptionStatus: subscriptionStatus,
      );
    } catch (_) {
      return AskAiRouteKind.needsSetup;
    }

    AskAiSourcePreference preference;
    try {
      preference = await AskAiSourcePrefs.read();
    } catch (_) {
      preference = AskAiSourcePreference.auto;
    }

    var hasByokWhenCloudRoute = false;
    if (preference == AskAiSourcePreference.byok &&
        defaultRoute == AskAiRouteKind.cloudGateway) {
      try {
        hasByokWhenCloudRoute = await hasActiveLlmProfile(backend, sessionKey);
      } catch (_) {
        hasByokWhenCloudRoute = false;
      }
    }

    return applyAskAiSourcePreference(
      defaultRoute,
      preference,
      hasByokWhenCloudRoute: hasByokWhenCloudRoute,
    );
  }

  Future<void> _refreshComposerAskAiRoute() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;

    String? cloudIdToken;
    try {
      cloudIdToken = await cloudAuthScope?.controller.getIdToken();
    } catch (_) {
      cloudIdToken = null;
    }

    final nextRoute = await _resolveAskAiRouteWithPreference(
      backend,
      sessionKey,
      cloudIdToken: cloudIdToken,
      cloudGatewayConfig: cloudGatewayConfig,
      subscriptionStatus: subscriptionStatus,
    );

    if (!mounted) return;
    if (_composerAskAiRoute == nextRoute && !_composerAskAiRouteLoading) {
      return;
    }

    _setState(() {
      _composerAskAiRouteLoading = false;
      _composerAskAiRoute = nextRoute;
    });
  }

  Future<void> _openAskAiSettingsFromComposer() async {
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AiSettingsPage(
          focusSection: AiSettingsSection.askAi,
          highlightFocus: true,
        ),
      ),
    );

    if (!mounted) return;
    unawaited(_refreshComposerAskAiRoute());
  }
}
