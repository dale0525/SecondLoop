final class ConversationContextSnapshot {
  const ConversationContextSnapshot({
    required this.todayAtAGlance,
    required this.longTermMemory,
    required this.people,
    required this.recentFiles,
    required this.pendingReview,
    required this.privacyNote,
  });

  final List<ConversationContextItem> todayAtAGlance;
  final List<ConversationContextItem> longTermMemory;
  final List<ConversationContextItem> people;
  final List<ConversationContextItem> recentFiles;
  final List<ConversationContextItem> pendingReview;
  final String privacyNote;

  static ConversationContextSnapshot demo() {
    return const ConversationContextSnapshot(
      todayAtAGlance: [
        ConversationContextItem(
          title: '2 priorities due today',
          subtitle: 'Passport renewal and weekly report are active.',
        ),
        ConversationContextItem(
          title: 'One open approval',
          subtitle: 'A task change is waiting before it writes to your vault.',
        ),
      ],
      longTermMemory: [
        ConversationContextItem(
          title: 'No meetings before 09:00',
          subtitle: 'Preference from long-term memory.',
        ),
        ConversationContextItem(
          title: 'Use Chinese for task replies',
          subtitle: 'Applies to planning and task updates.',
        ),
      ],
      people: [
        ConversationContextItem(
          title: 'Alex',
          subtitle: 'Prefers afternoon meetings.',
        ),
        ConversationContextItem(
          title: 'Mina',
          subtitle: 'Travel follow-up is still open.',
        ),
      ],
      recentFiles: [
        ConversationContextItem(
          title: 'passport-scan.pdf',
          subtitle: 'OCR candidate: expiry date found.',
        ),
        ConversationContextItem(
          title: 'weekly-notes.md',
          subtitle: 'Last updated today.',
        ),
      ],
      pendingReview: [
        ConversationContextItem(
          title: 'Task change',
          subtitle: 'Due time update requires approval.',
        ),
      ],
      privacyNote:
          'Only synced vault, working set, and approved context are shown here.',
    );
  }
}

final class ConversationContextItem {
  const ConversationContextItem({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}
