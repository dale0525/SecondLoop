part of 'agent_home_storyboard.dart';

final class AgentSettingsActivityStoryboard extends StatelessWidget {
  const AgentSettingsActivityStoryboard({super.key});

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
            child: _SettingsActivityCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _SettingsActivityCanvas extends StatelessWidget {
  const _SettingsActivityCanvas();

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
                _SettingsActivityWorkspace(),
                SizedBox(width: 32),
                _SettingsActivityPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 12),
          _SettingsActivityNotesStrip(),
        ],
      ),
    );
  }
}

final class _SettingsActivityWorkspace extends StatelessWidget {
  const _SettingsActivityWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_activity_workspace'),
      width: 1532,
      height: 1128,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _SettingsSidebar(),
          _VLine(),
          Expanded(child: _SettingsActivityDesktopBody()),
        ],
      ),
    );
  }
}

final class _SettingsActivityDesktopBody extends StatelessWidget {
  const _SettingsActivityDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(34, 32, 34, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(),
          SizedBox(height: 26),
          _SettingsTabs(selected: 'Activity'),
          SizedBox(height: 34),
          _SettingsActivityTitle(),
          SizedBox(height: 26),
          _ActivityTable(),
          SizedBox(height: 28),
          _ActivitySafetyCard(),
          SizedBox(height: 24),
          _ActivityExportCard(),
        ],
      ),
    );
  }
}

final class _SettingsActivityTitle extends StatelessWidget {
  const _SettingsActivityTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Activity transparency',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        SizedBox(height: 10),
        Text(
          'See what SecondLoop did, in plain language.',
          style: TextStyle(
              color: AgentHomeStoryboard.muted,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

enum _ActivityStatus { completed, needsOk }

final class _ActivitySpec {
  const _ActivitySpec({
    required this.time,
    required this.glyph,
    required this.action,
    required this.source,
    required this.status,
    this.section,
  });

  final String time;
  final String glyph;
  final String action;
  final String source;
  final _ActivityStatus status;
  final String? section;
}

const _activitySpecs = [
  _ActivitySpec(
    section: 'Today',
    time: '10:21',
    glyph: 'C',
    action: 'Read calendar availability',
    source: 'Calendar',
    status: _ActivityStatus.completed,
  ),
  _ActivitySpec(
    time: '10:18',
    glyph: 'E',
    action: 'Drafted email',
    source: 'Conversation',
    status: _ActivityStatus.completed,
  ),
  _ActivitySpec(
    time: '10:15',
    glyph: 'T',
    action: 'Prepared task change',
    source: 'Conversation',
    status: _ActivityStatus.needsOk,
  ),
  _ActivitySpec(
    time: '09:45',
    glyph: 'R',
    action: 'Saved research draft',
    source: 'Conversation',
    status: _ActivityStatus.completed,
  ),
  _ActivitySpec(
    section: 'This week',
    time: 'May 19, 19:32',
    glyph: 'N',
    action: 'Created reminder candidate',
    source: 'Conversation',
    status: _ActivityStatus.needsOk,
  ),
];

final class _ActivityTable extends StatelessWidget {
  const _ActivityTable();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 508,
      decoration: _box(radius: 9),
      child: Column(
        children: [
          const _ActivityTableHeader(),
          for (final spec in _activitySpecs) ...[
            if (spec.section != null) _ActivitySectionRow(spec.section!),
            _ActivityTableRow(spec),
          ],
        ],
      ),
    );
  }
}

final class _ActivityTableHeader extends StatelessWidget {
  const _ActivityTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: 210, child: Text('Time', style: _mutedBold(15))),
          SizedBox(width: 360, child: Text('Action', style: _mutedBold(15))),
          SizedBox(width: 270, child: Text('Source', style: _mutedBold(15))),
          SizedBox(width: 220, child: Text('Status', style: _mutedBold(15))),
          Expanded(child: Text('Details', style: _mutedBold(15))),
        ],
      ),
    );
  }
}

final class _ActivitySectionRow extends StatelessWidget {
  const _ActivitySectionRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
    );
  }
}

final class _ActivityTableRow extends StatelessWidget {
  const _ActivityTableRow(this.spec);

