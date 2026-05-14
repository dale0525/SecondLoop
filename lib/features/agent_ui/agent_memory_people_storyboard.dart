part of 'agent_home_storyboard.dart';

final class AgentMemoryPeopleStoryboard extends StatelessWidget {
  const AgentMemoryPeopleStoryboard({super.key});

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
            child: _MemoryPeopleCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _MemoryPeopleCanvas extends StatelessWidget {
  const _MemoryPeopleCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MemoryPeopleWorkspace(),
                SizedBox(width: 36),
                _MemoryPeoplePhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 24),
          _MemoryPeopleNotesStrip(),
        ],
      ),
    );
  }
}

final class _MemoryPeopleWorkspace extends StatelessWidget {
  const _MemoryPeopleWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_people_workspace'),
      width: 1528,
      height: 1110,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _MemorySidebar(),
          _VLine(),
          Expanded(child: _MemoryPeopleDesktopBody()),
        ],
      ),
    );
  }
}

final class _MemoryPeopleDesktopBody extends StatelessWidget {
  const _MemoryPeopleDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(30, 30, 30, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoryHeader(),
          SizedBox(height: 26),
          _MemoryPeopleTabs(),
          SizedBox(height: 36),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 500, child: _PeopleListPanel()),
                SizedBox(width: 22),
                Expanded(child: _PersonDetailPanel()),
              ],
            ),
          ),
          SizedBox(height: 24),
          _PeoplePendingCandidate(),
        ],
      ),
    );
  }
}

final class _MemoryPeopleTabs extends StatelessWidget {
  const _MemoryPeopleTabs();

  static const _tabs = [
    (label: 'Preferences', selected: false),
    (label: 'People', selected: true),
    (label: 'Projects', selected: false),
    (label: 'Sources', selected: false),
    (label: 'Suggestions', selected: false),
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

final class _PeopleListPanel extends StatelessWidget {
  const _PeopleListPanel();

  static const _people = [
    (
      name: 'Alex - Project',
      role: 'Project lead',
      confidence: 'High confidence',
      selected: true,
      color: Color(0xFFB97948),
    ),
    (
      name: 'Li Wei - Client',
      role: 'Key contact',
      confidence: 'High confidence',
      selected: false,
      color: Color(0xFF2C4A75),
    ),
    (
      name: 'Ethan - Finance',
      role: 'Finance partner',
      confidence: 'High confidence',
      selected: false,
      color: Color(0xFF9D6A3D),
    ),
    (
      name: 'Maya - Design',
      role: 'Design lead',
      confidence: 'Medium confidence',
      selected: false,
      color: Color(0xFF6D4C41),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text('People',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
              Text('+',
                  style: TextStyle(
                      color: AgentHomeStoryboard.blue,
                      fontSize: 26,
                      fontWeight: FontWeight.w500)),
              SizedBox(width: 12),
              Text('Add person',
                  style: TextStyle(
                      color: AgentHomeStoryboard.blue,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 28),
          for (final person in _people)
            _PersonListRow(
              name: person.name,
              role: person.role,
              confidence: person.confidence,
              selected: person.selected,
              color: person.color,
            ),
          const Spacer(),
          Text('4 people', style: _mutedBold(14)),
        ],
      ),
    );
  }
}

final class _PersonListRow extends StatelessWidget {
  const _PersonListRow({
    required this.name,
    required this.role,
    required this.confidence,
    required this.selected,
    required this.color,
  });

  final String name;
  final String role;
  final String confidence;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(
        radius: 7,
        color: selected ? const Color(0xFFFBFDFF) : AgentHomeStoryboard.panel,
        border: selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.line,
        borderWidth: selected ? 1.5 : 0,
      ),
      child: Row(
        children: [
          _Avatar(label: name[0], color: color, size: 54),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(role, style: _mutedBold(14)),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(confidence, style: _mutedBold(14)),
              const SizedBox(height: 10),
              const Row(
                children: [
                  _PresenceDot(),
                  SizedBox(width: 8),
                  Text('Saved',
                      style: TextStyle(
                          color: AgentHomeStoryboard.muted,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          const SizedBox(width: 18),
          Text('...', style: _mutedBold(20)),
        ],
      ),
    );
  }
}

final class _PersonDetailPanel extends StatelessWidget {
  const _PersonDetailPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PersonDetailHeader(),
          SizedBox(height: 48),
          Text('Known preferences',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          SizedBox(height: 14),
          _KnownPreferenceList(),
          SizedBox(height: 26),
          _PersonDetailFacts(),
          Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(width: 210, child: _SmallButton('Edit')),
              SizedBox(width: 14),
              SizedBox(width: 230, child: _SmallButton('Forget', danger: true)),
            ],
          ),
        ],
      ),
    );
  }
}

