part of 'agent_home_storyboard.dart';

final class AgentSettingsConnectionStoryboard extends StatelessWidget {
  const AgentSettingsConnectionStoryboard({super.key});

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
            child: _SettingsConnectionCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _SettingsConnectionCanvas extends StatelessWidget {
  const _SettingsConnectionCanvas();

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
                _SettingsConnectionWorkspace(),
                SizedBox(width: 32),
                _SettingsConnectionPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 12),
          _SettingsConnectionNotesStrip(),
        ],
      ),
    );
  }
}

final class _SettingsConnectionWorkspace extends StatelessWidget {
  const _SettingsConnectionWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_connection_workspace'),
      width: 1532,
      height: 1128,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _SettingsSidebar(),
          _VLine(),
          Expanded(child: _SettingsConnectionDesktopBody()),
        ],
      ),
    );
  }
}

final class _SettingsConnectionDesktopBody extends StatelessWidget {
  const _SettingsConnectionDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(34, 32, 34, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(),
          SizedBox(height: 26),
          _SettingsTabs(selected: 'Connection'),
          SizedBox(height: 34),
          _SettingsConnectionTitle(),
          SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ManagedProConnectionCard()),
              SizedBox(width: 26),
              Expanded(child: _SelfManagedConnectionCard()),
            ],
          ),
          SizedBox(height: 22),
          _ConnectionInfoBanner(),
          SizedBox(height: 22),
          _ConnectionHealthCard(),
        ],
      ),
    );
  }
}

final class _SettingsConnectionTitle extends StatelessWidget {
  const _SettingsConnectionTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Connection',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        SizedBox(height: 10),
        Text(
          'Choose how SecondLoop runs for you.',
          style: TextStyle(
              color: AgentHomeStoryboard.muted,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

final class _ManagedProConnectionCard extends StatelessWidget {
  const _ManagedProConnectionCard();

  static const _items = [
    'Ready to use',
    'No Cloudflare setup',
    'No BYOK required',
    'Same assistant abilities and user experience',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 438,
      padding: const EdgeInsets.all(28),
      decoration: _box(
        radius: 9,
        border: AgentHomeStoryboard.blue,
        borderWidth: 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ConnectionModeHeader(
            glyph: 'C',
            color: AgentHomeStoryboard.blue,
            title: 'Managed Pro',
            subtitle: 'Hosted by SecondLoop. No setup needed.',
            selected: true,
            chip: 'Recommended',
          ),
          const SizedBox(height: 34),
          for (final item in _items) ...[
            _ConnectionCheckRow(item),
            const SizedBox(height: 20),
          ],
          const Spacer(),
          const _ConnectionReadyBox(),
        ],
      ),
    );
  }
}

final class _SelfManagedConnectionCard extends StatelessWidget {
  const _SelfManagedConnectionCard();

  static const _steps = [
    (
      number: '1',
      title: 'Connect Cloudflare',
      body: 'Authorize and provision resources',
    ),
    (
      number: '2',
      title: 'Add model keys',
      body: 'Store securely in your Cloudflare account',
    ),
    (
      number: '3',
      title: 'Check assistant abilities',
      body: 'Verify everything works as expected',
    ),
    (
      number: '4',
      title: 'Save connection',
      body: 'Start using your self-managed setup',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 438,
      padding: const EdgeInsets.all(28),
      decoration: _box(radius: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ConnectionModeHeader(
            glyph: 'S',
            color: Color(0xFF485777),
            title: 'Self-managed / Open-source',
            subtitle: 'You host the runtime in your own Cloudflare account.',
          ),
          const SizedBox(height: 26),
          for (final step in _steps)
            _ConnectionStep(
              number: step.number,
              title: step.title,
              body: step.body,
              last: step.number == '4',
            ),
        ],
      ),
    );
  }
}

final class _ConnectionModeHeader extends StatelessWidget {
  const _ConnectionModeHeader({
    required this.glyph,
    required this.color,
    required this.title,
    required this.subtitle,
    this.selected = false,
    this.chip,
  });

