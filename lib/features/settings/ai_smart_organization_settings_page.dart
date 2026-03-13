import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/embeddings_data_consent_prefs.dart';
import '../../core/ai/semantic_parse_data_consent_prefs.dart';
import '../../core/ai/task_priority_ai_enhancement_prefs.dart';
import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'ai_settings_page.dart';
import 'cloud_account_page.dart';
import 'llm_profiles_page.dart';

class AiSmartOrganizationSettingsPage extends StatefulWidget {
  const AiSmartOrganizationSettingsPage({super.key});

  @override
  State<AiSmartOrganizationSettingsPage> createState() =>
      _AiSmartOrganizationSettingsPageState();
}

class _AiSmartOrganizationSettingsPageState
    extends State<AiSmartOrganizationSettingsPage> {
  bool _loading = true;
  bool _saving = false;
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
          prefs.getBool(EmbeddingsDataConsentPrefs.prefsKey) ?? false;
      _semanticParseEnabled =
          prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false;
      _byokConfigured = byokConfigured;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_saving || _enabled == enabled) return;

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final hasCloudAccount =
        (CloudAuthScope.maybeOf(context)?.controller.uid ?? '')
            .trim()
            .isNotEmpty;
    final canUseCloudEmbeddings =
        hasCloudAccount && subscriptionStatus == SubscriptionStatus.entitled;
    final canUseSmartOrganization = canUseCloudEmbeddings || _byokConfigured;

    if (enabled && !canUseSmartOrganization) {
      if (subscriptionStatus == SubscriptionStatus.entitled &&
          !hasCloudAccount) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CloudAccountPage(),
          ),
        );
        if (!mounted) return;
        await _reload(forceLoading: false);
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LlmProfilesPage(),
        ),
      );
      if (!mounted) return;
      await _reload(forceLoading: false);
      return;
    }

    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final t = context.t;
          return AlertDialog(
            title: Text(t.settings.aiSelection.smartOrganization.dialogTitle),
            content: Text(t.settings.aiSelection.smartOrganization.dialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.common.actions.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  t.settings.aiSelection.smartOrganization.dialogActions.enable,
                ),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await SemanticParseDataConsentPrefs.setEnabled(prefs, enabled);
      await EmbeddingsDataConsentPrefs.setEnabled(
        prefs,
        enabled && canUseCloudEmbeddings,
      );
      await TaskPriorityAiEnhancementPrefs.write(enabled);
      if (!mounted) return;
      await _reload(forceLoading: false);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
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
                SwitchListTile(
                  key: const ValueKey('smart_organization_settings_switch'),
                  title: Text(t.title),
                  subtitle: Text(t.privacySummary),
                  value: _enabled,
                  onChanged: _loading || _saving
                      ? null
                      : (value) async {
                          await _setEnabled(value);
                        },
                ),
                if (!_enabled) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey(
                          'smart_organization_settings_recommended_button',
                        ),
                        onPressed: _loading || _saving
                            ? null
                            : () async {
                                await _setEnabled(true);
                              },
                        child: Text(t.actions.useRecommended),
                      ),
                    ),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey(
                      'smart_organization_settings_open_advanced'),
                  title: Text(t.actions.reviewAdvanced),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiSettingsPage(
                          focusSection: AiSettingsSection.embeddings,
                          highlightFocus: true,
                          expandAdvancedOnOpen: true,
                        ),
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
