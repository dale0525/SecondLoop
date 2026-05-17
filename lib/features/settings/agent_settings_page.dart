import 'package:flutter/material.dart';

import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_tab_bar.dart';
import 'agent_settings_models.dart';
import 'ai_settings_page.dart';
import 'cloud_account_page.dart';
import 'cloud_runtime_mode_page.dart';
import 'diagnostics_page.dart';

final class AgentSettingsPage extends StatefulWidget {
  const AgentSettingsPage({super.key});

  @override
  State<AgentSettingsPage> createState() => _AgentSettingsPageState();
}

final class _AgentSettingsPageState extends State<AgentSettingsPage> {
  AgentSettingsTab _selectedTab = AgentSettingsTab.account;

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.agentUi;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AgentTabBar(
              tabs: [
                AgentTabItem(
                  id: AgentSettingsTab.account.id,
                  label: t.tabs.account,
                ),
                AgentTabItem(
                  id: AgentSettingsTab.connection.id,
                  label: t.tabs.connection,
                ),
                AgentTabItem(
                  id: AgentSettingsTab.permissions.id,
                  label: t.tabs.permissions,
                ),
                AgentTabItem(
                  id: AgentSettingsTab.memory.id,
                  label: t.tabs.memory,
                ),
                AgentTabItem(
                  id: AgentSettingsTab.activity.id,
                  label: t.tabs.activity,
                ),
              ],
              selectedId: _selectedTab.id,
              onSelected: (id) {
                setState(() {
                  _selectedTab = AgentSettingsTab.values.firstWhere(
                    (tab) => tab.id == id,
                  );
                });
              },
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            Expanded(child: _buildSelectedTab()),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTab() {
    return switch (_selectedTab) {
      AgentSettingsTab.account => _SettingsSection(
          rows: [
            _SettingsRow(
              title: context.t.settings.agentUi.account.profile,
              body: context.t.settings.agentUi.account.profileBody,
            ),
            _SettingsRow(
              title: context.t.settings.agentUi.account.plan,
              body: context.t.settings.agentUi.account.planBody,
            ),
            _SettingsRow(
              title: context.t.settings.agentUi.account.billing,
              body: context.t.settings.agentUi.account.billingBody,
            ),
            _SettingsRow(
              title: context.t.settings.agentUi.account.security,
              body: context.t.settings.agentUi.account.securityBody,
            ),
            _SettingsDeepLink(
              buttonKey: const ValueKey('agent_settings_open_cloud_account'),
              label: context.t.settings.agentUi.links.cloudAccount,
              pageBuilder: (_) => const CloudAccountPage(),
            ),
          ],
        ),
      AgentSettingsTab.connection => _SettingsSection(
          rows: [
            _SettingsRow(
              title: context.t.settings.agentUi.connection.runtimeMode,
              body: context.t.settings.agentUi.connection.runtimeModeBody,
            ),
            _SettingsRow(
              title: context.t.settings.agentUi.connection.connectionHealth,
              body: context.t.settings.agentUi.connection.connectionHealthBody,
            ),
            _SettingsDeepLink(
              buttonKey: const ValueKey('agent_settings_open_runtime_mode'),
              label: context.t.settings.agentUi.links.runtimeMode,
              pageBuilder: (_) => const CloudRuntimeModePage(),
            ),
          ],
        ),
      AgentSettingsTab.permissions => _SettingsSection(
          rows: [
            _SettingsRow(
              title: context.t.settings.agentUi.permissions.allowedActions,
              body: context.t.settings.agentUi.permissions.allowedActionsBody,
            ),
            _SettingsDeepLink(
              buttonKey: const ValueKey('agent_settings_open_ai_settings'),
              label: context.t.settings.agentUi.links.aiSettings,
              pageBuilder: (_) => const AiSettingsPage(),
            ),
          ],
        ),
      AgentSettingsTab.memory => _SettingsSection(
          rows: [
            _SettingsRow(
              title: context.t.settings.agentUi.memory.behaviorToggles,
              body: context.t.settings.agentUi.memory.behaviorTogglesBody,
            ),
          ],
        ),
      AgentSettingsTab.activity => _SettingsSection(
          rows: [
            _SettingsRow(
              title: context.t.settings.agentUi.activity.timeline,
              body: context.t.settings.agentUi.activity.timelineBody,
            ),
            _SettingsRow(
              title: context.t.settings.agentUi.activity.diagnosticExport,
              body: context.t.settings.agentUi.activity.diagnosticExportBody,
            ),
            _SettingsDeepLink(
              buttonKey: const ValueKey('agent_settings_open_diagnostics'),
              label: context.t.settings.agentUi.links.diagnostics,
              pageBuilder: (_) => const DiagnosticsPage(),
            ),
          ],
        ),
    };
  }
}

final class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) => rows[index],
      separatorBuilder: (_, __) =>
          const SizedBox(height: AgentDesignTokens.gapMd),
      itemCount: rows.length,
    );
  }
}

final class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SlSurface(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AgentDesignTokens.gapXs),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

final class _SettingsDeepLink extends StatelessWidget {
  const _SettingsDeepLink({
    required this.buttonKey,
    required this.label,
    required this.pageBuilder,
  });

  final Key buttonKey;
  final String label;
  final WidgetBuilder pageBuilder;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: buttonKey,
        onPressed: () {
          pushPageWithInheritedScopes(
            Navigator.of(context),
            context,
            pageBuilder(context),
          );
        },
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: Text(label),
      ),
    );
  }
}