  final _ActivitySpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 210,
            child: Text(spec.time, style: _mutedBold(15)),
          ),
          SizedBox(
            width: 360,
            child: Row(
              children: [
                _Glyph(spec.glyph, color: const Color(0xFF485777)),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    spec.action,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 270,
            child: Text(spec.source, style: _mutedBold(15)),
          ),
          SizedBox(width: 220, child: _ActivityStatusText(spec.status)),
          const Expanded(
            child: Text('View details',
                style: TextStyle(
                    color: AgentHomeStoryboard.blue,
                    fontSize: 15,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

final class _ActivityStatusText extends StatelessWidget {
  const _ActivityStatusText(this.status);

  final _ActivityStatus status;

  @override
  Widget build(BuildContext context) {
    final isOk = status == _ActivityStatus.completed;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: isOk ? const Color(0xFF159364) : const Color(0xFFFF8A00),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          isOk ? 'Completed' : 'Needs your OK',
          style: TextStyle(
            color: isOk ? const Color(0xFF159364) : const Color(0xFFFF8A00),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

final class _ActivitySafetyCard extends StatelessWidget {
  const _ActivitySafetyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: _box(radius: 9, color: const Color(0xFFFBFDFF)),
      child: Row(
        children: [
          const _Glyph('S', color: AgentHomeStoryboard.blue),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Activity shows what SecondLoop did and why.',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('Nothing is applied until you approve.',
                    style: _mutedBold(15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ActivityExportCard extends StatelessWidget {
  const _ActivityExportCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: _box(radius: 9),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: _box(
                radius: 10,
                color: const Color(0xFFEAF1FF),
                border: const Color(0xFFEAF1FF)),
            child: const Text('v',
                style: TextStyle(
                    color: AgentHomeStoryboard.blue,
                    fontSize: 24,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 28),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Export diagnostic summary',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                Text(
                  'Get a human-readable summary of recent activity, approvals, and system health.',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 30),
          const SizedBox(
            width: 280,
            child: _SmallButton('Export diagnostic summary'),
          ),
        ],
      ),
    );
  }
}

final class _SettingsActivityPhoneFrame extends StatelessWidget {
  const _SettingsActivityPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_activity_mobile_mock'),
      width: 470,
      height: 1128,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _SettingsActivityMobileCanvas(),
      ),
    );
  }
}

final class _SettingsActivityMobileCanvas extends StatelessWidget {
  const _SettingsActivityMobileCanvas();

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
            _SettingsActivityMobileTabs(),
            SizedBox(height: 22),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsActivityTitle(),
                    SizedBox(height: 18),
                    _ActivityMobileList(),
                    SizedBox(height: 14),
                    _ActivitySafetyCard(),
                    SizedBox(height: 14),
                    _ActivityMobileExportCard(),
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

final class _SettingsActivityMobileTabs extends StatelessWidget {
  const _SettingsActivityMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _SettingsMobileTab('Account')),
          Expanded(child: _SettingsMobileTab('Connection')),
          Expanded(child: _SettingsMobileTab('Permissions')),
          Expanded(child: _SettingsMobileTab('Memory')),
          Expanded(child: _SettingsMobileTab('Activity', selected: true)),
        ],
      ),
    );
  }
}

final class _ActivityMobileList extends StatelessWidget {
  const _ActivityMobileList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: Column(
        children: [
          for (final spec in _activitySpecs) ...[
            if (spec.section != null) _ActivityMobileSection(spec.section!),
            _ActivityMobileRow(spec),
          ],
        ],
      ),
    );
  }
}

final class _ActivityMobileSection extends StatelessWidget {
  const _ActivityMobileSection(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
    );
  }
}

final class _ActivityMobileRow extends StatelessWidget {
  const _ActivityMobileRow(this.spec);

  final _ActivitySpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: 58, child: Text(spec.time, style: _mutedBold(12))),
          _Glyph(spec.glyph, color: const Color(0xFF485777)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${spec.action}\n${spec.source}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, height: 1.3, fontWeight: FontWeight.w800),
            ),
          ),
          _ActivityStatusDot(spec.status),
          const SizedBox(width: 14),
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

final class _ActivityStatusDot extends StatelessWidget {
  const _ActivityStatusDot(this.status);

  final _ActivityStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: status == _ActivityStatus.completed
            ? const Color(0xFF159364)
            : const Color(0xFFFF8A00),
        shape: BoxShape.circle,
      ),
    );
  }
}

final class _ActivityMobileExportCard extends StatelessWidget {
  const _ActivityMobileExportCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(radius: 9),
      child: const Row(
        children: [
          _Glyph('v', color: AgentHomeStoryboard.blue),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'Export diagnostic summary\nGet a human-readable summary of recent activity, approvals, and system health.',
              style: TextStyle(
                  fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
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

final class _SettingsActivityNotesStrip extends StatelessWidget {
  const _SettingsActivityNotesStrip();

  static const _notes = [
    (
      title: 'Activity shows what happened.',
      body: 'Every entry is a plain-language record of what SecondLoop did.',
    ),
    (
      title: 'Actions are plain-language.',
      body: 'You see the action in everyday words, not technical terms.',
    ),
    (
      title: 'Sources stay visible.',
      body: 'Each action shows where it came from.',
    ),
    (
      title: 'Diagnostics stay secondary.',
      body: "Exports are available but won't distract from the main view.",
    ),
    (
      title: 'No connection setup here.',
      body: 'Runtime mode and connections belong to another tab.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_activity_interaction_notes'),
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