  final String glyph;
  final Color color;
  final String title;
  final String subtitle;
  final bool selected;
  final String? chip;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ConnectionIcon(glyph, color: color),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (chip != null) ...[
                    const SizedBox(width: 12),
                    _Chip(chip!, tone: _Tone.blue),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(subtitle, style: _mutedBold(15)),
            ],
          ),
        ),
        const SizedBox(width: 14),
        _ConnectionRadio(selected: selected),
      ],
    );
  }
}

final class _ConnectionIcon extends StatelessWidget {
  const _ConnectionIcon(this.glyph, {required this.color});

  final String glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B5CF6),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        glyph,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _ConnectionRadio extends StatelessWidget {
  const _ConnectionRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AgentHomeStoryboard.blue : const Color(0xFF9AA8BF),
          width: selected ? 7 : 2,
        ),
      ),
    );
  }
}

final class _ConnectionCheckRow extends StatelessWidget {
  const _ConnectionCheckRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('+',
            style: TextStyle(
                color: Color(0xFF159364),
                fontSize: 20,
                fontWeight: FontWeight.w900)),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

final class _ConnectionReadyBox extends StatelessWidget {
  const _ConnectionReadyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: _box(
        radius: 8,
        color: const Color(0xFFF2FBF7),
        border: const Color(0xFFCDE9DA),
      ),
      child: const Row(
        children: [
          _ReadyDot(),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              "Ready\nEverything is set. You're good to go.",
              style: TextStyle(
                color: Color(0xFF159364),
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ReadyDot extends StatelessWidget {
  const _ReadyDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF159364),
        shape: BoxShape.circle,
      ),
      child: const Text('+',
          style: TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
    );
  }
}

final class _ConnectionStep extends StatelessWidget {
  const _ConnectionStep({
    required this.number,
    required this.title,
    required this.body,
    required this.last,
  });

  final String number;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 31,
                height: 31,
                alignment: Alignment.center,
                decoration: _box(
                  radius: 16,
                  color: const Color(0xFFF6F8FC),
                  border: const Color(0xFFCAD3E2),
                ),
                child: Text(number,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900)),
              ),
              if (!last)
                Container(
                  width: 2,
                  height: 41,
                  color: AgentHomeStoryboard.line,
                ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(body, style: _mutedBold(14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ConnectionInfoBanner extends StatelessWidget {
  const _ConnectionInfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _box(
        radius: 8,
        color: const Color(0xFFFBFDFF),
        border: AgentHomeStoryboard.blue,
      ),
      child: Row(
        children: [
          const _Glyph('i', color: AgentHomeStoryboard.blue),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              'Both modes provide the same assistant abilities, data controls, and user experience.',
              style: _mutedBold(15),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ConnectionHealthCard extends StatelessWidget {
  const _ConnectionHealthCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: _box(radius: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Connection health',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 22),
          const Row(
            children: [
              Expanded(
                child: _ConnectionHealthItem(
                  glyph: 'N',
                  title: 'Network',
                  state: 'Good',
                  body: 'Connected',
                ),
              ),
              _VLine(height: 72),
              Expanded(
                child: _ConnectionHealthItem(
                  glyph: 'A',
                  title: 'Assistant service',
                  state: 'Good',
                  body: 'All services operational',
                ),
              ),
              _VLine(height: 72),
              Expanded(
                child: _ConnectionHealthItem(
                  glyph: 'D',
                  title: 'Data storage',
                  state: 'Good',
                  body: 'Encrypted and accessible',
                ),
              ),
              SizedBox(width: 26),
              SizedBox(width: 210, child: _SmallButton('Test connection')),
            ],
          ),
          const Spacer(),
          Text(
            'Last checked: May 20, 2025 10:14   -   Auto-check: Every 15 min',
            style: _mutedBold(13),
          ),
        ],
      ),
    );
  }
}

final class _ConnectionHealthItem extends StatelessWidget {
  const _ConnectionHealthItem({
    required this.glyph,
    required this.title,
    required this.state,
    required this.body,
  });

  final String glyph;
  final String title;
  final String state;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Glyph(glyph, color: const Color(0xFF485777)),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            '$title   + $state\n$body',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

final class _SettingsConnectionPhoneFrame extends StatelessWidget {
  const _SettingsConnectionPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_connection_mobile_mock'),
      width: 470,
      height: 1128,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _SettingsConnectionMobileCanvas(),
      ),
    );
  }
}

final class _SettingsConnectionMobileCanvas extends StatelessWidget {
  const _SettingsConnectionMobileCanvas();

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
            _SettingsConnectionMobileTabs(),
            SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MobileManagedProConnection(),
                    SizedBox(height: 14),
                    _MobileSelfManagedConnection(),
                    SizedBox(height: 14),
                    _MobileConnectionHealth(),
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

final class _SettingsConnectionMobileTabs extends StatelessWidget {
  const _SettingsConnectionMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _SettingsMobileTab('Account')),
          Expanded(child: _SettingsMobileTab('Connection', selected: true)),
          Expanded(child: _SettingsMobileTab('Permissions')),
          Expanded(child: _SettingsMobileTab('Memory')),
          Expanded(child: _SettingsMobileTab('Activity')),
        ],
      ),
    );
  }
}

