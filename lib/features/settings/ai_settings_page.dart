import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
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

enum AiSettingsSection {
  askAi,
  embeddings,
  mediaUnderstanding,
}

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({
    this.focusSection,
    this.highlightFocus = false,
    super.key,
  });

  final AiSettingsSection? focusSection;
  final bool highlightFocus;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _askAiSectionAnchorKey = GlobalKey();
  final GlobalKey _embeddingsSectionAnchorKey = GlobalKey();
  final GlobalKey _mediaSectionAnchorKey = GlobalKey();

  bool _didRunInitialFocus = false;
  AiSettingsSection? _highlightedSection;

  Future<AskAiRouteKind>? _askAiRouteFuture;
  Timer? _clearHighlightTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _askAiRouteFuture = _resolveAskAiRoute();
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

  Future<AskAiRouteKind> _resolveAskAiRoute() async {
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

    try {
      return await decideAskAiRoute(
        backend,
        sessionKey,
        cloudIdToken: cloudIdToken,
        cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
        subscriptionStatus: subscriptionStatus,
      );
    } catch (_) {
      return AskAiRouteKind.needsSetup;
    }
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

    final targetContext = _sectionAnchorKeyOf(section).currentContext;
    if (targetContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_scrollToAndHighlight(section));
      });
      return;
    }

    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;

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

  String _askAiStatusLabel(BuildContext context, AskAiRouteKind route) {
    final status = context.t.settings.aiSelection.askAi.status;
    return switch (route) {
      AskAiRouteKind.cloudGateway => status.cloud,
      AskAiRouteKind.byok => status.byok,
      AskAiRouteKind.needsSetup => status.notConfigured,
    };
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required GlobalKey anchorKey,
    required Key cardKey,
    required AiSettingsSection section,
    required String title,
    required String description,
    required String statusLabel,
    required List<Widget> actions,
    Widget? warning,
  }) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final highlighted = _highlightedSection == section;
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;

    final borderColor = highlighted ? colorScheme.primary : tokens.borderSubtle;
    final backgroundColor = highlighted
        ? colorScheme.primaryContainer.withOpacity(0.28)
        : colorScheme.surface;

    return Container(
      key: anchorKey,
      child: AnimatedContainer(
        key: cardKey,
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.18),
                    blurRadius: 20,
                    spreadRadius: 1,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SlSurface(
            padding: EdgeInsets.zero,
            child: ColoredBox(
              color: backgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(description),
                        const SizedBox(height: 8),
                        Text(
                          statusLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (warning != null) ...[
                          const SizedBox(height: 12),
                          warning,
                        ],
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) const Divider(height: 1),
                  for (var index = 0; index < actions.length; index++) ...[
                    if (index != 0) const Divider(height: 1),
                    actions[index],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.aiSelection;

    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.subtitle),
          const SizedBox(height: 12),
          FutureBuilder<AskAiRouteKind>(
            future: _askAiRouteFuture,
            builder: (context, snapshot) {
              final route = snapshot.connectionState == ConnectionState.done
                  ? (snapshot.data ?? AskAiRouteKind.needsSetup)
                  : AskAiRouteKind.needsSetup;
              final statusLabel =
                  snapshot.connectionState == ConnectionState.done
                      ? _askAiStatusLabel(context, route)
                      : t.askAi.status.loading;

              return _buildSectionCard(
                context,
                anchorKey: _askAiSectionAnchorKey,
                cardKey: const ValueKey('ai_settings_section_ask_ai'),
                section: AiSettingsSection.askAi,
                title: t.askAi.title,
                description: t.askAi.description,
                statusLabel: statusLabel,
                warning: route == AskAiRouteKind.needsSetup
                    ? Container(
                        key: const ValueKey('ai_settings_ask_ai_setup_hint'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withOpacity(0.45),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t.askAi.setupHint)),
                          ],
                        ),
                      )
                    : null,
                actions: [
                  ListTile(
                    key: const ValueKey('ai_settings_open_cloud_account'),
                    title: Text(t.askAi.actions.openCloud),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CloudAccountPage(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    key: const ValueKey('ai_settings_open_llm_profiles'),
                    title: Text(t.askAi.actions.openByok),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LlmProfilesPage(),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            anchorKey: _embeddingsSectionAnchorKey,
            cardKey: const ValueKey('ai_settings_section_embeddings'),
            section: AiSettingsSection.embeddings,
            title: t.embeddings.title,
            description: t.embeddings.description,
            statusLabel: t.embeddings.status,
            actions: [
              ListTile(
                key: const ValueKey('ai_settings_open_embedding_profiles'),
                title: Text(t.embeddings.actions.openEmbeddingProfiles),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmbeddingProfilesPage(),
                    ),
                  );
                },
              ),
              ListTile(
                key:
                    const ValueKey('ai_settings_open_embeddings_cloud_account'),
                title: Text(t.embeddings.actions.openCloudAccount),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CloudAccountPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            anchorKey: _mediaSectionAnchorKey,
            cardKey: const ValueKey('ai_settings_section_media_understanding'),
            section: AiSettingsSection.mediaUnderstanding,
            title: t.mediaUnderstanding.title,
            description: t.mediaUnderstanding.description,
            statusLabel: t.mediaUnderstanding.status,
            actions: [
              ListTile(
                key: const ValueKey('ai_settings_open_media_understanding'),
                title: Text(t.mediaUnderstanding.actions.openSettings),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MediaAnnotationSettingsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
