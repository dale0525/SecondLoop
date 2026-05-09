import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/embeddings_data_consent_prefs.dart';
import '../../core/ai/semantic_parse_data_consent_prefs.dart';
import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'ai_settings_page.dart';

class AiSmartOrganizationSettingsPage extends StatefulWidget {
  const AiSmartOrganizationSettingsPage({super.key});

  @override
  State<AiSmartOrganizationSettingsPage> createState() =>
      _AiSmartOrganizationSettingsPageState();
}

class _AiSmartOrganizationSettingsPageState
    extends State<AiSmartOrganizationSettingsPage> {
  bool _loading = true;
  bool? _cloudEmbeddingsEnabled;
  bool? _semanticParseEnabled;
  bool _byokConfigured = false;
  int _generation = 0;

  bool get _enabled {
    return (_semanticParseEnabled ?? false) ||
        (_cloudEmbeddingsEnabled ?? false);
  }

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
    final prefs = await SharedPreferences.getInstance();

    var byokConfigured = false;
    if (backend != null && sessionKey != null) {
      try {
        byokConfigured = await hasActiveLlmProfile(backend, sessionKey);
      } catch (_) {
        byokConfigured = false;
      }
    }

    if (!mounted || generation != _generation) return;
    setState(() {
      _cloudEmbeddingsEnabled =
          EmbeddingsDataConsentPrefs.readEffectiveEnabled(prefs);
      _semanticParseEnabled =
          SemanticParseDataConsentPrefs.readEffectiveEnabled(prefs);
      _byokConfigured = byokConfigured;
      _loading = false;
    });
  }

  String _statusLabel(BuildContext context) {
    final status = context.t.settings.aiSelection.smartOrganization.status;
    if (_loading) return status.loading;

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final hasCloudAccount =
        (CloudAuthScope.maybeOf(context)?.controller.uid ?? '')
            .trim()
            .isNotEmpty;
    final canUseCloudEmbeddings =
        hasCloudAccount && subscriptionStatus == SubscriptionStatus.entitled;
    final canUseSmartOrganization = canUseCloudEmbeddings || _byokConfigured;

    if (!canUseSmartOrganization) return status.requiresSetup;
    return _enabled ? status.enabled : status.disabled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.aiSelection.smartOrganization;

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
                const SizedBox(height: 8),
                Text(t.privacySummary),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SlSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey(
                      'smart_organization_settings_open_advanced'),
                  title: Text(t.actions.reviewAdvanced),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    pushReplacementPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const AiSettingsPage(
                        focusSection: AiSettingsSection.embeddings,
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