final class _MobileManagedProConnection extends StatelessWidget {
  const _MobileManagedProConnection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(
        radius: 9,
        border: AgentHomeStoryboard.blue,
        borderWidth: 2,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConnectionModeHeader(
            glyph: 'C',
            color: AgentHomeStoryboard.blue,
            title: 'Managed Pro',
            subtitle: 'Hosted by SecondLoop. No setup needed.',
            selected: true,
            chip: 'Recommended',
          ),
          SizedBox(height: 18),
          _ConnectionCheckRow('Ready to use'),
          SizedBox(height: 11),
          _ConnectionCheckRow('No Cloudflare setup'),
          SizedBox(height: 11),
          _ConnectionCheckRow('No BYOK required'),
          SizedBox(height: 11),
          _ConnectionCheckRow('Same assistant abilities and user experience'),
          SizedBox(height: 16),
          _ConnectionReadyBox(),
        ],
      ),
    );
  }
}

final class _MobileSelfManagedConnection extends StatelessWidget {
  const _MobileSelfManagedConnection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(radius: 9),
      child: const Row(
        children: [
          _ConnectionIcon('S', color: Color(0xFF485777)),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'Self-managed /\nOpen-source\n\nYou host the runtime in your own Cloudflare account.\n\n4 setup steps',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text('>',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _MobileConnectionHealth extends StatelessWidget {
  const _MobileConnectionHealth();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _box(radius: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Connection health',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: _MobileConnectionHealthItem('N', 'Network')),
              _VLine(height: 74),
              Expanded(child: _MobileConnectionHealthItem('A', 'Service')),
              _VLine(height: 74),
              Expanded(child: _MobileConnectionHealthItem('D', 'Storage')),
            ],
          ),
          const SizedBox(height: 14),
          const _SmallButton('Test connection'),
          const SizedBox(height: 10),
          Center(
            child: Text('Last checked: May 20, 10:14', style: _mutedBold(12)),
          ),
        ],
      ),
    );
  }
}

final class _MobileConnectionHealthItem extends StatelessWidget {
  const _MobileConnectionHealthItem(this.glyph, this.label);

  final String glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Glyph(glyph, color: const Color(0xFF485777)),
        const SizedBox(height: 8),
        const Text('Good',
            style: TextStyle(
                color: Color(0xFF159364),
                fontSize: 13,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

final class _SettingsConnectionNotesStrip extends StatelessWidget {
  const _SettingsConnectionNotesStrip();

  static const _notes = [
    (
      title: 'Connection is runtime setup.',
      body: 'It covers where and how SecondLoop runs, not what it can do.',
    ),
    (
      title: 'Both modes keep the same UX.',
      body: 'You get the same assistant abilities, controls, and experience.',
    ),
    (
      title: 'Self-managed has setup steps.',
      body: 'Connect Cloudflare, add keys, verify, then save.',
    ),
    (
      title: 'Permissions live in another tab.',
      body: 'Allowed actions are managed in the Permissions tab.',
    ),
    (
      title: 'Activity lives in another tab.',
      body: 'History and transparency are managed in the Activity tab.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_connection_interaction_notes'),
      height: 208,
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
