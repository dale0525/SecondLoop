part of 'agent_home_storyboard.dart';

final class AgentFilesMediaStoryboard extends StatelessWidget {
  const AgentFilesMediaStoryboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(
        color: AgentHomeStoryboard.ink,
        fontFamily: 'Inter',
        fontSize: 14,
        decoration: TextDecoration.none,
      ),
      child: const ColoredBox(
        color: AgentHomeStoryboard.soft,
        child: FittedBox(
          alignment: Alignment.topLeft,
          fit: BoxFit.contain,
          child: SizedBox(
            width: AgentHomeStoryboard.canvasWidth,
            height: AgentHomeStoryboard.canvasHeight,
            child: _FilesMediaCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _FilesMediaCanvas extends StatelessWidget {
  const _FilesMediaCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1115,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FilesMediaWorkspace(),
                SizedBox(width: 56),
                _FilesMediaPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 20),
          _FilesMediaNotesStrip(),
        ],
      ),
    );
  }
}

final class _FilesMediaWorkspace extends StatelessWidget {
  const _FilesMediaWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_files_media_workspace'),
      width: 1552,
      height: 1115,
      decoration: _box(radius: 16),
      child: const Row(
        children: [
          _Sidebar(),
          _VLine(),
          Expanded(child: _FilesMediaConversation()),
          _VLine(),
          SizedBox(width: 395, child: _ContextRail()),
        ],
      ),
    );
  }
}

final class _FilesMediaConversation extends StatelessWidget {
  const _FilesMediaConversation();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 28, 28, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilesMediaHeader(),
          SizedBox(height: 26),
          Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FilesMediaUserMessage(),
                  SizedBox(height: 24),
                  _FilesMediaAssistantMessage(),
                ],
              ),
            ),
          ),
          SizedBox(height: 14),
          _Composer(fullText: true),
        ],
      ),
    );
  }
}

final class _FilesMediaHeader extends StatelessWidget {
  const _FilesMediaHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('Conversation',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        SizedBox(width: 22),
        _PresenceDot(),
        SizedBox(width: 8),
        Text('Ready',
            style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
      ],
    );
  }
}

final class _FilesMediaUserMessage extends StatelessWidget {
  const _FilesMediaUserMessage();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 44),
        SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'You', time: '09:20'),
              SizedBox(height: 8),
              Text(
                'Please summarize today\'s meeting audio, invoice, and passport scan, then extract details and suggested actions.',
                style: TextStyle(
                    fontSize: 16, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _AttachmentCard(
                      glyph: 'A',
                      color: Color(0xFF8D57FF),
                      title: 'meeting_audio.mp3',
                      body: '48.2 MB  -  45:12',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _AttachmentCard(
                      glyph: 'PDF',
                      color: Color(0xFFE82424),
                      title: 'invoice.pdf',
                      body: '1.2 MB  -  3 pages',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _AttachmentCard(
                      glyph: 'IMG',
                      color: Color(0xFF0B9B63),
                      title: 'passport_scan.jpg',
                      body: '820 KB  -  1 page',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _FilesMediaAssistantMessage extends StatelessWidget {
  const _FilesMediaAssistantMessage();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LoopAvatar(size: 44),
        SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'SecondLoop', time: '09:22'),
              SizedBox(height: 8),
              Text(
                "I processed your files. Here's a summary, key points, extracted details, and suggested actions.",
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 20),
              _FilesMediaSummaryCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _MessageMeta extends StatelessWidget {
  const _MessageMeta({required this.name, required this.time});

  final String name;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(width: 16),
        Text(time, style: _mutedBold(13)),
      ],
    );
  }
}

final class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.glyph,
    required this.color,
    required this.title,
    required this.body,
  });

  final String glyph;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _box(radius: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: _box(
              radius: 8,
              color: color.withOpacity(0.12),
              border: color.withOpacity(0.12),
            ),
            child: Text(glyph,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$title\n$body',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, height: 1.35, fontWeight: FontWeight.w800),
            ),
          ),
          const Text('x',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _FilesMediaSummaryCard extends StatelessWidget {
  const _FilesMediaSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilesMediaTabs(),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MeetingSummaryBox(),
                SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _DecisionPanel()),
                    SizedBox(width: 12),
                    Expanded(child: _ActionItemsPanel()),
                    SizedBox(width: 12),
                    Expanded(child: _TopicPanel()),
                  ],
                ),
                SizedBox(height: 16),
                _ExtractedFieldsTable(),
                SizedBox(height: 16),
                _SuggestedReviewItems(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _FilesMediaTabs extends StatelessWidget {
  const _FilesMediaTabs();

  static const _tabs = [
    (label: 'Summary', selected: true),
    (label: 'Transcript', selected: false),
    (label: 'Extracted fields', selected: false),
    (label: 'Suggested actions', selected: false),
    (label: 'Sources', selected: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          for (final tab in _tabs)
            SizedBox(
              width: tab.label == 'Suggested actions' ? 150 : 124,
              child: _MemoryTab(label: tab.label, selected: tab.selected),
            ),
        ],
      ),
    );
  }
}

final class _MeetingSummaryBox extends StatelessWidget {
  const _MeetingSummaryBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(radius: 8, color: const Color(0xFFFBFCFE)),
      child: const Text(
        'Meeting summary  (meeting_audio.mp3)\nThe meeting covered Q2 progress, launch timing, and market strategy. The team agreed to stay on schedule, focus on growth channels, and set the next review.',
        style:
            TextStyle(fontSize: 14, height: 1.55, fontWeight: FontWeight.w800),
      ),
    );
  }
}

final class _DecisionPanel extends StatelessWidget {
  const _DecisionPanel();

