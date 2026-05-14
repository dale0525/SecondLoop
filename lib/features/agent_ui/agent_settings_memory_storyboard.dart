part of 'agent_home_storyboard.dart';

final class AgentSettingsMemoryStoryboard extends StatelessWidget {
  const AgentSettingsMemoryStoryboard({super.key});

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
            child: _SettingsMemoryCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _SettingsMemoryCanvas extends StatelessWidget {
  const _SettingsMemoryCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsMemoryWorkspace(),
                SizedBox(width: 32),
                _SettingsMemoryPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 12),
          _SettingsMemoryNotesStrip(),
        ],
      ),
    );
  }
}

final class _SettingsMemoryWorkspace extends StatelessWidget {
  const _SettingsMemoryWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_memory_workspace'),
      width: 1532,
      height: 1128,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _SettingsSidebar(),
          _VLine(),
          Expanded(child: _SettingsMemoryDesktopBody()),
        ],
      ),
    );
  }
}

final class _SettingsMemoryDesktopBody extends StatelessWidget {
  const _SettingsMemoryDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(34, 32, 34, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(),
          SizedBox(height: 26),
          _SettingsTabs(selected: 'Memory'),
          SizedBox(height: 34),
          _SettingsMemoryTitle(),
          SizedBox(height: 26),
          _SettingsMemoryList(),
          SizedBox(height: 28),
          _SettingsMemoryInfoCard(),
        ],
      ),
    );
  }
}

final class _SettingsMemoryTitle extends StatelessWidget {
  const _SettingsMemoryTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Memory',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        SizedBox(height: 10),
        Text(
          'Control how SecondLoop remembers and uses saved context.',
          style: TextStyle(
              color: AgentHomeStoryboard.muted,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

final class _SettingsMemorySpec {
  const _SettingsMemorySpec({
    required this.glyph,
    required this.color,
    required this.title,
    required this.body,
    this.chevron = false,
    this.danger = false,
  });

  final String glyph;
  final Color color;
  final String title;
  final String body;
  final bool chevron;
  final bool danger;
}

const _settingsMemorySpecs = [
  _SettingsMemorySpec(
    glyph: '*',
    color: AgentHomeStoryboard.blue,
    title: 'Memory suggestions',
    body: 'Suggest new memories from your messages and context.',
  ),
  _SettingsMemorySpec(
    glyph: 'M',
    color: Color(0xFF16A96E),
    title: 'Use memories in conversation',
    body: 'Allow SecondLoop to use saved memories to personalize replies.',
  ),
  _SettingsMemorySpec(
    glyph: 'P',
    color: Color(0xFF815CFF),
    title: 'People memory',
    body: 'Remember facts about people you work with.',
    chevron: true,
  ),
  _SettingsMemorySpec(
    glyph: 'J',
    color: Color(0xFFFF7A00),
    title: 'Project memory',
    body: 'Remember context, goals, and constraints for your projects.',
    chevron: true,
  ),
  _SettingsMemorySpec(
    glyph: 'R',
    color: Color(0xFFE9A928),
    title: 'Review before saving',
    body: 'Require approval before new memories are saved permanently.',
  ),
  _SettingsMemorySpec(
    glyph: 'X',
    color: Color(0xFFFF3333),
    title: 'Forget all memory',
    body: 'Permanently remove all saved memories and context.',
    danger: true,
  ),
];

final class _SettingsMemoryList extends StatelessWidget {
  const _SettingsMemoryList();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 664,
      decoration: _box(radius: 9),
      child: Column(
        children: [
          for (final spec in _settingsMemorySpecs)
            _SettingsMemoryRow(spec: spec),
        ],
      ),
    );
  }
}

final class _SettingsMemoryRow extends StatelessWidget {
  const _SettingsMemoryRow({required this.spec});

  final _SettingsMemorySpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          _SettingsMemoryGlyph(spec.glyph, color: spec.color),
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              '${spec.title}\n${spec.body}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: spec.danger
                    ? const Color(0xFFFF3333)
                    : AgentHomeStoryboard.ink,
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (spec.danger)
            const SizedBox(width: 250, child: _ForgetMemoryButton())
          else ...[
            const _SettingsMemorySwitch(),
            const SizedBox(width: 22),
            const Text('On',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            if (spec.chevron) ...[
              const SizedBox(width: 20),
              const Text('>',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ] else
              const SizedBox(width: 38),
          ],
        ],
      ),
    );
  }
}

final class _SettingsMemoryGlyph extends StatelessWidget {
  const _SettingsMemoryGlyph(this.glyph, {required this.color});

  final String glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        glyph,
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _SettingsMemorySwitch extends StatelessWidget {
  const _SettingsMemorySwitch();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AgentHomeStoryboard.blue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Align(
        alignment: Alignment.centerRight,
        child: DecoratedBox(
          decoration:
              BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: SizedBox(width: 26, height: 26),
        ),
      ),
    );
  }
}

