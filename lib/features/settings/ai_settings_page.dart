import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/ai/embeddings_data_consent_prefs.dart';
import '../../core/ai/embeddings_source_prefs.dart';
import '../../core/ai/media_capability_wifi_prefs.dart';
import '../../core/ai/semantic_parse_data_consent_prefs.dart';
import '../../core/ai/media_source_prefs.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/models/app_models.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'embedding_profiles_page.dart';
import 'llm_profiles_page.dart';
import 'ai_ask_ai_settings_page.dart';
import 'ai_smart_organization_settings_page.dart';

part 'ai_settings_page_ui.dart';

enum AiSettingsSection {
  askAi,
  smartOrganization,
  embeddings,
  mediaUnderstanding,
}

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({
    this.focusSection,
    this.highlightFocus = false,
    this.expandAdvancedOnOpen = false,
    super.key,
  });

  final AiSettingsSection? focusSection;
  final bool highlightFocus;
  final bool expandAdvancedOnOpen;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _askAiSectionAnchorKey = GlobalKey();
  final GlobalKey _advancedAskAiSectionAnchorKey = GlobalKey();
  final GlobalKey _smartOrganizationSectionAnchorKey = GlobalKey();
  final GlobalKey _embeddingsSectionAnchorKey = GlobalKey();
  final GlobalKey _mediaSectionAnchorKey = GlobalKey();

  bool _didRunInitialFocus = false;
  bool _advancedSettingsExpanded = false;
  AiSettingsSection? _highlightedSection;

  AskAiRouteKind _askAiRoute = AskAiRouteKind.needsSetup;
  bool _askAiLoading = true;
  int _askAiLoadGeneration = 0;

  EmbeddingsSourceRouteKind _embeddingsRoute =
      EmbeddingsSourceRouteKind.needsSetup;
  EmbeddingsSourcePreference _embeddingsPreference =
      EmbeddingsSourcePreference.auto;
  bool _embeddingsLoading = true;
  bool _embeddingsPreferenceSaving = false;
  int _embeddingsLoadGeneration = 0;

  MediaSourceRouteKind _mediaRoute = MediaSourceRouteKind.needsSetup;
  MediaSourcePreference _mediaPreference = MediaSourcePreference.auto;
  bool _mediaLoading = true;
  bool _mediaPreferenceSaving = false;
  bool _imageWifiOnly = true;
  bool _imageWifiSaving = false;
  int _mediaLoadGeneration = 0;

  bool _automationLoading = true;
  bool? _cloudEmbeddingsEnabled;
  bool _cloudEmbeddingsConfigured = false;
  bool? _semanticParseEnabled;
  int _automationLoadGeneration = 0;

  Timer? _clearHighlightTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_reloadAskAiState(forceLoading: _askAiLoading));
    unawaited(_reloadEmbeddingsState(forceLoading: _embeddingsLoading));
    unawaited(_reloadMediaState(forceLoading: _mediaLoading));
    unawaited(_reloadAutomationState(forceLoading: _automationLoading));
    _scheduleInitialFocus();
  }

  @override
  void dispose() {
    _clearHighlightTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _sectionAnchorKeyOf(AiSettingsSection section) {
    return switch (section) {
      AiSettingsSection.askAi => _advancedSettingsExpanded
          ? _advancedAskAiSectionAnchorKey
          : _askAiSectionAnchorKey,
      AiSettingsSection.smartOrganization => _smartOrganizationSectionAnchorKey,
      AiSettingsSection.embeddings => _embeddingsSectionAnchorKey,
      AiSettingsSection.mediaUnderstanding => _mediaSectionAnchorKey,
    };
  }

  bool _focusSectionRequiresAdvancedExpansion(AiSettingsSection section) {
    return section == AiSettingsSection.askAi ||
        section == AiSettingsSection.embeddings ||
        section == AiSettingsSection.mediaUnderstanding;
  }

  Future<(bool cloudAvailable, String gatewayBaseUrl, String idToken)>
      _readCloudAvailabilityContext() async {
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;

    final cloudIdToken = await readCloudCapabilityIdToken(
      cloudAuthScope?.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );

    final token = cloudIdToken?.trim() ?? '';
    final baseUrl = cloudGatewayConfig.baseUrl.trim();
    final cloudAvailable = subscriptionStatus == SubscriptionStatus.entitled &&
        token.isNotEmpty &&
        baseUrl.isNotEmpty;
    return (cloudAvailable, baseUrl, token);
  }

  Future<AskAiRouteKind> _resolveAskAiRoute() async {
    final backend = AppBackendScope.maybeOf(context);
    if (backend == null) {
      return AskAiRouteKind.needsSetup;
    }

    final sessionKey = SessionScope.of(context).sessionKey;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;

    final cloudIdToken = await readCloudCapabilityIdToken(
      cloudAuthScope?.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );

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

    return defaultRoute;
  }

  Future<EmbeddingsSourceRouteKind> _resolveEmbeddingsRouteWithPreference(
    EmbeddingsSourcePreference preference,
  ) async {
    final backend = AppBackendScope.maybeOf(context);
    if (backend == null) {
      return EmbeddingsSourceRouteKind.needsSetup;
    }

    final sessionKey = SessionScope.of(context).sessionKey;
    final (cloudAvailable, _, _) = await _readCloudAvailabilityContext();

    final prefs = await SharedPreferences.getInstance();
    final cloudEmbeddingsSelected =
        EmbeddingsDataConsentPrefs.readEffectiveEnabled(prefs);

    var hasByokProfile = false;
    try {
      final profiles = await backend.listEmbeddingProfiles(sessionKey);
      hasByokProfile = profiles.any((p) => p.isActive);
    } catch (_) {
      hasByokProfile = false;
    }

    return resolveEmbeddingsSourceRoute(
      preference,
      cloudEmbeddingsSelected: cloudEmbeddingsSelected,
      cloudAvailable: cloudAvailable,
      hasByokProfile: hasByokProfile,
    );
  }

  Future<MediaSourceRouteKind> _resolveMediaRouteWithPreference(
    MediaSourcePreference preference,
  ) async {
    final backend = AppBackendScope.maybeOf(context);
    if (backend == null) {
      return MediaSourceRouteKind.needsSetup;
    }

    final sessionKey = SessionScope.of(context).sessionKey;
    final (cloudAvailable, _, _) = await _readCloudAvailabilityContext();

    var hasByokProfile = false;
    try {
      final profiles = await backend.listLlmProfiles(sessionKey);
      hasByokProfile = profiles.any(_isActiveOpenAiCompatibleProfile);
    } catch (_) {
      hasByokProfile = false;
    }

    return resolveMediaSourceRoute(
      preference,
      cloudAvailable: cloudAvailable,
      hasByokProfile: hasByokProfile,
    );
  }

  Future<void> _reloadAskAiState({required bool forceLoading}) async {
    final generation = ++_askAiLoadGeneration;
    if (forceLoading && mounted) {
      setState(() => _askAiLoading = true);
    }

    final route = await _resolveAskAiRoute();

    if (!mounted || generation != _askAiLoadGeneration) return;
    setState(() {
      _askAiRoute = route;
      _askAiLoading = false;
    });
  }

  Future<void> _reloadEmbeddingsState({required bool forceLoading}) async {
    final generation = ++_embeddingsLoadGeneration;
    if (forceLoading && mounted) {
      setState(() => _embeddingsLoading = true);
    }

    EmbeddingsSourcePreference preference;
    try {
      preference = await EmbeddingsSourcePrefs.read();
    } catch (_) {
      preference = EmbeddingsSourcePreference.auto;
    }

    final route = await _resolveEmbeddingsRouteWithPreference(preference);

    if (!mounted || generation != _embeddingsLoadGeneration) return;
    setState(() {
      _embeddingsPreference = preference;
      _embeddingsRoute = route;
      _embeddingsLoading = false;
    });
  }

  Future<void> _reloadMediaState({required bool forceLoading}) async {
    final generation = ++_mediaLoadGeneration;
    if (forceLoading && mounted) {
      setState(() => _mediaLoading = true);
    }

    MediaSourcePreference preference;
    try {
      preference = await MediaSourcePrefs.read();
    } catch (_) {
      preference = MediaSourcePreference.auto;
    }

    bool imageWifiOnly;
    try {
      imageWifiOnly = await MediaCapabilityWifiPrefs.readImageWifiOnly(
        fallbackWifiOnly: true,
      );
    } catch (_) {
      imageWifiOnly = true;
    }

    final route = await _resolveMediaRouteWithPreference(preference);

    if (!mounted || generation != _mediaLoadGeneration) return;
    setState(() {
      _mediaPreference = preference;
      _mediaRoute = route;
      _imageWifiOnly = imageWifiOnly;
      _mediaLoading = false;
    });
  }

  Future<void> _reloadAutomationState({required bool forceLoading}) async {
    final generation = ++_automationLoadGeneration;
    if (forceLoading && mounted) {
      setState(() => _automationLoading = true);
    }

    final prefs = await SharedPreferences.getInstance();
    final cloudEmbeddingsEnabled =
        EmbeddingsDataConsentPrefs.readEffectiveEnabled(prefs);
    final semanticParseEnabled =
        SemanticParseDataConsentPrefs.readEffectiveEnabled(prefs);

    if (!mounted || generation != _automationLoadGeneration) return;
    setState(() {
      _cloudEmbeddingsEnabled = cloudEmbeddingsEnabled;
      _cloudEmbeddingsConfigured = true;
      _semanticParseEnabled = semanticParseEnabled;
      _automationLoading = false;
    });
  }

  bool get _smartOrganizationEnabled {
    return (_semanticParseEnabled ?? false) ||
        (_cloudEmbeddingsEnabled ?? false);
  }

  void _setAdvancedSettingsExpanded(bool expanded) {
    if (_advancedSettingsExpanded == expanded) return;
    setState(() => _advancedSettingsExpanded = expanded);
  }

  Future<void> _setEmbeddingsPreference(EmbeddingsSourcePreference next) async {
    if (_embeddingsPreferenceSaving || _embeddingsPreference == next) return;
    setState(() => _embeddingsPreferenceSaving = true);

    try {
      await EmbeddingsSourcePrefs.write(next);
      if (!mounted) return;
      setState(() => _embeddingsPreference = next);
      await _reloadEmbeddingsState(forceLoading: false);
      if (next == EmbeddingsSourcePreference.byok &&
          _embeddingsRoute != EmbeddingsSourceRouteKind.byok) {
        await _openEmbeddingProfilesForByokSetupAndRefreshRoutes();
      }
    } finally {
      if (mounted) {
        setState(() => _embeddingsPreferenceSaving = false);
      }
    }
  }

  Future<void> _setMediaPreference(MediaSourcePreference next) async {
    if (_mediaPreferenceSaving || _mediaPreference == next) return;
    setState(() => _mediaPreferenceSaving = true);

    try {
      await MediaSourcePrefs.write(next);
      if (!mounted) return;
      setState(() => _mediaPreference = next);
      await _reloadMediaState(forceLoading: false);
      if (next == MediaSourcePreference.byok &&
          _mediaRoute != MediaSourceRouteKind.byok) {
        await _openLlmProfilesForByokSetupAndRefreshRoutes();
      }
    } finally {
      if (mounted) {
        setState(() => _mediaPreferenceSaving = false);
      }
    }
  }

  Future<void> _setImageWifiOnly(bool wifiOnly) async {
    if (_imageWifiSaving || _imageWifiOnly == wifiOnly) return;
    setState(() => _imageWifiSaving = true);

    try {
      await MediaCapabilityWifiPrefs.write(
        MediaCapabilityWifiScope.imageCaption,
        wifiOnly: wifiOnly,
      );
      if (!mounted) return;
      setState(() => _imageWifiOnly = wifiOnly);
    } finally {
      if (mounted) {
        setState(() => _imageWifiSaving = false);
      }
    }
  }

  Future<void> _openEmbeddingProfilesForByokSetupAndRefreshRoutes() async {
    if (!mounted) return;
    if (AppBackendScope.maybeOf(context) == null) return;

    await pushPageWithInheritedScopes(
      Navigator.of(context),
      context,
      const EmbeddingProfilesPage(
        focusTarget: EmbeddingProfilesFocusTarget.addProfileForm,
        highlightFocus: true,
      ),
    );

    if (!mounted) return;
    await _reloadEmbeddingsState(forceLoading: false);
  }

  Future<void> _openLlmProfilesForByokSetupAndRefreshRoutes() async {
    if (!mounted) return;
    if (AppBackendScope.maybeOf(context) == null) return;

    await pushPageWithInheritedScopes(
      Navigator.of(context),
      context,
      const LlmProfilesPage(
        focusTarget: LlmProfilesFocusTarget.addProfileForm,
        highlightFocus: true,
      ),
    );

    if (!mounted) return;
    await _reloadAskAiState(forceLoading: false);
    await _reloadEmbeddingsState(forceLoading: false);
    await _reloadMediaState(forceLoading: false);
    await _reloadAutomationState(forceLoading: false);
  }

  void _scheduleInitialFocus() {
    if (_didRunInitialFocus) return;
    final focusSection = widget.focusSection;
    if (focusSection == null) return;
    _didRunInitialFocus = true;

    if (widget.expandAdvancedOnOpen ||
        _focusSectionRequiresAdvancedExpansion(focusSection)) {
      _advancedSettingsExpanded = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToAndHighlight(focusSection));
    });
  }

  Future<void> _scrollToAndHighlight(AiSettingsSection section) async {
    if (!mounted) return;

    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    final targetContext = _sectionAnchorKeyOf(section).currentContext;
    if (targetContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_scrollToAndHighlight(section));
      });
      return;
    }

    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration:
          disableAnimations ? Duration.zero : const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !widget.highlightFocus) return;

    _clearHighlightTimer?.cancel();
    setState(() => _highlightedSection = section);
    if (disableAnimations) return;

    _clearHighlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted || _highlightedSection != section) return;
      setState(() => _highlightedSection = null);
    });
  }

  EmbeddingsSourceRouteKind? _preferredEmbeddingsRoute(
    EmbeddingsSourcePreference preference,
  ) {
    return switch (preference) {
      EmbeddingsSourcePreference.auto => null,
      EmbeddingsSourcePreference.cloud =>
        EmbeddingsSourceRouteKind.cloudGateway,
      EmbeddingsSourcePreference.byok => EmbeddingsSourceRouteKind.byok,
      EmbeddingsSourcePreference.local => null,
    };
  }

  MediaSourceRouteKind? _preferredMediaRoute(MediaSourcePreference preference) {
    return switch (preference) {
      MediaSourcePreference.auto => null,
      MediaSourcePreference.cloud => MediaSourceRouteKind.cloudGateway,
      MediaSourcePreference.byok => MediaSourceRouteKind.byok,
      MediaSourcePreference.local => null,
    };
  }

  String _askAiStatusLabel(BuildContext context) {
    if (_askAiLoading) {
      return context.t.settings.aiSelection.askAi.status.loading;
    }

    final status = context.t.settings.aiSelection.askAi.status;
    return switch (_askAiRoute) {
      AskAiRouteKind.cloudGateway => status.cloud,
      AskAiRouteKind.needsSetup => status.notConfigured,
    };
  }

  String _embeddingsStatusLabel(BuildContext context) {
    if (_embeddingsLoading) {
      return context.t.settings.aiSelection.embeddings.status.loading;
    }

    final status = context.t.settings.aiSelection.embeddings.status;
    return switch (_embeddingsRoute) {
      EmbeddingsSourceRouteKind.cloudGateway => status.cloud,
      EmbeddingsSourceRouteKind.byok => status.byok,
      EmbeddingsSourceRouteKind.needsSetup => status.notConfigured,
      EmbeddingsSourceRouteKind.local => status.local,
    };
  }

  String _mediaStatusLabel(BuildContext context) {
    if (_mediaLoading) {
      return context.t.settings.aiSelection.mediaUnderstanding.status.loading;
    }

    final status = context.t.settings.aiSelection.mediaUnderstanding.status;
    return switch (_mediaRoute) {
      MediaSourceRouteKind.cloudGateway => status.cloud,
      MediaSourceRouteKind.byok => status.byok,
      MediaSourceRouteKind.needsSetup => status.notConfigured,
      MediaSourceRouteKind.local => status.local,
    };
  }

  bool _isZhLocale(BuildContext context) {
    return Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
  }

  String _wifiOnlyHint(BuildContext context) {
    return context.t.settings.mediaAnnotation.connectivity.wifiOnlySubtitle;
  }

  String _mediaUnavailableHint(BuildContext context) {
    if (_mediaPreference != MediaSourcePreference.byok) {
      return context
          .t.settings.aiSelection.mediaUnderstanding.preferenceUnavailableHint;
    }

    return _isZhLocale(context)
        ? '媒体 BYOK 仅支持 OpenAI-compatible 配置。请在“API Key（AI 对话）”里新增或激活 OpenAI-compatible profile。'
        : 'Media BYOK only supports OpenAI-compatible profiles. Add or activate an OpenAI-compatible profile in API Keys (Ask AI).';
  }

  bool _isActiveOpenAiCompatibleProfile(LlmProfile profile) =>
      profile.isActive && profile.providerType == 'openai-compatible';

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
