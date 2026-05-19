import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'ai_settings_page.dart';
import 'cloud_account_page.dart';
import 'cloud_runtime_mode_page.dart';

class AiAskAiSettingsPage extends StatefulWidget {
  const AiAskAiSettingsPage({super.key});

  @override
  State<AiAskAiSettingsPage> createState() => _AiAskAiSettingsPageState();
}

class _AiAskAiSettingsPageState extends State<AiAskAiSettingsPage> {
  AskAiRouteKind _route = AskAiRouteKind.needsSetup;
  bool _loading = true;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload(forceLoading: _loading);
  }

  Future<void> _reload({required bool forceLoading}) async {
    final generation = ++_generation;
    if (forceLoading && mounted) {
      setState(() => _loading = true);
    }

    final backend = AppBackendScope.maybeOf(context);
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);

    AskAiRouteKind route = AskAiRouteKind.needsSetup;
    if (backend != null && sessionKey != null) {
      try {
        final gatewayConfig =
            cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
        final cloudIdToken = await readCloudCapabilityIdToken(
          cloudAuthScope?.controller,
          mode: CloudCapabilityAuthMode.background,
        );

        route = await decideAskAiRoute(
          backend,
          sessionKey,
          cloudIdToken: cloudIdToken,
          cloudGatewayBaseUrl: gatewayConfig.baseUrl,
          subscriptionStatus: subscriptionStatus,
        );
      } catch (_) {
        route = AskAiRouteKind.needsSetup;
      }
    }

    if (!mounted || generation != _generation) return;
    setState(() {
      _route = route;
      _loading = false;
    });
  }

  String _statusLabel(BuildContext context) {
    if (_loading) {
      return context.t.settings.aiSelection.askAi.status.loading;
    }

    final status = context.t.settings.aiSelection.askAi.status;
    return switch (_route) {
      AskAiRouteKind.cloudGateway => status.cloud,
      AskAiRouteKind.needsSetup => status.notConfigured,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.aiSelection.askAi;

    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SlSurface(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(t.description),
                const SizedBox(height: 12),
                Text(
                  _statusLabel(context),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SlSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('ask_ai_settings_open_runtime_mode'),
                  title: Text(context.t.settings.runtimeMode.title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    pushPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const CloudRuntimeModePage(),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('ask_ai_settings_open_cloud_account'),
                  title: Text(
                      context.t.settings.runtimeMode.actions.openCloudAccount),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    pushPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const CloudAccountPage(),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('ask_ai_settings_open_advanced'),
                  title: Text(t.actions.reviewAdvanced),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    pushReplacementPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const AiSettingsPage(
                        focusSection: AiSettingsSection.askAi,
                        highlightFocus: true,
                        expandAdvancedOnOpen: true,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