final class _PersonDetailHeader extends StatelessWidget {
  const _PersonDetailHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _Glyph('P', color: Color(0xFF485777)),
        SizedBox(width: 22),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Alex - Project',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Text('Project lead',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        _Chip('Saved', tone: _Tone.green),
      ],
    );
  }
}

final class _KnownPreferenceList extends StatelessWidget {
  const _KnownPreferenceList();

  static const _items = [
    (
      title: 'Prefers afternoon meetings',
      body: 'Brief, focused discussions work best.',
      source: 'From your message  -  May 18, 2025',
      quote: '"Afternoon meetings are more productive."',
      glyph: 'C',
    ),
    (
      title: 'Wants concise agendas',
      body: 'Keep agendas to 3-5 key points.',
      source: 'From your message  -  May 20, 2025',
      quote: '"Short agendas are better."',
      glyph: 'S',
    ),
    (
      title: 'Project: Q2 launch',
      body: 'Leading the Q2 product launch.',
      source: 'From your message  -  May 22, 2025',
      quote: '"I am owning Q2 launch."',
      glyph: 'F',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 8),
      child: Column(
        children: [
          for (final item in _items)
            _KnownPreferenceRow(
              title: item.title,
              body: item.body,
              source: item.source,
              quote: item.quote,
              glyph: item.glyph,
            ),
        ],
      ),
    );
  }
}

final class _KnownPreferenceRow extends StatelessWidget {
  const _KnownPreferenceRow({
    required this.title,
    required this.body,
    required this.source,
    required this.quote,
    required this.glyph,
  });

  final String title;
  final String body;
  final String source;
  final String quote;
  final String glyph;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Container(
          height: compact ? 68 : 118,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
          child: Row(
            children: [
              _Glyph(glyph, color: const Color(0xFF485777)),
              SizedBox(width: compact ? 12 : 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(
                      compact ? source : body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _mutedBold(13),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 20),
                SizedBox(
                  width: 310,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Source', style: _mutedBold(14)),
                      const SizedBox(height: 8),
                      Text(source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _mutedBold(13)),
                      const SizedBox(height: 8),
                      Text(quote,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _mutedBold(13)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

final class _PersonDetailFacts extends StatelessWidget {
  const _PersonDetailFacts();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FactRow('Last mentioned', 'May 22, 2025'),
        SizedBox(height: 16),
        _FactRow('Confidence', 'High confidence'),
      ],
    );
  }
}

final class _FactRow extends StatelessWidget {
  const _FactRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 150, child: Text(label, style: _titleStyle(14))),
        Text(value, style: _mutedBold(14)),
      ],
    );
  }
}

final class _PeoplePendingCandidate extends StatelessWidget {
  const _PeoplePendingCandidate();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pending people memory candidate (1)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          _PeopleCandidateBody(),
        ],
      ),
    );
  }
}

final class _PeopleCandidateBody extends StatelessWidget {
  const _PeopleCandidateBody();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(radius: 8),
      child: const Row(
        children: [
          _Glyph('P', color: Color(0xFF815CFF)),
          SizedBox(width: 22),
          Expanded(
            child: Text(
              'Alex prefers written follow-up\nFrom your message  -  May 23, 2025',
              style: TextStyle(
                  fontSize: 15, height: 1.45, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(width: 260, child: _SmallButton('Accept', success: true)),
          SizedBox(width: 14),
          SizedBox(width: 130, child: _SmallButton('Edit')),
          SizedBox(width: 14),
          SizedBox(width: 150, child: _SmallButton('Ignore')),
        ],
      ),
    );
  }
}

final class _MemoryPeoplePhoneFrame extends StatelessWidget {
  const _MemoryPeoplePhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_people_mobile_mock'),
      width: 430,
      height: 1110,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _MemoryPeopleMobileCanvas(),
      ),
    );
  }
}

