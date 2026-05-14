part of 'agent_home_storyboard.dart';

final class AgentMemoryPreferencesStoryboard extends StatelessWidget {
  const AgentMemoryPreferencesStoryboard({super.key});

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
            child: _MemoryPreferencesCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _MemoryPreferencesCanvas extends StatelessWidget {
  const _MemoryPreferencesCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1088,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MemoryPreferencesWorkspace(),
                SizedBox(width: 36),
                _MemoryPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 38),
          _MemoryNotesStrip(),
        ],
      ),
    );
  }
}

final class _MemoryPreferencesWorkspace extends StatelessWidget {
  const _MemoryPreferencesWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_preferences_workspace'),
      width: 1520,
      height: 1088,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _MemorySidebar(),
          _VLine(),
          Expanded(child: _MemoryDesktopBody()),
        ],
      ),
    );
  }
}

final class _MemorySidebar extends StatelessWidget {
  const _MemorySidebar();

  static const _items = [
    (label: 'Conversation', glyph: 'C', selected: false, badge: ''),
    (label: 'Memory', glyph: 'M', selected: true, badge: ''),
    (label: 'Review', glyph: 'R', selected: false, badge: '2'),
    (label: 'Settings', glyph: 'S', selected: false, badge: ''),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 36, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Brand(),
            const SizedBox(height: 62),
            for (final item in _items) ...[
              _ReviewNavItem(
                label: item.label,
                glyph: item.glyph,
                selected: item.selected,
                badge: item.badge,
              ),
              const SizedBox(height: 20),
            ],
            const Spacer(),
            const Divider(color: AgentHomeStoryboard.line),
            const SizedBox(height: 16),
            const _AccountFooter(),
          ],
        ),
      ),
    );
  }
}

final class _MemoryDesktopBody extends StatelessWidget {
  const _MemoryDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 36, 32, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoryHeader(),
          SizedBox(height: 32),
          _MemoryTabs(),
          SizedBox(height: 38),
          _PreferencesTitleRow(),
          SizedBox(height: 30),
          _PreferencesTable(),
          SizedBox(height: 38),
          _PendingPreferenceCard(),
          SizedBox(height: 36),
          _MemoryPrivacyBox(),
        ],
      ),
    );
  }
}

final class _MemoryHeader extends StatelessWidget {
  const _MemoryHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text('Memory',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
        ),
        const _Glyph('L', color: Color(0xFF485777)),
        const SizedBox(width: 12),
        Text(
          'All memory is private and editable.',
          style: _mutedBold(16),
        ),
      ],
    );
  }
}

final class _MemoryTabs extends StatelessWidget {
  const _MemoryTabs();

