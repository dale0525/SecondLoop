part of 'agent_home_storyboard.dart';

final class AgentResearchStoryboard extends StatelessWidget {
  const AgentResearchStoryboard({super.key});

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
            child: _ResearchCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _ResearchCanvas extends StatelessWidget {
  const _ResearchCanvas();

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
                _ResearchWorkspace(),
                SizedBox(width: 56),
                _ResearchPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 20),
          _ResearchNotesStrip(),
        ],
      ),
    );
  }
}

final class _ResearchWorkspace extends StatelessWidget {
  const _ResearchWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_research_workspace'),
      width: 1552,
      height: 1115,
      decoration: _box(radius: 16),
      child: const Row(
        children: [
          _Sidebar(),
          _VLine(),
          Expanded(child: _ResearchConversation()),
          _VLine(),
          SizedBox(width: 395, child: _ContextRail()),
        ],
      ),
    );
  }
}

final class _ResearchConversation extends StatelessWidget {
  const _ResearchConversation();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 28, 28, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResearchHeader(),
          SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ResearchRequestMessage(),
                  SizedBox(height: 18),
                  _ResearchConfirmationReply(),
                  SizedBox(height: 18),
                  _ResearchStartMessage(),
                  SizedBox(height: 18),
                  _ResearchResultReply(),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          _Composer(fullText: true),
        ],
      ),
    );
  }
}

final class _ResearchHeader extends StatelessWidget {
  const _ResearchHeader();

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

final class _ResearchRequestMessage extends StatelessWidget {
  const _ResearchRequestMessage();

  @override
  Widget build(BuildContext context) {
    return const _ResearchTextMessage(
      avatar: _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 44),
      name: 'You',
      time: '09:01',
      text:
          'Research Hermes Agent and OpenClaw capability differences, then save a note.',
      bubble: true,
    );
  }
}

final class _ResearchConfirmationReply extends StatelessWidget {
  const _ResearchConfirmationReply();

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
              _MessageMeta(name: 'SecondLoop', time: '09:01'),
              SizedBox(height: 8),
              Text(
                'I will do bounded search and reading, summarize the result, and save a note. This is high-cost research, so I need confirmation before starting.',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 16),
              _ResearchBudgetCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ResearchStartMessage extends StatelessWidget {
  const _ResearchStartMessage();

  @override
  Widget build(BuildContext context) {
    return const _ResearchTextMessage(
      avatar: _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 44),
      name: 'You',
      time: '09:02',
      text: 'Start.',
      bubble: true,
    );
  }
}

final class _ResearchResultReply extends StatelessWidget {
  const _ResearchResultReply();

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
              _MessageMeta(name: 'SecondLoop', time: '09:06'),
              SizedBox(height: 8),
              Text(
                'Research is complete. Here is the summary.',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 16),
              _ResearchResultCard(),
              SizedBox(height: 14),
              _ResearchDraftSavedCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ResearchTextMessage extends StatelessWidget {
  const _ResearchTextMessage({
    required this.avatar,
    required this.name,
    required this.time,
    required this.text,
    this.bubble = false,
  });

  final Widget avatar;
  final String name;
  final String time;
  final String text;
  final bool bubble;

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      text,
      style: TextStyle(
        color: bubble ? AgentHomeStoryboard.ink : AgentHomeStoryboard.muted,
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w800,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: name, time: time),
              const SizedBox(height: 8),
              if (bubble)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: _box(
                    radius: 8,
                    color: const Color(0xFFF0F3F8),
                    border: const Color(0xFFF0F3F8),
                  ),
                  child: textWidget,
                )
              else
                textWidget,
            ],
          ),
        ),
      ],
    );
  }
}

