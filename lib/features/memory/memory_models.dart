enum AgentMemoryTab {
  preferences('preferences'),
  people('people'),
  projects('projects'),
  sources('sources'),
  suggestions('suggestions');

  const AgentMemoryTab(this.id);

  final String id;
}

final class MemoryPreference {
  const MemoryPreference({
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;
}

final class PersonMemory {
  const PersonMemory({
    required this.name,
    required this.summary,
    required this.detail,
  });

  final String name;
  final String summary;
  final String detail;
}

final class ProjectMemory {
  const ProjectMemory({
    required this.name,
    required this.summary,
    required this.detail,
  });

  final String name;
  final String summary;
  final String detail;
}

final class MemorySource {
  const MemorySource({
    required this.title,
    required this.summary,
    required this.snippet,
  });

  final String title;
  final String summary;
  final String snippet;
}

final class MemorySuggestion {
  const MemorySuggestion({
    required this.group,
    required this.title,
    required this.summary,
  });

  final String group;
  final String title;
  final String summary;
}

final class MemoryDemoData {
  const MemoryDemoData({
    required this.preferences,
    required this.people,
    required this.projects,
    required this.sources,
    required this.suggestions,
  });

  final List<MemoryPreference> preferences;
  final List<PersonMemory> people;
  final List<ProjectMemory> projects;
  final List<MemorySource> sources;
  final List<MemorySuggestion> suggestions;

  static MemoryDemoData demo() {
    return const MemoryDemoData(
      preferences: [
        MemoryPreference(
          title: 'Morning meeting guardrail',
          detail: 'Avoid scheduling meetings before 09:00.',
        ),
        MemoryPreference(
          title: 'Task reply language',
          detail: 'Use Chinese for task planning replies.',
        ),
      ],
      people: [
        PersonMemory(
          name: 'Alex Chen',
          summary: 'Prefers afternoon meetings.',
          detail: 'Alex avoids morning calls and responds fastest after 14:00.',
        ),
        PersonMemory(
          name: 'Mina Park',
          summary: 'Travel follow-up is open.',
          detail: 'Send concise logistics updates before Friday.',
        ),
      ],
      projects: [
        ProjectMemory(
          name: 'Project Atlas',
          summary: 'Cloud agent MVP planning.',
          detail: 'Current focus: approval boundary and media pipeline.',
        ),
        ProjectMemory(
          name: 'Passport renewal',
          summary: 'Document expiry workflow.',
          detail: 'Needs OCR-backed reminder candidate after approval.',
        ),
      ],
      sources: [
        MemorySource(
          title: 'passport-scan.pdf',
          summary: 'OCR source with expiry date evidence.',
          snippet: 'Expiry date appears in the lower-right document field.',
        ),
        MemorySource(
          title: 'weekly-notes.md',
          summary: 'Planning notes from this week.',
          snippet: 'Mentions agent approval and calendar constraints.',
        ),
      ],
      suggestions: [
        MemorySuggestion(
          group: 'Preferences',
          title: 'Task reply language candidate',
          summary: 'Remember that task replies should use Chinese.',
        ),
      ],
    );
  }
}
