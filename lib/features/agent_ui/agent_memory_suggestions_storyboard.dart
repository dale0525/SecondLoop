part of 'agent_home_storyboard.dart';

final class AgentMemorySuggestionsStoryboard extends StatelessWidget {
  const AgentMemorySuggestionsStoryboard({super.key});

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
            child: _MemorySuggestionsCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _MemorySuggestionsCanvas extends StatelessWidget {
  const _MemorySuggestionsCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1112,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MemorySuggestionsWorkspace(),
                SizedBox(width: 32),
                _MemorySuggestionsPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 18),
          _MemorySuggestionsNotesStrip(),
        ],
      ),
    );
  }
}

final class _MemorySuggestionsWorkspace extends StatelessWidget {
  const _MemorySuggestionsWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_suggestions_workspace'),
      width: 1532,
      height: 1112,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _MemorySidebar(),
          _VLine(),
          Expanded(child: _MemorySuggestionsDesktopBody()),
        ],
      ),
    );
  }
}

final class _MemorySuggestionsDesktopBody extends StatelessWidget {
  const _MemorySuggestionsDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(38, 34, 38, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoryHeader(),
          SizedBox(height: 26),
          _MemorySuggestionsTabs(),
          SizedBox(height: 42),
          _SuggestionsTitleRow(),
          SizedBox(height: 40),
          _SuggestionGroup(
            time: 'May 20, 2025 at 09:01',
            quote:
                'Note: no meetings before 9 AM. Reply to task updates in Chinese.',
            count: '2 candidates',
            candidates: [
              _CandidateData(
                title: 'No meetings before 9 AM',
                type: 'Preference',
                confidence: 'High confidence',
                color: Color(0xFF08945F),
                icon: 'P',
              ),
              _CandidateData(
                title: 'Reply to tasks in Chinese',
                type: 'Communication preference',
                confidence: 'High confidence',
                color: Color(0xFF08945F),
                icon: 'C',
              ),
            ],
          ),
          SizedBox(height: 32),
          _SuggestionGroup(
            time: 'May 20, 2025 at 09:12',
            quote: 'Alex prefers afternoon meetings whenever possible.',
            count: '1 candidate',
            candidates: [
              _CandidateData(
                title: 'Alex prefers afternoon meetings',
                type: 'Person preference',
                confidence: 'High confidence',
                color: AgentHomeStoryboard.blue,
                icon: 'A',
              ),
            ],
          ),
          Spacer(),
          _SuggestionSafetyNotice(),
        ],
      ),
    );
  }
}

final class _MemorySuggestionsTabs extends StatelessWidget {
  const _MemorySuggestionsTabs();

  static const _tabs = [
    (label: 'Preferences', selected: false),
    (label: 'People', selected: false),
    (label: 'Projects', selected: false),
    (label: 'Sources', selected: false),
    (label: 'Suggestions', selected: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          for (final tab in _tabs)
            SizedBox(
              width: 122,
              child: _MemoryTab(label: tab.label, selected: tab.selected),
            ),
        ],
      ),
    );
  }
}