final class _MemoryPeopleMobileCanvas extends StatelessWidget {
  const _MemoryPeopleMobileCanvas();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AgentHomeStoryboard.panel,
      child: Stack(
        children: [
          Positioned.fill(child: _MemoryPeopleMobileBody()),
          Positioned(
              left: 0, right: 0, bottom: 80, child: _PersonMobileSheet()),
        ],
      ),
    );
  }
}

final class _MemoryPeopleMobileBody extends StatelessWidget {
  const _MemoryPeopleMobileBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 24, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneStatus(),
          SizedBox(height: 26),
          _MemoryMobileHeader(),
          SizedBox(height: 22),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                    child: _MemoryTab(label: 'Preferences', selected: false)),
                Expanded(child: _MemoryTab(label: 'People', selected: true)),
                Expanded(child: _MemoryTab(label: 'Review', selected: false)),
                Expanded(child: _MemoryTab(label: '2', selected: false)),
              ],
            ),
          ),
          SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: Text('People',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              Text('+',
                  style: TextStyle(
                      color: AgentHomeStoryboard.blue,
                      fontSize: 28,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          SizedBox(height: 14),
          _PeopleMobileList(),
          Spacer(),
          _MemoryBottomNav(),
        ],
      ),
    );
  }
}

final class _PeopleMobileList extends StatelessWidget {
  const _PeopleMobileList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: const Column(
        children: [
          _PeopleMobileRow('Alex - Project', 'Project lead', 'High', true,
              Color(0xFFB97948)),
          _PeopleMobileRow('Li Wei - Client', 'Key contact', 'High', false,
              Color(0xFF2C4A75)),
          _PeopleMobileRow('Ethan - Finance', 'Finance partner', 'High', false,
              Color(0xFF9D6A3D)),
          _PeopleMobileRow('Maya - Design', 'Design lead', 'Medium', false,
              Color(0xFF6D4C41)),
        ],
      ),
    );
  }
}

final class _PeopleMobileRow extends StatelessWidget {
  const _PeopleMobileRow(
    this.name,
    this.role,
    this.confidence,
    this.selected,
    this.color,
  );

  final String name;
  final String role;
  final String confidence;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.line,
          width: selected ? 1.4 : 0.8,
        ),
      ),
      child: Row(
        children: [
          _Avatar(label: name[0], color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(role,
                    overflow: TextOverflow.ellipsis, style: _mutedBold(12)),
              ],
            ),
          ),
          Text(confidence, style: _mutedBold(12)),
          const SizedBox(width: 8),
          const _PresenceDot(),
        ],
      ),
    );
  }
}

final class _PersonMobileSheet extends StatelessWidget {
  const _PersonMobileSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 500,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: const BoxDecoration(
        color: AgentHomeStoryboard.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Avatar(label: 'A', color: Color(0xFFB97948), size: 46),
              SizedBox(width: 16),
              Expanded(
                child: Text('Alex - Project\nProject lead',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              _Chip('Saved', tone: _Tone.green),
            ],
          ),
          SizedBox(height: 18),
          _KnownPreferenceList(),
          SizedBox(height: 14),
          Text('Pending candidate (1)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          _PeopleCandidateCompact(),
        ],
      ),
    );
  }
}

final class _PeopleCandidateCompact extends StatelessWidget {
  const _PeopleCandidateCompact();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(radius: 8),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Alex prefers written follow-up',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text('From your message  -  May 23, 2025',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _SmallButton('Accept', success: true)),
              SizedBox(width: 10),
              Expanded(child: _SmallButton('Edit')),
              SizedBox(width: 10),
              Expanded(child: _SmallButton('Ignore')),
            ],
          ),
        ],
      ),
    );
  }
}

final class _MemoryPeopleNotesStrip extends StatelessWidget {
  const _MemoryPeopleNotesStrip();

  static const _notes = [
    (
      title: 'People memories are person-scoped.',
      body: 'Each person has their own context separate from others.',
    ),
    (
      title: 'Preferences stay attached to a person.',
      body: 'Store what matters about how each person works.',
    ),
    (
      title: 'Sources are readable.',
      body: 'Every fact shows where it came from in plain language.',
    ),
    (
      title: 'Candidates wait for approval.',
      body: 'New people insights are reviewed before being saved.',
    ),
    (
      title: 'No project or global preferences here.',
      body: 'This tab is only about people, not projects or general rules.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_people_interaction_notes'),
      height: 225,
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(48, 36, 48, 30),
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
