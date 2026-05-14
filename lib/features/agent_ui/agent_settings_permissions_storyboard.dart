part of 'agent_home_storyboard.dart';

final class AgentSettingsPermissionsStoryboard extends StatelessWidget {
  const AgentSettingsPermissionsStoryboard({super.key});

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
            child: _SettingsPermissionsCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _SettingsPermissionsCanvas extends StatelessWidget {
  const _SettingsPermissionsCanvas();

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
                _SettingsPermissionsWorkspace(),
                SizedBox(width: 32),
                _SettingsPermissionsPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 12),
          _SettingsPermissionsNotesStrip(),
        ],
      ),
    );
  }
}

final class _SettingsPermissionsWorkspace extends StatelessWidget {
  const _SettingsPermissionsWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_permissions_workspace'),
      width: 1532,
      height: 1128,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _SettingsSidebar(),
          _VLine(),
          Expanded(child: _SettingsPermissionsDesktopBody()),
        ],
      ),
    );
  }
}

final class _SettingsPermissionsDesktopBody extends StatelessWidget {
  const _SettingsPermissionsDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(34, 32, 34, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(),
          SizedBox(height: 26),
          _SettingsTabs(selected: 'Permissions'),
          SizedBox(height: 34),
          _SettingsPermissionsTitle(),
          SizedBox(height: 26),
          _PermissionsInfoBanner(),
          SizedBox(height: 30),
          _PermissionsTable(),
          SizedBox(height: 26),
          _PermissionsChangeNote(),
        ],
      ),
    );
  }
}

final class _SettingsPermissionsTitle extends StatelessWidget {
  const _SettingsPermissionsTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Permissions',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        SizedBox(height: 10),
        Text(
          'Manage what SecondLoop can read, draft, or do with approval.',
          style: TextStyle(
              color: AgentHomeStoryboard.muted,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

final class _PermissionsInfoBanner extends StatelessWidget {
  const _PermissionsInfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _box(radius: 8, color: const Color(0xFFFBFDFF)),
      child: Row(
        children: [
          const _Glyph('i', color: AgentHomeStoryboard.blue),
          const SizedBox(width: 18),
          Text(
            'External side effects require approval.',
            style: _mutedBold(15),
          ),
        ],
      ),
    );
  }
}

enum _PermissionState { allowed, needsApproval, off }

final class _PermissionSpec {
  const _PermissionSpec({
    required this.glyph,
    required this.color,
    required this.title,
    required this.body,
    required this.state,
  });

  final String glyph;
  final Color color;
  final String title;
  final String body;
  final _PermissionState state;
}

const _permissionSpecs = [
  _PermissionSpec(
    glyph: 'V',
    color: Color(0xFF14A66E),
    title: 'Vault read',
    body: 'Read your saved memories and notes.',
    state: _PermissionState.allowed,
  ),
  _PermissionSpec(
    glyph: 'C',
    color: AgentHomeStoryboard.blue,
    title: 'Calendar availability',
    body: 'Check free/busy and time windows.',
    state: _PermissionState.allowed,
  ),
  _PermissionSpec(
    glyph: 'E',
    color: AgentHomeStoryboard.blue,
    title: 'Email drafts',
    body: 'Draft emails for your review.',
    state: _PermissionState.allowed,
  ),
  _PermissionSpec(
    glyph: 'S',
    color: Color(0xFFFF7A00),
    title: 'Email send requires approval',
    body: 'Send emails only after you approve.',
    state: _PermissionState.needsApproval,
  ),
  _PermissionSpec(
    glyph: 'F',
    color: AgentHomeStoryboard.blue,
    title: 'Files you attach',
    body: 'Read files you attach in conversation.',
    state: _PermissionState.allowed,
  ),
  _PermissionSpec(
    glyph: 'N',
    color: Color(0xFF9B37DB),
    title: 'Notifications',
    body: 'Send reminders and notifications.',
    state: _PermissionState.off,
  ),
];

final class _PermissionsTable extends StatelessWidget {
  const _PermissionsTable();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 612,
      decoration: _box(radius: 9),
      child: Column(
        children: [
          const _PermissionsTableHeader(),
          for (final spec in _permissionSpecs) _PermissionTableRow(spec),
        ],
      ),
    );
  }
}

final class _PermissionsTableHeader extends StatelessWidget {
  const _PermissionsTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 370, child: Text('Permission', style: _mutedBold(15))),
          Expanded(child: Text('What it allows', style: _mutedBold(15))),
          SizedBox(width: 170, child: Text('State', style: _mutedBold(15))),
          SizedBox(width: 150, child: Text('Action', style: _mutedBold(15))),
        ],
      ),
    );
  }
}

final class _PermissionTableRow extends StatelessWidget {
  const _PermissionTableRow(this.spec);