final class _SuggestionsTitleRow extends StatelessWidget {
  const _SuggestionsTitleRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Suggestions',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              SizedBox(height: 12),
              Text(
                'Review memory candidates before they become permanent.',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Container(
          width: 192,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: _box(radius: 7),
          child: Row(
            children: [
              const Expanded(
                child: Text('All types',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Text('v', style: _mutedBold(16)),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Container(
          width: 226,
          height: 54,
          alignment: Alignment.center,
          decoration: _box(radius: 7, color: const Color(0xFFFAFBFD)),
          child: const Text(
            'Review selected (0)',
            style: TextStyle(
                color: Color(0xFFA1ABC0),
                fontSize: 16,
                fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

final class _SuggestionGroup extends StatelessWidget {
  const _SuggestionGroup({
    required this.time,
    required this.quote,
    required this.count,
    required this.candidates,
  });

  final String time;
  final String quote;
  final String count;
  final List<_CandidateData> candidates;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: Column(
        children: [
          _SuggestionGroupHeader(time: time, quote: quote, count: count),
          for (final candidate in candidates)
            _SuggestionCandidateRow(candidate),
        ],
      ),
    );
  }
}

final class _SuggestionGroupHeader extends StatelessWidget {
  const _SuggestionGroupHeader({
    required this.time,
    required this.quote,
    required this.count,
  });

  final String time;
  final String quote;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: _Glyph('M', color: Color(0xFF485777)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('From your message  -  $time', style: _mutedBold(14)),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(quote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _mutedBold(14)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(count, style: _mutedBold(14)),
          ),
          const SizedBox(width: 24),
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text('^',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

final class _SuggestionCandidateRow extends StatelessWidget {
  const _SuggestionCandidateRow(this.candidate);

  final _CandidateData candidate;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          const _SelectionBox(),
          const SizedBox(width: 26),
          _SourceIcon(icon: candidate.icon, color: candidate.color),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(candidate.type, style: _mutedBold(15)),
              ],
            ),
          ),
          SizedBox(
            width: 210,
            child: Text(candidate.confidence, style: _mutedBold(15)),
          ),
          const SizedBox(width: 20),
          const SizedBox(
              width: 144, child: _SmallButton('Accept', success: true)),
          const SizedBox(width: 18),
          const SizedBox(width: 144, child: _SmallButton('Edit')),
          const SizedBox(width: 18),
          const SizedBox(width: 144, child: _SmallButton('Ignore')),
        ],
      ),
    );
  }
}

final class _SelectionBox extends StatelessWidget {
  const _SelectionBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: _box(radius: 5, color: const Color(0xFFFBFCFE)),
    );
  }
}

final class _SuggestionSafetyNotice extends StatelessWidget {
  const _SuggestionSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: _box(radius: 9),
      child: const Row(
        children: [
          _Glyph('i', color: AgentHomeStoryboard.blue),
          SizedBox(width: 22),
          Expanded(
            child: Text(
              'Nothing is saved until you accept.\nAccepted items will move to the right tab and remain editable.',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 16,
                  height: 1.55,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _MemorySuggestionsPhoneFrame extends StatelessWidget {
  const _MemorySuggestionsPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_suggestions_mobile_mock'),
      width: 470,
      height: 1112,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _MemorySuggestionsMobileCanvas(),
      ),
    );
  }
}

final class _MemorySuggestionsMobileCanvas extends StatelessWidget {
  const _MemorySuggestionsMobileCanvas();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AgentHomeStoryboard.panel,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PhoneStatus(),
            SizedBox(height: 18),
            _MemoryMobileHeader(),
            SizedBox(height: 14),
            _SuggestionsMobileTabs(),
            SizedBox(height: 14),
            _SuggestionsMobileTitle(),
            SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SuggestionsMobileFilter(),
                    SizedBox(height: 14),
                    _SuggestionsMobileGroup(
                      time: '09:01',
                      quote:
                          'Note: no meetings before 9 AM. Reply to task updates in Chinese.',
                      count: '2 candidates',
                      candidates: [
                        _CandidateData(
                          title: 'No meetings before 9 AM',
                          type: 'Preference',
                          confidence: 'High confidence',
                          color: Color(0xFF08945F),
                          icon: 'P',
                        ),
                        _CandidateData(
                          title: 'Reply to tasks in Chinese',
                          type: 'Communication preference',
                          confidence: 'High confidence',
                          color: Color(0xFF08945F),
                          icon: 'C',
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _SuggestionsMobileGroup(
                      time: '09:12',
                      quote:
                          'Alex prefers afternoon meetings whenever possible.',
                      count: '1 candidate',
                      candidates: [
                        _CandidateData(
                          title: 'Alex prefers afternoon meetings',
                          type: 'Person preference',
                          confidence: 'High confidence',
                          color: AgentHomeStoryboard.blue,
                          icon: 'A',
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _SuggestionMobileSafetyNotice(),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            _MemoryBottomNav(),
          ],
        ),
      ),
    );
  }
}

final class _SuggestionsMobileTabs extends StatelessWidget {
  const _SuggestionsMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _MemoryTab(label: 'Preferences', selected: false)),
          Expanded(child: _MemoryTab(label: 'People', selected: false)),
          Expanded(child: _MemoryTab(label: 'Suggestions', selected: true)),
          SizedBox(width: 24, child: _Badge('2')),
        ],
      ),
    );
  }
}

