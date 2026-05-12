import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_tab_bar.dart';
import 'memory_models.dart';
import 'memory_widgets.dart';

final class MemoryPage extends StatefulWidget {
  const MemoryPage({
    this.data,
    super.key,
  });

  final MemoryDemoData? data;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

final class _MemoryPageState extends State<MemoryPage> {
  late final MemoryDemoData _data = widget.data ?? MemoryDemoData.demo();
  AgentMemoryTab _selectedTab = AgentMemoryTab.preferences;

  @override
  Widget build(BuildContext context) {
    final t = context.t.memory.agentUi;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AgentTabBar(
              tabs: [
                AgentTabItem(
                  id: AgentMemoryTab.preferences.id,
                  label: t.tabs.preferences,
                ),
                AgentTabItem(
                  id: AgentMemoryTab.people.id,
                  label: t.tabs.people,
                ),
                AgentTabItem(
                  id: AgentMemoryTab.projects.id,
                  label: t.tabs.projects,
                ),
                AgentTabItem(
                  id: AgentMemoryTab.sources.id,
                  label: t.tabs.sources,
                ),
                AgentTabItem(
                  id: AgentMemoryTab.suggestions.id,
                  label: t.tabs.suggestions,
                ),
              ],
              selectedId: _selectedTab.id,
              onSelected: (id) {
                setState(() {
                  _selectedTab = AgentMemoryTab.values.firstWhere(
                    (tab) => tab.id == id,
                  );
                });
              },
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            Expanded(child: _buildSelectedBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedBody() {
    return switch (_selectedTab) {
      AgentMemoryTab.preferences => MemoryPreferencesBody(
          preferences: _data.preferences,
          suggestions: _data.suggestions,
        ),
      AgentMemoryTab.people => MemoryPeopleBody(people: _data.people),
      AgentMemoryTab.projects => MemoryProjectsBody(projects: _data.projects),
      AgentMemoryTab.sources => MemorySourcesBody(sources: _data.sources),
      AgentMemoryTab.suggestions =>
        MemorySuggestionsBody(suggestions: _data.suggestions),
    };
  }
}
