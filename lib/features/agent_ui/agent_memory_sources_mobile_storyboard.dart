part of 'agent_home_storyboard.dart';

final class _MemorySourcesPhoneFrame extends StatelessWidget {
  const _MemorySourcesPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_sources_mobile_mock'),
      width: 470,
      height: 1106,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _MemorySourcesMobileCanvas(),
      ),
    );
  }
}

final class _MemorySourcesMobileCanvas extends StatelessWidget {
  const _MemorySourcesMobileCanvas();

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
            SizedBox(height: 26),
            _MemoryMobileHeader(),
            SizedBox(height: 20),
            _SourcesMobileTabs(),
            SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Sources',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900)),
                    SizedBox(height: 14),
                    _SourceFilterRow(),
                    SizedBox(height: 14),
                    _SourcesMobileList(),
                    SizedBox(height: 16),
                    _SourcesMobileDetail(),
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

final class _SourcesMobileTabs extends StatelessWidget {
  const _SourcesMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _MemoryTab(label: 'Preferences', selected: false)),
          Expanded(child: _MemoryTab(label: 'People', selected: false)),
          Expanded(child: _MemoryTab(label: 'Sources', selected: true)),
          Expanded(child: _MemoryTab(label: 'More', selected: false)),
        ],
      ),
    );
  }
}

final class _SourcesMobileList extends StatelessWidget {
  const _SourcesMobileList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: const Column(
        children: [
          _SourcesMobileRow('Conversation - May 20', 'You and SecondLoop', '5',
              AgentHomeStoryboard.blue, 'C',
              selected: true),
          _SourcesMobileRow('Meeting notes - Q2 review', 'Q2 review sync', '4',
              Color(0xFF08945F), 'N'),
          _SourcesMobileRow('Client_Requirements.docx', 'Document', '6',
              AgentHomeStoryboard.blue, 'W'),
          _SourcesMobileRow(
              'Passport scan', 'Image', '3', Color(0xFF08945F), 'I'),
        ],
      ),
    );
  }
}

final class _SourcesMobileRow extends StatelessWidget {
  const _SourcesMobileRow(
    this.title,
    this.body,
    this.count,
    this.color,
    this.icon, {
    this.selected = false,
  });

  final String title;
  final String body;
  final String count;
  final Color color;
  final String icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? const Color(0xFF7FA9FF) : AgentHomeStoryboard.line,
          width: selected ? 1.4 : 0.8,
        ),
      ),
      child: Row(
        children: [
          _SourceIcon(icon: icon, color: color, small: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedBold(11)),
              ],
            ),
          ),
          Text(count, style: _mutedBold(13)),
          const SizedBox(width: 12),
          const Text('>',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _SourcesMobileDetail extends StatelessWidget {
  const _SourcesMobileDetail();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Conversation - May 20\nMay 20, 2025  -  5 memories',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              Text('^',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          SizedBox(height: 16),
          Text('Extracted memory references',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          SizedBox(height: 10),
          _SourcesMobileReferenceList(),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _SourceActionButton('Open source')),
              SizedBox(width: 12),
              Expanded(
                child: _SourceActionButton('Detach memory', danger: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _SourcesMobileReferenceList extends StatelessWidget {
  const _SourcesMobileReferenceList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 8),
      child: const Column(
        children: [
          _SourcesMobileReferenceRow(
            'No meetings before 9 AM',
            'Preference',
            '"I normally do deep work before 9..."',
            'High',
            Color(0xFF08945F),
          ),
          _SourcesMobileReferenceRow(
            'Reply to tasks in Chinese',
            'Communication preference',
            '"Please reply in Chinese for tasks."',
            'High',
            Color(0xFF08945F),
          ),
          _SourcesMobileReferenceRow(
            'Alex prefers afternoon meetings',
            'Person',
            '"Alex said afternoon meetings are efficient."',
            'High',
            AgentHomeStoryboard.blue,
          ),
        ],
      ),
    );
  }
}

final class _SourcesMobileReferenceRow extends StatelessWidget {
  const _SourcesMobileReferenceRow(
    this.title,
    this.type,
    this.snippet,
    this.confidence,
    this.color,
  );

  final String title;
  final String type;
  final String snippet;
  final String confidence;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph(title[0], color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(type, style: _mutedBold(11)),
                const SizedBox(height: 6),
                Text(snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedBold(11)),
              ],
            ),
          ),
          Text(confidence,
              style: const TextStyle(
                  color: Color(0xFF08945F),
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _SourceIcon extends StatelessWidget {
  const _SourceIcon({
    required this.icon,
    required this.color,
    this.small = false,
    this.large = false,
  });

  final String icon;
  final Color color;
  final bool small;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 44.0 : (small ? 30.0 : 42.0);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        icon,
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 15 : 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _MemorySourcesNotesStrip extends StatelessWidget {
  const _MemorySourcesNotesStrip();

  static const _notes = [
    (
      title: 'Sources explain why memory exists.',
      body: 'Each memory shows where it came from.',
    ),
    (
      title: 'Users can inspect readable snippets.',
      body: 'Snippets are quoted in plain language.',
    ),
    (
      title: 'Files and conversations are separate sources.',
      body: 'Different source types are kept distinct.',
    ),
    (
      title: 'Detach if a source is wrong.',
      body: 'Detached memories can be reviewed or removed.',
    ),
    (
      title: 'No saved memory list here.',
      body: 'This tab is only about sources, not what is saved.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_sources_interaction_notes'),
      height: 222,
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(36, 32, 44, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 138,
            child: Text('Interaction\nNotes',
                style: TextStyle(
                    fontSize: 20, height: 1.25, fontWeight: FontWeight.w900)),
          ),
          const _NoteDivider(),
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