  final _PermissionSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 91,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 370,
            child: Row(
              children: [
                _PermissionGlyph(spec.glyph, color: spec.color),
                const SizedBox(width: 24),
                Expanded(
                  child: Text(
                    spec.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(spec.body, style: _mutedBold(15)),
          ),
          SizedBox(width: 170, child: _PermissionStateChip(spec.state)),
          const SizedBox(width: 150, child: _PermissionEditButton()),
        ],
      ),
    );
  }
}

final class _PermissionGlyph extends StatelessWidget {
  const _PermissionGlyph(this.glyph, {required this.color});

  final String glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        glyph,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _PermissionStateChip extends StatelessWidget {
  const _PermissionStateChip(this.state);

  final _PermissionState state;

  @override
  Widget build(BuildContext context) {
    final colors = switch (state) {
      _PermissionState.allowed => (
          label: 'Allowed',
          bg: const Color(0xFFEAF9F2),
          fg: const Color(0xFF159364),
          bd: const Color(0xFFC8ECD9),
        ),
      _PermissionState.needsApproval => (
          label: 'Needs approval',
          bg: const Color(0xFFFFF5E8),
          fg: const Color(0xFFFF7A00),
          bd: const Color(0xFFFFE0B8),
        ),
      _PermissionState.off => (
          label: 'Off',
          bg: const Color(0xFFF0F2F5),
          fg: const Color(0xFF63708A),
          bd: const Color(0xFFE0E4EA),
        ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: _box(radius: 6, color: colors.bg, border: colors.bd),
        child: Text(
          colors.label,
          style: TextStyle(
            color: colors.fg,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

final class _PermissionEditButton extends StatelessWidget {
  const _PermissionEditButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      alignment: Alignment.center,
      decoration: _box(radius: 7),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Glyph('E', color: Color(0xFF485777)),
          SizedBox(width: 14),
          Text('Edit',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

final class _PermissionsChangeNote extends StatelessWidget {
  const _PermissionsChangeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _box(radius: 8, color: const Color(0xFFFBFDFF)),
      child: Row(
        children: [
          const _Glyph('L', color: Color(0xFF485777)),
          const SizedBox(width: 18),
          const Text('You can change any permission at any time.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text('Changes apply to future actions only.', style: _mutedBold(15)),
        ],
      ),
    );
  }
}

final class _SettingsPermissionsPhoneFrame extends StatelessWidget {
  const _SettingsPermissionsPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_permissions_mobile_mock'),
      width: 470,
      height: 1128,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _SettingsPermissionsMobileCanvas(),
      ),
    );
  }
}

final class _SettingsPermissionsMobileCanvas extends StatelessWidget {
  const _SettingsPermissionsMobileCanvas();

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
            _SettingsPermissionsMobileTabs(),
            SizedBox(height: 22),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsPermissionsTitle(),
                    SizedBox(height: 18),
                    _PermissionsInfoBanner(),
                    SizedBox(height: 14),
                    _PermissionsMobileList(),
                    SizedBox(height: 14),
                    _PermissionsMobileChangeNote(),
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

final class _SettingsPermissionsMobileTabs extends StatelessWidget {
  const _SettingsPermissionsMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _SettingsMobileTab('Account')),
          Expanded(child: _SettingsMobileTab('Connection')),
          Expanded(child: _SettingsMobileTab('Permissions', selected: true)),
          Expanded(child: _SettingsMobileTab('Memory')),
          Expanded(child: _SettingsMobileTab('Activity')),
        ],
      ),
    );
  }
}

final class _PermissionsMobileList extends StatelessWidget {
  const _PermissionsMobileList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: Column(
        children: [
          for (final spec in _permissionSpecs) _PermissionMobileRow(spec),
        ],
      ),
    );
  }
}

final class _PermissionMobileRow extends StatelessWidget {
  const _PermissionMobileRow(this.spec);

  final _PermissionSpec spec;

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
          _PermissionGlyph(spec.glyph, color: spec.color),
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  spec.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _PermissionStateChip(spec.state),
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

final class _PermissionsMobileChangeNote extends StatelessWidget {
  const _PermissionsMobileChangeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(radius: 9, color: const Color(0xFFFBFDFF)),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph('L', color: Color(0xFF485777)),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'You can change any permission at any time.\nChanges apply to future actions only.',
              style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SettingsPermissionsNotesStrip extends StatelessWidget {
  const _SettingsPermissionsNotesStrip();

  static const _notes = [
    (
      title: 'Permissions describe allowed actions.',
      body: 'This tab explains what SecondLoop can read, draft, or do.',
    ),
    (
      title: 'Read and write are separate.',
      body: 'We show what can be read and what requires approval.',
    ),
    (
      title: 'Sending requires approval.',
      body: 'External actions like sending emails need your OK.',
    ),
    (
      title: 'Connection setup is elsewhere.',
      body: 'Runtime mode and connections live in the Connection tab.',
    ),
    (
      title: 'Activity history is elsewhere.',
      body: 'What happened is shown in the Activity tab.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_permissions_interaction_notes'),
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