  static const _tabs = [
    (label: 'Preferences', selected: true),
    (label: 'People', selected: false),
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

final class _MemoryTab extends StatelessWidget {
  const _MemoryTab({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: selected
            ? const Border(
                bottom: BorderSide(color: AgentHomeStoryboard.blue, width: 3),
              )
            : null,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.muted,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

final class _PreferencesTitleRow extends StatelessWidget {
  const _PreferencesTitleRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preferences',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              SizedBox(height: 12),
              Text(
                'Personal rules SecondLoop can use when helping you.',
                style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: _box(radius: 7),
          child: const Row(
            children: [
              Text('+',
                  style: TextStyle(
                      color: AgentHomeStoryboard.blue,
                      fontSize: 28,
                      fontWeight: FontWeight.w500)),
              SizedBox(width: 12),
              Text('Add preference',
                  style: TextStyle(
                      color: AgentHomeStoryboard.blue,
                      fontSize: 17,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ],
    );
  }
}

final class _PreferencesTable extends StatelessWidget {
  const _PreferencesTable();

  static const _rows = [
    (
      title: 'Meetings do not start before 9 AM',
      glyph: 'C',
      source: 'You',
      confidence: 'High',
      tone: _Tone.green,
      lastUsed: 'May 20, 2025',
    ),
    (
      title: 'Task replies should use Chinese',
      glyph: 'Q',
      source: 'You',
      confidence: 'High',
      tone: _Tone.green,
      lastUsed: 'May 20, 2025',
    ),
    (
      title: 'Focus time 14:00-15:00',
      glyph: 'O',
      source: 'You',
      confidence: 'High',
      tone: _Tone.green,
      lastUsed: 'May 19, 2025',
    ),
    (
      title: 'Prefer concise summaries',
      glyph: 'S',
      source: 'You',
      confidence: 'Medium',
      tone: _Tone.orange,
      lastUsed: 'May 18, 2025',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: Column(
        children: [
          const _PreferenceHeaderRow(),
          for (final row in _rows)
            _PreferenceRow(
              title: row.title,
              glyph: row.glyph,
              source: row.source,
              confidence: row.confidence,
              tone: row.tone,
              lastUsed: row.lastUsed,
            ),
        ],
      ),
    );
  }
}

final class _PreferenceHeaderRow extends StatelessWidget {
  const _PreferenceHeaderRow();

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Preference',
      'Source',
      'Confidence',
      'Last used',
      'Actions'
    ];
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: i == 0 ? 4 : 2,
              child: Text(labels[i], style: _mutedBold(14)),
            ),
        ],
      ),
    );
  }
}

final class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.title,
    required this.glyph,
    required this.source,
    required this.confidence,
    required this.tone,
    required this.lastUsed,
  });

  final String title;
  final String glyph;
  final String source;
  final String confidence;
  final _Tone tone;
  final String lastUsed;

  @override
  Widget build(BuildContext context) {
    final dot = tone == _Tone.orange
        ? const Color(0xFFFF8A00)
        : const Color(0xFF08945F);
    return Container(
      height: 88,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _Glyph(glyph,
                    color: tone == _Tone.orange
                        ? AgentHomeStoryboard.blue
                        : const Color(0xFF08945F)),
                const SizedBox(width: 24),
                Expanded(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(source, style: _mutedBold(16))),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Text(confidence, style: _mutedBold(16)),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(lastUsed, style: _mutedBold(16))),
          const Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SmallButton('Edit'),
                SizedBox(width: 12),
                _SmallButton('Forget', danger: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _PendingPreferenceCard extends StatelessWidget {
  const _PendingPreferenceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pending preference candidate (1)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          SizedBox(height: 14),
          _PendingPreferenceBody(),
        ],
      ),
    );
  }
}

final class _PendingPreferenceBody extends StatelessWidget {
  const _PendingPreferenceBody();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(radius: 8),
      child: const Row(
        children: [
          _Glyph('*', color: Color(0xFF815CFF)),
          SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Do not schedule meetings after 18:00',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                Text('From your message  -  May 20, 2025',
                    style: TextStyle(
                        color: AgentHomeStoryboard.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 12),
                Text('Suggested based on your availability preferences.',
                    style: TextStyle(
                        color: AgentHomeStoryboard.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          _SmallButton('Accept', success: true),
          SizedBox(width: 14),
          _SmallButton('Edit'),
          SizedBox(width: 14),
          _SmallButton('Ignore'),
        ],
      ),
    );
  }
}

final class _MemoryPrivacyBox extends StatelessWidget {
  const _MemoryPrivacyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _box(
        radius: 7,
        color: const Color(0xFFF0FBF7),
        border: const Color(0xFFCFEFE2),
      ),
      child: const Row(
        children: [
          _Glyph('V', color: Color(0xFF08945F)),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'Your preferences are used only to personalize responses and suggestions.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Color(0xFF1B5C47),
                  fontSize: 15,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _MemoryPhoneFrame extends StatelessWidget {
  const _MemoryPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_mobile_mock'),
      width: 430,
      height: 1088,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _MemoryMobileCanvas(),
      ),
    );
  }
}

final class _MemoryMobileCanvas extends StatelessWidget {
  const _MemoryMobileCanvas();

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
            SizedBox(height: 22),
            _MemoryMobileTabs(),
            SizedBox(height: 26),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MemoryMobileTitle(),
                    SizedBox(height: 18),
                    _MemoryMobileList(),
                    SizedBox(height: 24),
                    _MemoryMobilePendingCard(),
                    SizedBox(height: 18),
                    _MemoryPrivacyBox(),
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

final class _MemoryMobileHeader extends StatelessWidget {
  const _MemoryMobileHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('=', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Expanded(
          child: Text('Memory',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ),
        _Glyph('P', color: Color(0xFF485777)),
      ],
    );
  }
}