final class _ForgetMemoryButton extends StatelessWidget {
  const _ForgetMemoryButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.center,
      decoration: _box(radius: 8, border: const Color(0xFFFF6F6F)),
      child: const Text(
        'Forget all memory',
        style: TextStyle(
          color: Color(0xFFFF3333),
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _SettingsMemoryInfoCard extends StatelessWidget {
  const _SettingsMemoryInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _box(radius: 8, color: const Color(0xFFF7FCFA)),
      child: const Row(
        children: [
          _Glyph('V', color: Color(0xFF159364)),
          SizedBox(width: 18),
          Expanded(
            child: Text(
              'Long-term memory is editable and requires approval before new facts are saved.',
              style: TextStyle(
                  color: Color(0xFF25755D),
                  fontSize: 15,
                  fontWeight: FontWeight.w800),
            ),
          ),
          Text('Learn more about memory',
              style: TextStyle(
                  color: AgentHomeStoryboard.blue,
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
          SizedBox(width: 10),
          _Glyph('>', color: AgentHomeStoryboard.blue),
        ],
      ),
    );
  }
}

final class _SettingsMemoryPhoneFrame extends StatelessWidget {
  const _SettingsMemoryPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_memory_mobile_mock'),
      width: 470,
      height: 1128,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _SettingsMemoryMobileCanvas(),
      ),
    );
  }
}

final class _SettingsMemoryMobileCanvas extends StatelessWidget {
  const _SettingsMemoryMobileCanvas();

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
            SizedBox(height: 24),
            _SettingsMobileHeader(),
            SizedBox(height: 20),
            _SettingsMemoryMobileTabs(),
            SizedBox(height: 22),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsMemoryTitle(),
                    SizedBox(height: 18),
                    _SettingsMemoryMobileList(),
                    SizedBox(height: 14),
                    _SettingsMemoryMobileInfoCard(),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            _SettingsBottomNav(),
          ],
        ),
      ),
    );
  }
}

final class _SettingsMemoryMobileTabs extends StatelessWidget {
  const _SettingsMemoryMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _SettingsMobileTab('Account')),
          Expanded(child: _SettingsMobileTab('Connection')),
          Expanded(child: _SettingsMobileTab('Permissions')),
          Expanded(child: _SettingsMobileTab('Memory', selected: true)),
          Expanded(child: _SettingsMobileTab('Activity')),
        ],
      ),
    );
  }
}

final class _SettingsMemoryMobileList extends StatelessWidget {
  const _SettingsMemoryMobileList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: Column(
        children: [
          for (final spec in _settingsMemorySpecs)
            _SettingsMemoryMobileRow(spec: spec),
        ],
      ),
    );
  }
}

final class _SettingsMemoryMobileRow extends StatelessWidget {
  const _SettingsMemoryMobileRow({required this.spec});

  final _SettingsMemorySpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          _SettingsMemoryGlyph(spec.glyph, color: spec.color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: spec.danger
                        ? const Color(0xFFFF3333)
                        : AgentHomeStoryboard.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  spec.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (spec.danger)
            const Text('>',
                style: TextStyle(
                    color: Color(0xFFFF3333),
                    fontSize: 18,
                    fontWeight: FontWeight.w900))
          else ...[
            const SizedBox(width: 10),
            const _SettingsMemorySwitch(),
            if (spec.chevron) ...[
              const SizedBox(width: 8),
              const Text('>',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ],
          ],
        ],
      ),
    );
  }
}

final class _SettingsMemoryMobileInfoCard extends StatelessWidget {
  const _SettingsMemoryMobileInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(radius: 9, color: const Color(0xFFF7FCFA)),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph('V', color: Color(0xFF159364)),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Long-term memory is editable and requires approval before new facts are saved.\nLearn more about memory',
              style: TextStyle(
                  color: Color(0xFF25755D),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SettingsMemoryNotesStrip extends StatelessWidget {
  const _SettingsMemoryNotesStrip();

  static const _notes = [
    (
      title: 'This tab controls memory behavior.',
      body:
          'These settings decide what SecondLoop can remember and how it uses it.',
    ),
    (
      title: 'New facts require approval.',
      body:
          'Review before saving ensures accuracy and prevents unwanted memories.',
    ),
    (
      title: 'Users can disable categories.',
      body: "Turn off people or project memory if you don't want them used.",
    ),
    (
      title: 'Saved memories are edited in Memory.',
      body: 'Use the Memory page to view, edit, or forget individual items.',
    ),
    (
      title: 'No activity timeline here.',
      body: 'What happened is shown in the Activity tab.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_memory_interaction_notes'),
      height: 208,
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(30, 30, 48, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 125,
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
