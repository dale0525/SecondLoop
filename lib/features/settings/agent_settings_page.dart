import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_tab_bar.dart';
import 'agent_digest_settings_page.dart';
import 'agent_settings_models.dart';
import 'cloud_account_page.dart';
import 'cloud_runtime_mode_page.dart';
import 'diagnostics_page.dart';
import 'settings_ui.dart';

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
    return SettingsPageShell(
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
        _buildSelectedTab(),
      ],
    );
  }

  Widget _buildSelectedTab() {
    return switch (_selectedTab) {
      AgentSettingsTab.account => const CloudAccountSettingsHost(),
      AgentSettingsTab.connection => CloudRuntimeModePanel(
          onOpenManagedPro: () {
            setState(() => _selectedTab = AgentSettingsTab.account);
          },
        ),
      AgentSettingsTab.permissions => _AgentPermissionsPanel(),
      AgentSettingsTab.memory => const AgentDigestSettingsPage(embedded: true),
      AgentSettingsTab.activity => const DiagnosticsPage(embedded: true),
    };
  }
}

class _AgentPermissionsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.agentUi.permissions;
    return SettingsSection(
      children: [
        SettingsRow(
          leading: const Icon(Icons.verified_user_outlined),
          title: t.allowedActions,
          body: t.allowedActionsBody,
        ),
      ],
    );
  }
}
