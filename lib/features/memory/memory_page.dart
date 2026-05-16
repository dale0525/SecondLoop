import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/secretary_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
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
  Future<MemoryDemoData>? _dataFuture;
  AgentMemoryTab _selectedTab = AgentMemoryTab.preferences;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.data == null) {
      _dataFuture ??= _loadData();
    }
  }

  @override
  void didUpdateWidget(MemoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _dataFuture = widget.data == null ? _loadData() : null;
    }
  }

  Future<MemoryDemoData> _loadData() async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend is! SecretaryBackend || session == null) {
      return MemoryDemoData.empty();
    }
    final secretaryBackend = backend as SecretaryBackend;
    final pages = await secretaryBackend.listMemoryPages(
      session.sessionKey,
      state: 'active',
    );
    return _memoryDataFromPages(pages);
  }

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
            Expanded(child: _buildDataBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildDataBody() {
    final data = widget.data;
    if (data != null) return _buildSelectedBody(data);
    return FutureBuilder<MemoryDemoData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildSelectedBody(snapshot.data ?? MemoryDemoData.empty());
      },
    );
  }

  Widget _buildSelectedBody(MemoryDemoData data) {
    return switch (_selectedTab) {
      AgentMemoryTab.preferences => MemoryPreferencesBody(
          preferences: data.preferences,
          suggestions: data.suggestions,
        ),
      AgentMemoryTab.people => MemoryPeopleBody(people: data.people),
      AgentMemoryTab.projects => MemoryProjectsBody(projects: data.projects),
      AgentMemoryTab.sources => MemorySourcesBody(sources: data.sources),
      AgentMemoryTab.suggestions =>
        MemorySuggestionsBody(suggestions: data.suggestions),
    };
  }
}

MemoryDemoData _memoryDataFromPages(List<MemoryPageRecord> pages) {
  final active = pages
      .where((page) => page.state.toLowerCase() == 'active')
      .toList(growable: false);
  return MemoryDemoData(
    preferences: [
      for (final page in active)
        MemoryPreference(
          title: page.title,
          detail: _memoryPageDetail(page),
        ),
    ],
    people: const <PersonMemory>[],
    projects: const <ProjectMemory>[],
    sources: const <MemorySource>[],
    suggestions: const <MemorySuggestion>[],
  );
}

String _memoryPageDetail(MemoryPageRecord page) {
  final summary = page.summary.trim();
  if (summary.isNotEmpty && summary != page.title.trim()) return summary;
  final body = page.body.trim();
  if (body.isNotEmpty) return body;
  return page.title;
}
