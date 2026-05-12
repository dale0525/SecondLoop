import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'memory_models.dart';

final class MemoryPreferencesBody extends StatelessWidget {
  const MemoryPreferencesBody({
    required this.preferences,
    required this.suggestions,
    super.key,
  });

  final List<MemoryPreference> preferences;
  final List<MemorySuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    final t = context.t.memory.agentUi;
    return _MemoryBodyFrame(
      children: [
        for (final preference in preferences)
          _MemoryRow(title: preference.title, detail: preference.detail),
        _MemorySectionTitle(t.candidateMemory),
        _MemoryRow(
          title: suggestions.first.title,
          detail: suggestions.first.summary,
        ),
      ],
    );
  }
}

final class MemoryPeopleBody extends StatelessWidget {
  const MemoryPeopleBody({required this.people, super.key});

  final List<PersonMemory> people;

  @override
  Widget build(BuildContext context) {
    final selected = people.first;
    return _MemorySplitBody(
      listChildren: [
        for (final person in people)
          _MemoryRow(title: person.name, detail: person.summary),
      ],
      detailTitle: context.t.memory.agentUi.selectedPersonDetail,
      detailBody: selected.detail,
    );
  }
}

final class MemoryProjectsBody extends StatelessWidget {
  const MemoryProjectsBody({required this.projects, super.key});

  final List<ProjectMemory> projects;

  @override
  Widget build(BuildContext context) {
    final selected = projects.first;
    return _MemorySplitBody(
      listChildren: [
        for (final project in projects)
          _MemoryRow(title: project.name, detail: project.summary),
      ],
      detailTitle: context.t.memory.agentUi.selectedProjectDetail,
      detailBody: selected.detail,
    );
  }
}

final class MemorySourcesBody extends StatelessWidget {
  const MemorySourcesBody({required this.sources, super.key});

  final List<MemorySource> sources;

  @override
  Widget build(BuildContext context) {
    final selected = sources.first;
    return _MemorySplitBody(
      listChildren: [
        for (final source in sources)
          _MemoryRow(title: source.title, detail: source.summary),
      ],
      detailTitle: context.t.memory.agentUi.sourceSnippets,
      detailBody: selected.snippet,
    );
  }
}

final class MemorySuggestionsBody extends StatelessWidget {
  const MemorySuggestionsBody({required this.suggestions, super.key});

  final List<MemorySuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    final t = context.t.memory.agentUi;
    final suggestion = suggestions.first;
    return _MemoryBodyFrame(
      children: [
        _MemorySectionTitle(t.groupedCandidates),
        _MemoryRow(title: suggestion.title, detail: suggestion.summary),
        Wrap(
          spacing: AgentDesignTokens.gapSm,
          runSpacing: AgentDesignTokens.gapSm,
          children: [
            FilledButton(onPressed: () {}, child: Text(t.actions.accept)),
            OutlinedButton(onPressed: () {}, child: Text(t.actions.edit)),
            TextButton(onPressed: () {}, child: Text(t.actions.ignore)),
          ],
        ),
      ],
    );
  }
}

final class _MemoryBodyFrame extends StatelessWidget {
  const _MemoryBodyFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final child in children) ...[
          child,
          const SizedBox(height: AgentDesignTokens.gapMd),
        ],
      ],
    );
  }
}

final class _MemorySplitBody extends StatelessWidget {
  const _MemorySplitBody({
    required this.listChildren,
    required this.detailTitle,
    required this.detailBody,
  });

  final List<Widget> listChildren;
  final String detailTitle;
  final String detailBody;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useWide = constraints.maxWidth >= 720;
        if (!useWide) {
          return _MemoryBodyFrame(
            children: [
              ...listChildren,
              _MemoryDetail(title: detailTitle, body: detailBody),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _MemoryBodyFrame(children: listChildren)),
            const SizedBox(width: AgentDesignTokens.gapLg),
            Expanded(
                child: _MemoryDetail(title: detailTitle, body: detailBody)),
          ],
        );
      },
    );
  }
}

final class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SlSurface(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AgentDesignTokens.gapXs),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

final class _MemoryDetail extends StatelessWidget {
  const _MemoryDetail({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
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
          const SizedBox(height: AgentDesignTokens.gapSm),
          Text(body),
        ],
      ),
    );
  }
}

final class _MemorySectionTitle extends StatelessWidget {
  const _MemorySectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}