  @override
  Widget build(BuildContext context) {
    return const _MiniPanel(
      title: 'Decisions',
      rows: [
        'Q2 plan stays on track',
        'Campaign budget increases 15%',
        'Next review: Monday 10:00'
      ],
      glyph: '+',
      color: Color(0xFF159364),
    );
  }
}

final class _ActionItemsPanel extends StatelessWidget {
  const _ActionItemsPanel();

  @override
  Widget build(BuildContext context) {
    return const _MiniPanel(
      title: 'Action items',
      rows: [
        'Kevin: prepare launch plan by 5/22',
        'Evelyn: update growth dashboard by 5/21',
        'Ada: send review invite today'
      ],
      glyph: '-',
      color: AgentHomeStoryboard.blue,
    );
  }
}

final class _TopicPanel extends StatelessWidget {
  const _TopicPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 136,
      padding: const EdgeInsets.all(12),
      decoration: _box(radius: 8),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Key topics covered',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Bubble('Q2'),
              _Bubble('Growth'),
              _Bubble('Launch'),
              _Bubble('Market'),
              _Bubble('Budget'),
            ],
          ),
        ],
      ),
    );
  }
}

final class _MiniPanel extends StatelessWidget {
  const _MiniPanel({
    required this.title,
    required this.rows,
    required this.glyph,
    required this.color,
  });

  final String title;
  final List<String> rows;
  final String glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 136,
      padding: const EdgeInsets.all(12),
      decoration: _box(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(glyph,
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

final class _ExtractedFieldsTable extends StatelessWidget {
  const _ExtractedFieldsTable();

  static const _rows = [
    ['Field', 'Value', 'Source', 'Page / Area', 'Confidence'],
    ['Passport expiry', '2026-09-30', 'passport_scan.jpg', 'Page 1', 'High'],
    ['Invoice due date', '2025-05-28', 'invoice.pdf', 'Page 1', 'Medium'],
    ['Contract renewal', '2025-07-15', 'invoice.pdf', 'Page 2', 'High'],
    ['Invoice amount', 'CNY 1,280.00', 'invoice.pdf', 'Page 1', 'High'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Extracted fields',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Container(
          decoration: _box(radius: 8),
          child: Column(
            children: [
              for (var i = 0; i < _rows.length; i++)
                _ExtractedFieldRow(cells: _rows[i], header: i == 0),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ExtractedFieldRow extends StatelessWidget {
  const _ExtractedFieldRow({required this.cells, required this.header});

  final List<String> cells;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Text(
                cells[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: header
                      ? AgentHomeStoryboard.muted
                      : i == 4 && cells[i] == 'Medium'
                          ? const Color(0xFFFF8A00)
                          : i == 4
                              ? const Color(0xFF159364)
                              : AgentHomeStoryboard.ink,
                  fontSize: header ? 11 : 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _SuggestedReviewItems extends StatelessWidget {
  const _SuggestedReviewItems();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Suggested review items',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ReviewSuggestionCard(
                title: 'Create reminder: invoice due',
                body: 'Remind me on May 26 to handle this invoice.',
                glyph: 'N',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _ReviewSuggestionCard(
                title: 'Remember passport expiry',
                body: 'Save passport expiry date 2026-09-30.',
                glyph: 'M',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _ReviewSuggestionCard(
                title: 'Draft follow-up email',
                body: 'Draft a team follow-up from the meeting notes.',
                glyph: 'E',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _ReviewSuggestionCard extends StatelessWidget {
  const _ReviewSuggestionCard({
    required this.title,
    required this.body,
    required this.glyph,
  });

  final String title;
  final String body;
  final String glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.all(12),
      decoration: _box(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Glyph(glyph, color: const Color(0xFFFF8A00)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mutedBold(12),
            ),
          ),
          const Row(
            children: [
              Expanded(child: _TinyActionButton('Review', primary: true)),
              SizedBox(width: 8),
              Expanded(child: _TinyActionButton('Edit')),
              SizedBox(width: 8),
              Expanded(child: _TinyActionButton('Ignore')),
            ],
          ),
        ],
      ),
    );
  }
}

final class _TinyActionButton extends StatelessWidget {
  const _TinyActionButton(this.label, {this.primary = false});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      alignment: Alignment.center,
      decoration: _box(
        radius: 6,
        color: primary ? AgentHomeStoryboard.blue : AgentHomeStoryboard.panel,
        border: primary ? AgentHomeStoryboard.blue : AgentHomeStoryboard.line,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: primary ? Colors.white : AgentHomeStoryboard.muted,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _FilesMediaNotesStrip extends StatelessWidget {
  const _FilesMediaNotesStrip();

  static const _notes = [
    (
      title: 'Files enter through the conversation composer.',
      body: 'You attach audio, images, PDFs, or documents in the chat.',
    ),
    (
      title: 'Media and OCR results appear in the conversation.',
      body:
          'Summaries, transcripts, and extracted fields are shown in plain language.',
    ),
    (
      title: 'Sources and confidence use plain language.',
      body:
          'Each extracted item shows where it came from and a confidence level.',
    ),
    (
      title: 'Suggested reminders and memories still need review.',
      body: 'Review, edit, or ignore before anything is saved or scheduled.',
    ),
    (
      title: 'The right context rail remains stable.',
      body:
          'Your context is always visible and consistent across every screen.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_files_media_interaction_notes'),
      height: 220,
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(48, 34, 48, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _notes.length; i++) ...[
            Expanded(
              child: _ReviewNote(
                number: '${i + 1}',
                title: _notes[i].title,
                body: _notes[i].body,
              ),
            ),
            if (i < _notes.length - 1) const _NoteDivider(),
          ],
        ],
      ),
    );
  }
}
