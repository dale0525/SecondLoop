enum ReviewItemKind {
  taskChange,
  memoryWrite,
  emailDraft,
}

enum ReviewRisk {
  high,
  medium,
  low,
}

enum ReviewStatus {
  needsApproval,
  draft,
}

final class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.kind,
    required this.risk,
    required this.status,
    required this.title,
    required this.summary,
    required this.source,
    required this.timeLabel,
    required this.diffRows,
  });

  final String id;
  final ReviewItemKind kind;
  final ReviewRisk risk;
  final ReviewStatus status;
  final String title;
  final String summary;
  final String source;
  final String timeLabel;
  final List<ReviewDiffRow> diffRows;
}

final class ReviewDiffRow {
  const ReviewDiffRow({
    required this.id,
    required this.field,
    required this.before,
    required this.after,
  });

  final String id;
  final String field;
  final String before;
  final String after;
}

List<ReviewItem> demoReviewItems() {
  return const [
    ReviewItem(
      id: 'task_due',
      kind: ReviewItemKind.taskChange,
      risk: ReviewRisk.high,
      status: ReviewStatus.needsApproval,
      title: 'Move passport renewal',
      summary: 'Due time changes before the task is written.',
      source:
          "Move the passport renewal task to today at 20:00, but don't mark it done.",
      timeLabel: '2 min ago',
      diffRows: [
        ReviewDiffRow(
          id: 'due_time',
          field: 'Due time',
          before: 'Tomorrow 09:00',
          after: 'Today 20:00',
        ),
        ReviewDiffRow(
          id: 'status',
          field: 'Status',
          before: 'Not started',
          after: 'Not started',
        ),
        ReviewDiffRow(
          id: 'notes',
          field: 'Notes',
          before: 'No note',
          after: 'Keep current status unchanged.',
        ),
      ],
    ),
    ReviewItem(
      id: 'memory_language',
      kind: ReviewItemKind.memoryWrite,
      risk: ReviewRisk.medium,
      status: ReviewStatus.needsApproval,
      title: 'Remember reply language',
      summary: 'Long-term memory candidate.',
      source: 'Remember: task replies should use Chinese.',
      timeLabel: '8 min ago',
      diffRows: [
        ReviewDiffRow(
          id: 'scope',
          field: 'Scope',
          before: 'No memory',
          after: 'Task replies',
        ),
        ReviewDiffRow(
          id: 'value',
          field: 'Value',
          before: 'Unset',
          after: 'Chinese',
        ),
        ReviewDiffRow(
          id: 'source',
          field: 'Source',
          before: 'None',
          after: 'Conversation',
        ),
      ],
    ),
    ReviewItem(
      id: 'email_followup',
      kind: ReviewItemKind.emailDraft,
      risk: ReviewRisk.low,
      status: ReviewStatus.draft,
      title: 'Team follow-up draft',
      summary: 'Draft only, not sent.',
      source: 'Create a follow-up email draft for the meeting.',
      timeLabel: '15 min ago',
      diffRows: [
        ReviewDiffRow(
          id: 'draft',
          field: 'Draft',
          before: 'None',
          after: 'Created in vault drafts',
        ),
        ReviewDiffRow(
          id: 'send',
          field: 'Send',
          before: 'Not sent',
          after: 'Needs approval',
        ),
        ReviewDiffRow(
          id: 'recipients',
          field: 'Recipients',
          before: 'Unset',
          after: 'Team',
        ),
      ],
    ),
  ];
}
