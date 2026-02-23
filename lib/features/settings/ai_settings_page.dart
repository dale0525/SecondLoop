import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/ai/ask_ai_source_prefs.dart';
import '../../core/ai/embeddings_data_consent_prefs.dart';
import '../../core/ai/embeddings_source_prefs.dart';
import '../../core/ai/media_capability_wifi_prefs.dart';
import '../../core/ai/semantic_parse_data_consent_prefs.dart';
import '../../core/ai/media_source_prefs.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'cloud_account_page.dart';
import 'embedding_profiles_page.dart';
import 'llm_profiles_page.dart';
import 'media_annotation_settings_page.dart';

part 'ai_settings_page_ui.dart';

enum AiSettingsSection {
  askAi,
  embeddings,
  mediaUnderstanding,
}

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({
    this.focusSection,
    this.highlightFocus = false,
    this.focusMediaLocalCapabilityCard = false,
    super.key,
  });

  final AiSettingsSection? focusSection;
  final bool highlightFocus;
  final bool focusMediaLocalCapabilityCard;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _askAiSectionAnchorKey = GlobalKey();
  final GlobalKey _embeddingsSectionAnchorKey = GlobalKey();
  final GlobalKey _mediaSectionAnchorKey = GlobalKey();
  final GlobalKey _mediaLocalCapabilityEntryAnchorKey = GlobalKey();

  bool _didRunInitialFocus = false;
  AiSettingsSection? _highlightedSection;

  AskAiRouteKind _askAiRoute = AskAiRouteKind.needsSetup;
  AskAiSourcePreference _askAiPreference = AskAiSourcePreference.auto;
  bool _askAiLoading = true;
  bool _askAiPreferenceSaving = false;
  int _askAiLoadGeneration = 0;

  EmbeddingsSourceRouteKind _embeddingsRoute = EmbeddingsSourceRouteKind.local;
  EmbeddingsSourcePreference _embeddingsPreference =
      EmbeddingsSourcePreference.auto;
  bool _embeddingsLoading = true;
  bool _embeddingsPreferenceSaving = false;
  int _embeddingsLoadGeneration = 0;

  MediaSourceRouteKind _mediaRoute = MediaSourceRouteKind.local;
  MediaSourcePreference _mediaPreference = MediaSourcePreference.auto;
  bool _mediaLoading = true;
  bool _mediaPreferenceSaving = false;
  bool _imageWifiOnly = true;
  bool _imageWifiSaving = false;
  int _mediaLoadGeneration = 0;

  bool _automationLoading = true;
  bool _automationSaving = false;
  bool? _cloudEmbeddingsEnabled;
  bool _cloudEmbeddingsConfigured = false;
  bool? _semanticParseEnabled;
  bool _semanticParseConfigured = false;
  bool _byokConfigured = false;
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
      AiSettingsSection.askAi => _askAiSectionAnchorKey,
      AiSettingsSection.embeddings => _embeddingsSectionAnchorKey,
      AiSettingsSection.mediaUnderstanding => _mediaSectionAnchorKey,
    };
  }

  bool _shouldFocusMediaLocalCapabilityEntry(AiSettingsSection section) {
    if (section != AiSettingsSection.mediaUnderstanding) return false;
    if (!widget.focusMediaLocalCapabilityCard) return false;
    return AppBackendScope.maybeOf(context) != null &&
        SessionScope.maybeOf(context) != null;
  }

  GlobalKey _focusAnchorKeyOf(AiSettingsSection section) {
    if (_shouldFocusMediaLocalCapabilityEntry(section)) {
      return _mediaLocalCapabilityEntryAnchorKey;
    }
    return _sectionAnchorKeyOf(section);
  }

  Future<void> _nudgeTowardsMediaLocalCapabilityEntry({
    required bool disableAnimations,
  }) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nextOffset = (position.pixels + position.viewportDimension * 0.9)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((nextOffset - position.pixels).abs() < 0.5) return;

    if (disableAnimations) {
      position.jumpTo(nextOffset);
      return;
    }

    await _scrollController.animateTo(
      nextOffset,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<(bool cloudAvailable, String gatewayBaseUrl, String idToken)>
      _readCloudAvailabilityContext() async {
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

    final token = cloudIdToken?.trim() ?? '';
    final baseUrl = cloudGatewayConfig.baseUrl.trim();
    final cloudAvailable = subscriptionStatus == SubscriptionStatus.entitled &&
        token.isNotEmpty &&
        baseUrl.isNotEmpty;
    return (cloudAvailable, baseUrl, token);
  }

  Future<AskAiRouteKind> _resolveAskAiRouteWithPreference(
    AskAiSourcePreference preference,
  ) async {
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

    String? cloudIdToken;
    try {
      cloudIdToken = await cloudAuthScope?.controller.getIdToken();
    } catch (_) {
      cloudIdToken = null;
    }

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

  Future<EmbeddingsSourceRouteKind> _resolveEmbeddingsRouteWithPreference(
    EmbeddingsSourcePreference preference,
  ) async {
    final backend = AppBackendScope.maybeOf(context);
    if (backend == null) {
      return EmbeddingsSourceRouteKind.local;
    }

    final sessionKey = SessionScope.of(context).sessionKey;
    final (cloudAvailable, _, _) = await _readCloudAvailabilityContext();

    final prefs = await SharedPreferences.getInstance();
    final cloudEmbeddingsSelected =
        prefs.getBool(EmbeddingsDataConsentPrefs.prefsKey) ?? false;

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
      return MediaSourceRouteKind.local;
    }

    final sessionKey = SessionScope.of(context).sessionKey;
    final (cloudAvailable, _, _) = await _readCloudAvailabilityContext();

    var hasByokProfile = false;
    try {
      final profiles = await backend.listLlmProfiles(sessionKey);
      hasByokProfile = profiles.any(
        (p) => p.isActive && p.providerType == 'openai-compatible',
      );
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

    AskAiSourcePreference preference;
    try {
      preference = await AskAiSourcePrefs.read();
    } catch (_) {
      preference = AskAiSourcePreference.auto;
    }

    final route = await _resolveAskAiRouteWithPreference(preference);

    if (!mounted || generation != _askAiLoadGeneration) return;
    setState(() {
      _askAiPreference = preference;
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

    final backend = AppBackendScope.maybeOf(context);
    final sessionKey =
        backend == null ? null : SessionScope.of(context).sessionKey;

    final prefs = await SharedPreferences.getInstance();
    final cloudEmbeddingsEnabled =
        prefs.getBool(EmbeddingsDataConsentPrefs.prefsKey);
    final semanticParseEnabled =
        prefs.getBool(SemanticParseDataConsentPrefs.prefsKey);

    var byokConfigured = false;
    if (backend != null && sessionKey != null) {
      try {
        byokConfigured = await hasActiveLlmProfile(backend, sessionKey);
      } catch (_) {
        byokConfigured = false;
      }
    }

    if (!mounted || generation != _automationLoadGeneration) return;
    setState(() {
      _cloudEmbeddingsEnabled = cloudEmbeddingsEnabled ?? false;
      _cloudEmbeddingsConfigured = cloudEmbeddingsEnabled != null;
      _semanticParseEnabled = semanticParseEnabled ?? false;
      _semanticParseConfigured = semanticParseEnabled != null;
      _byokConfigured = byokConfigured;
      _automationLoading = false;
    });
  }

  Future<void> _setCloudEmbeddingsEnabled(bool enabled) async {
    if (_automationSaving || (_cloudEmbeddingsEnabled ?? false) == enabled) {
      return;
    }

    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final t = context.t;
          return AlertDialog(
            title: Text(t.settings.cloudEmbeddings.dialogTitle),
            content: Text(t.settings.cloudEmbeddings.dialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.common.actions.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.settings.cloudEmbeddings.dialogActions.enable),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !mounted) return;
    }

    setState(() => _automationSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await EmbeddingsDataConsentPrefs.setEnabled(prefs, enabled);
      if (!mounted) return;
      await _reloadAutomationState(forceLoading: false);
      await _reloadEmbeddingsState(forceLoading: false);
    } finally {
      if (mounted) {
        setState(() => _automationSaving = false);
      }
    }
  }

  Future<void> _setSemanticParseEnabled(bool enabled) async {
    if (_automationSaving || (_semanticParseEnabled ?? false) == enabled) {
      return;
    }

    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final t = context.t;
          return AlertDialog(
            title: Text(t.settings.semanticParseAutoActions.dialogTitle),
            content: Text(t.settings.semanticParseAutoActions.dialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.common.actions.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  t.settings.semanticParseAutoActions.dialogActions.enable,
                ),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _automationSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await SemanticParseDataConsentPrefs.setEnabled(prefs, enabled);
      if (!mounted) return;
      await _reloadAutomationState(forceLoading: false);
    } finally {
      if (mounted) {
        setState(() => _automationSaving = false);
      }
    }
  }

  Future<void> _setAskAiPreference(AskAiSourcePreference next) async {
    if (_askAiPreferenceSaving || _askAiPreference == next) return;
    setState(() => _askAiPreferenceSaving = true);

    try {
      await AskAiSourcePrefs.write(next);
      if (!mounted) return;
      setState(() => _askAiPreference = next);
      await _reloadAskAiState(forceLoading: false);
      if (next == AskAiSourcePreference.byok &&
          _askAiRoute != AskAiRouteKind.byok) {
        await _openLlmProfilesForByokSetupAndRefreshRoutes();
      }
    } finally {
      if (mounted) {
        setState(() => _askAiPreferenceSaving = false);
      }
    }
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
        await _openLlmProfilesForByokSetupAndRefreshRoutes(
          providerFilter: LlmProfilesProviderFilter.openAiCompatibleOnly,
        );
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

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EmbeddingProfilesPage(
          focusTarget: EmbeddingProfilesFocusTarget.addProfileForm,
          highlightFocus: true,
        ),
      ),
    );

    if (!mounted) return;
    await _reloadEmbeddingsState(forceLoading: false);
  }

  Future<void> _openLlmProfilesForByokSetupAndRefreshRoutes({
    LlmProfilesProviderFilter providerFilter = LlmProfilesProviderFilter.all,
  }) async {
    if (!mounted) return;
    if (AppBackendScope.maybeOf(context) == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LlmProfilesPage(
          focusTarget: LlmProfilesFocusTarget.addProfileForm,
          highlightFocus: true,
          providerFilter: providerFilter,
        ),
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToAndHighlight(focusSection));
    });
  }

  Future<void> _scrollToAndHighlight(AiSettingsSection section) async {
    if (!mounted) return;

    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    final focusMediaLocalCapability =
        _shouldFocusMediaLocalCapabilityEntry(section);

    final targetContext = _focusAnchorKeyOf(section).currentContext;
    if (targetContext == null) {
      if (focusMediaLocalCapability) {
        final fallbackContext = _sectionAnchorKeyOf(section).currentContext;
        if (fallbackContext != null) {
          await Scrollable.ensureVisible(
            fallbackContext,
            alignment: 0.08,
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
          );
        }
        if (!mounted) return;
        await _nudgeTowardsMediaLocalCapabilityEntry(
          disableAnimations: disableAnimations,
        );
      }

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

  AskAiRouteKind? _preferredAskAiRoute(AskAiSourcePreference preference) {
    return switch (preference) {
      AskAiSourcePreference.auto => null,
      AskAiSourcePreference.cloud => AskAiRouteKind.cloudGateway,
      AskAiSourcePreference.byok => AskAiRouteKind.byok,
    };
  }

  EmbeddingsSourceRouteKind? _preferredEmbeddingsRoute(
    EmbeddingsSourcePreference preference,
  ) {
    return switch (preference) {
      EmbeddingsSourcePreference.auto => null,
      EmbeddingsSourcePreference.cloud =>
        EmbeddingsSourceRouteKind.cloudGateway,
      EmbeddingsSourcePreference.byok => EmbeddingsSourceRouteKind.byok,
      EmbeddingsSourcePreference.local => EmbeddingsSourceRouteKind.local,
    };
  }

  MediaSourceRouteKind? _preferredMediaRoute(MediaSourcePreference preference) {
    return switch (preference) {
      MediaSourcePreference.auto => null,
      MediaSourcePreference.cloud => MediaSourceRouteKind.cloudGateway,
      MediaSourcePreference.byok => MediaSourceRouteKind.byok,
      MediaSourcePreference.local => MediaSourceRouteKind.local,
    };
  }

  String _askAiStatusLabel(BuildContext context) {
    if (_askAiLoading) {
      return context.t.settings.aiSelection.askAi.status.loading;
    }

    final status = context.t.settings.aiSelection.askAi.status;
    return switch (_askAiRoute) {
      AskAiRouteKind.cloudGateway => status.cloud,
      AskAiRouteKind.byok => status.byok,
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
      MediaSourceRouteKind.local => status.local,
    };
  }

  bool _isZhLocale(BuildContext context) {
    return Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
  }

  String _imageLocalSourceSubtitle(BuildContext context) {
    return _isZhLocale(context)
        ? '使用本地文字识别，也就是 OCR。'
        : 'Use local text recognition (OCR) on-device.';
  }

  String _wifiOnlyHint(BuildContext context) {
    return _isZhLocale(context)
        ? '仅Wi-Fi（仅对 SecondLoop Cloud / BYOK 生效，本地能力不受影响）'
        : 'Wi-Fi only (applies to SecondLoop Cloud / BYOK only; local capability is unaffected).';
  }

  String _mediaUnavailableHint(BuildContext context) {
    if (_mediaPreference != MediaSourcePreference.byok) {
      return context
          .t.settings.aiSelection.mediaUnderstanding.preferenceUnavailableHint;
    }

    return _isZhLocale(context)
        ? '媒体 BYOK 仅支持 OpenAI-compatible 配置。请在“API Key（AI 对话）”里新增或激活 OpenAI-compatible profile（Gemini/Anthropic 不能用于图片理解、OCR、音频转写）。'
        : 'Media BYOK only supports OpenAI-compatible profiles. Add or activate an OpenAI-compatible profile in API Keys (Ask AI). Gemini/Anthropic profiles cannot run image understanding, OCR, or audio transcription.';
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