final class _MemoryMobileTabs extends StatelessWidget {
  const _MemoryMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _MemoryTab(label: 'Preferences', selected: true)),
          Expanded(child: _MemoryTab(label: 'People', selected: false)),
          Expanded(child: _MemoryTab(label: 'Projects', selected: false)),
          Expanded(child: _MemoryTab(label: 'More', selected: false)),
        ],
      ),
    );
  }
}

final class _MemoryMobileTitle extends StatelessWidget {
  const _MemoryMobileTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preferences',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Text(
                'Personal rules SecondLoop can use when helping you.',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Container(
          width: 52,
          height: 46,
          alignment: Alignment.center,
          decoration: _box(radius: 7),
          child: const Text('+',
              style: TextStyle(
                  color: AgentHomeStoryboard.blue,
                  fontSize: 28,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

final class _MemoryMobileList extends StatelessWidget {
  const _MemoryMobileList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: const Column(
        children: [
          _MemoryMobileRow(
              'Meetings do not start before 9 AM', 'High', _Tone.green, 'C'),
          _MemoryMobileRow(
              'Task replies should use Chinese', 'High', _Tone.green, 'Q'),
          _MemoryMobileRow('Focus time 14:00-15:00', 'High', _Tone.green, 'O'),
          _MemoryMobileRow(
              'Prefer concise summaries', 'Medium', _Tone.orange, 'S'),
        ],
      ),
    );
  }
}

final class _MemoryMobileRow extends StatelessWidget {
  const _MemoryMobileRow(this.title, this.confidence, this.tone, this.glyph);

  final String title;
  final String confidence;
  final _Tone tone;
  final String glyph;

  @override
  Widget build(BuildContext context) {
    final dot = tone == _Tone.orange
        ? const Color(0xFFFF8A00)
        : const Color(0xFF08945F);
    return Container(
      height: 82,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Glyph(glyph,
              color: tone == _Tone.orange
                  ? AgentHomeStoryboard.blue
                  : const Color(0xFF08945F)),
          const SizedBox(width: 14),
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
                const SizedBox(height: 4),
                Text('You', style: _mutedBold(13)),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(confidence, style: _mutedBold(13)),
          const SizedBox(width: 8),
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

final class _MemoryMobilePendingCard extends StatelessWidget {
  const _MemoryMobilePendingCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pending preference candidate (1)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _box(radius: 9),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Glyph('*', color: Color(0xFF815CFF)),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Do not schedule meetings after 18:00',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.only(left: 38),
                child: Text(
                  'From your message  -  May 20, 2025',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(height: 14),
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
        ),
      ],
    );
  }
}

final class _MemoryBottomNav extends StatelessWidget {
  const _MemoryBottomNav();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 54,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BottomNavItem('Conversation', 'C'),
          _BottomNavItem('Memory', 'M', selected: true),
          _BottomNavItem('Review', 'R', badge: '2'),
          _BottomNavItem('Settings', 'S'),
        ],
      ),
    );
  }
}

final class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem(
    this.label,
    this.glyph, {
    this.selected = false,
    this.badge,
  });

  final String label;
  final String glyph;
  final bool selected;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _Glyph(glyph, color: color),
            if (badge != null)
              Positioned(right: -8, top: -8, child: _Badge(badge!)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

final class _SmallButton extends StatelessWidget {
  const _SmallButton(
    this.label, {
    this.danger = false,
    this.success = false,
  });

  final String label;
  final bool danger;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.center,
      decoration: _box(radius: 7),
      child: Text(
        label,
        style: TextStyle(
          color: danger
              ? Colors.red
              : success
                  ? const Color(0xFF08945F)
                  : AgentHomeStoryboard.ink,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

final class _MemoryNotesStrip extends StatelessWidget {
  const _MemoryNotesStrip();

  static const _notes = [
    (
      title: 'Preferences guide future replies.',
      body: 'Saved preferences help SecondLoop respond in the way you want.',
    ),
    (
      title: 'Each preference can be edited.',
      body: 'Keep your preferences accurate and up to date.',
    ),
    (
      title: 'New preferences wait for review.',
      body:
          'Candidates are suggested from your messages and need your approval.',
    ),
    (
      title: 'No people or project content here.',
      body: 'This tab is only for your personal preferences.',
    ),
    (
      title: 'Memory stays private.',
      body: 'Only you can see and manage your preferences.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_interaction_notes'),
      height: 212,
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