final class _ResearchBudgetCard extends StatelessWidget {
  const _ResearchBudgetCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(
        radius: 10,
        color: const Color(0xFFFFFCF7),
        border: const Color(0xFFFFD59B),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Glyph('!', color: Color(0xFFFF8A00)),
              SizedBox(width: 12),
              Expanded(
                child: Text('High-cost research',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          SizedBox(height: 14),
          Divider(height: 1, color: AgentHomeStoryboard.line),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _ResearchMetricBox('Q', 'Search up to 20 pages')),
              _VLine(height: 48),
              Expanded(child: _ResearchMetricBox('T', 'Estimated tokens 120K')),
              _VLine(height: 48),
              Expanded(
                  child: _ResearchMetricBox(r'$', r'Estimated cost $1.24')),
              _VLine(height: 48),
              Expanded(
                child: Text(
                  'Results include a brief, key points, sources, and a draft note.',
                  style: TextStyle(
                      fontSize: 12, height: 1.35, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _TinyActionButton('Start research', primary: true)),
              SizedBox(width: 12),
              Expanded(child: _TinyActionButton('Reduce scope')),
              SizedBox(width: 12),
              Expanded(child: _TinyActionButton('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ResearchMetricBox extends StatelessWidget {
  const _ResearchMetricBox(this.glyph, this.text);

  final String glyph;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Glyph(glyph, color: const Color(0xFF485777)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, height: 1.35, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

final class _ResearchResultCard extends StatelessWidget {
  const _ResearchResultCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResearchTabs(),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ResearchBriefBox(),
                SizedBox(height: 14),
                _ResearchBullet(
                    'Hermes Agent is stronger for long-running task orchestration.'),
                _ResearchBullet(
                    'OpenClaw is closer to code search and editor workflow automation.'),
                _ResearchBullet(
                    'Choose based on collaboration style and developer-tool efficiency.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ResearchTabs extends StatelessWidget {
  const _ResearchTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 54,
      child: Row(
        children: [
          Expanded(child: _SettingsMobileTab('Brief', selected: true)),
          Expanded(child: _SettingsMobileTab('Key points')),
          Expanded(child: _SettingsMobileTab('Sources (5)')),
          Expanded(child: _SettingsMobileTab('Draft note')),
        ],
      ),
    );
  }
}

final class _ResearchBriefBox extends StatelessWidget {
  const _ResearchBriefBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(
        radius: 8,
        color: const Color(0xFFF4F8FF),
        border: const Color(0xFFDCE6FF),
      ),
      child: const Text(
        'Hermes Agent appears more suited to multi-agent collaboration and task execution frameworks. OpenClaw is closer to code-understanding and editor-side workflows. Both are useful, but they optimize for different operating modes.',
        style:
            TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
      ),
    );
  }
}

final class _ResearchBullet extends StatelessWidget {
  const _ResearchBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•',
              style: TextStyle(
                  color: AgentHomeStoryboard.blue,
                  fontSize: 20,
                  height: 0.9,
                  fontWeight: FontWeight.w900)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ResearchDraftSavedCard extends StatelessWidget {
  const _ResearchDraftSavedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      decoration: _box(
        radius: 10,
        color: const Color(0xFFF0FBF7),
        border: const Color(0xFFCFEFE2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: const Row(
        children: [
          _Glyph('S', color: Color(0xFF159364)),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saved as draft note',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text('Hermes Agent vs OpenClaw capability research',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          SizedBox(width: 120, child: _TinyActionButton('Open draft')),
        ],
      ),
    );
  }
}

final class _ResearchNotesStrip extends StatelessWidget {
  const _ResearchNotesStrip();

  static const _notes = [
    (
      title: 'Research starts in conversation.',
      body:
          'Describe what you need in plain language; the assistant continues from there.',
    ),
    (
      title: 'High-cost work asks first.',
      body: 'More reading or tokens require scope and budget confirmation.',
    ),
    (
      title: 'Result structure is generic.',
      body:
          'Every research result returns Brief, Key points, Sources, and Draft note.',
    ),
    (
      title: 'Sources stay visible.',
      body:
          'Citations include title, domain, and fetched time for verification.',
    ),
    (
      title: 'Drafts save to your vault.',
      body: 'Results are saved as draft notes you can open, edit, and reuse.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_research_interaction_notes'),
      height: 220,
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(64, 24, 46, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _notes.length; i++) ...[
            Expanded(
              child: _NoteItem(
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