final class _SuggestionsMobileTitle extends StatelessWidget {
  const _SuggestionsMobileTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Suggestions',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        SizedBox(height: 8),
        Text(
          'Review memory candidates before they become permanent.',
          style: TextStyle(
              color: AgentHomeStoryboard.muted,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

final class _SuggestionsMobileFilter extends StatelessWidget {
  const _SuggestionsMobileFilter();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 38,
        width: 122,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _box(radius: 7),
        child: Row(
          children: [
            const Expanded(
              child: Text('All types',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            Text('v', style: _mutedBold(13)),
          ],
        ),
      ),
    );
  }
}

final class _SuggestionsMobileGroup extends StatelessWidget {
  const _SuggestionsMobileGroup({
    required this.time,
    required this.quote,
    required this.count,
    required this.candidates,
  });

  final String time;
  final String quote;
  final String count;
  final List<_CandidateData> candidates;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From your message  -  $time', style: _mutedBold(13)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    quote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedBold(12),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(count, style: _mutedBold(12))),
                    Text('v', style: _mutedBold(14)),
                  ],
                ),
              ],
            ),
          ),
          for (final candidate in candidates)
            _SuggestionsMobileCandidate(candidate),
        ],
      ),
    );
  }
}

final class _SuggestionsMobileCandidate extends StatelessWidget {
  const _SuggestionsMobileCandidate(this.candidate);

  final _CandidateData candidate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const _SelectionBox(),
              const SizedBox(width: 12),
              _SourceIcon(
                icon: candidate.icon,
                color: candidate.color,
                small: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(candidate.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text(candidate.type, style: _mutedBold(12)),
                    const SizedBox(height: 5),
                    Text(candidate.confidence, style: _mutedBold(12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(child: _SuggestionMiniButton('Accept', success: true)),
              SizedBox(width: 10),
              Expanded(child: _SuggestionMiniButton('Edit')),
              SizedBox(width: 10),
              Expanded(child: _SuggestionMiniButton('Ignore')),
            ],
          ),
        ],
      ),
    );
  }
}

final class _SuggestionMiniButton extends StatelessWidget {
  const _SuggestionMiniButton(this.label, {this.success = false});

  final String label;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      decoration: _box(radius: 6),
      child: Text(
        label,
        style: TextStyle(
          color: success ? const Color(0xFF08945F) : AgentHomeStoryboard.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

final class _SuggestionMobileSafetyNotice extends StatelessWidget {
  const _SuggestionMobileSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(radius: 8),
      child: const Row(
        children: [
          _Glyph('i', color: AgentHomeStoryboard.blue),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nothing is saved until you accept.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _CandidateData {
  const _CandidateData({
    required this.title,
    required this.type,
    required this.confidence,
    required this.color,
    required this.icon,
  });

  final String title;
  final String type;
  final String confidence;
  final Color color;
  final String icon;
}

final class _MemorySuggestionsNotesStrip extends StatelessWidget {
  const _MemorySuggestionsNotesStrip();

  static const _notes = [
    (
      title: 'Suggestions are not saved yet.',
      body: 'They are candidates and need your approval.',
    ),
    (
      title: 'Multiple facts stay separate.',
      body: 'Each candidate represents one specific fact.',
    ),
    (
      title: 'Every candidate has its own action.',
      body: 'Accept, edit, or ignore one item at a time.',
    ),
    (
      title: 'Source text remains readable.',
      body: 'You can see exactly where each candidate came from.',
    ),
    (
      title: 'Approved items move to their tabs.',
      body: 'They become part of your memory and stay editable.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_suggestions_interaction_notes'),
      height: 218,
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
