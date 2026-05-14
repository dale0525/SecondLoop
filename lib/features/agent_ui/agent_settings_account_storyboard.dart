part of 'agent_home_storyboard.dart';

final class AgentSettingsAccountStoryboard extends StatelessWidget {
  const AgentSettingsAccountStoryboard({super.key});

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
            child: _SettingsAccountCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _SettingsAccountCanvas extends StatelessWidget {
  const _SettingsAccountCanvas();

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
                _SettingsAccountWorkspace(),
                SizedBox(width: 32),
                _SettingsAccountPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 12),
          _SettingsAccountNotesStrip(),
        ],
      ),
    );
  }
}

final class _SettingsAccountWorkspace extends StatelessWidget {
  const _SettingsAccountWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_account_workspace'),
      width: 1532,
      height: 1128,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _SettingsSidebar(),
          _VLine(),
          Expanded(child: _SettingsAccountDesktopBody()),
        ],
      ),
    );
  }
}

final class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar();

  static const _items = [
    (label: 'Conversation', glyph: 'C', selected: false, badge: ''),
    (label: 'Memory', glyph: 'M', selected: false, badge: ''),
    (label: 'Review', glyph: 'R', selected: false, badge: '2'),
    (label: 'Settings', glyph: 'S', selected: true, badge: ''),
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

final class _SettingsAccountDesktopBody extends StatelessWidget {
  const _SettingsAccountDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(34, 32, 34, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(),
          SizedBox(height: 26),
          _SettingsTabs(selected: 'Account'),
          SizedBox(height: 34),
          _SettingsAccountTitle(),
          SizedBox(height: 22),
          _ProfileSummaryCard(),
          SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _PlanCard()),
              SizedBox(width: 20),
              Expanded(child: _BillingCard()),
            ],
          ),
          SizedBox(height: 20),
          _SecurityCard(),
          SizedBox(height: 20),
          _DataCard(),
        ],
      ),
    );
  }
}

final class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text('Settings',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
        ),
        const _Glyph('L', color: Color(0xFF485777)),
        const SizedBox(width: 12),
        Text('All data is private to you.', style: _mutedBold(16)),
      ],
    );
  }
}

final class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({required this.selected});

  final String selected;

  static const _tabs = [
    'Account',
    'Connection',
    'Permissions',
    'Memory',
    'Activity'
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
              width: tab == 'Permissions' ? 152 : 124,
              child: _MemoryTab(label: tab, selected: tab == selected),
            ),
        ],
      ),
    );
  }
}

final class _SettingsAccountTitle extends StatelessWidget {
  const _SettingsAccountTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Account',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        SizedBox(height: 10),
        Text(
          'Plan, profile, billing, and security.',
          style: TextStyle(
              color: AgentHomeStoryboard.muted,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

final class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: _box(radius: 9),
      child: const Row(
        children: [
          _Avatar(label: 'AL', color: Color(0xFF22304E), size: 74),
          SizedBox(width: 22),
          Expanded(
            child: Text(
              'Ada Lin\nada.lin@example.com\nJoined May 12, 2025',
              style: TextStyle(
                  fontSize: 16, height: 1.55, fontWeight: FontWeight.w800),
            ),
          ),
          _Chip('You', tone: _Tone.blue),
          SizedBox(width: 36),
          SizedBox(width: 160, child: _SmallButton('Edit profile')),
        ],
      ),
    );
  }
}

final class _PlanCard extends StatelessWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 226,
      padding: const EdgeInsets.all(20),
      decoration: _box(radius: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your plan',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              decoration: _box(radius: 8, color: const Color(0xFFFBFCFE)),
              child: const Row(
                children: [
                  SizedBox(width: 18),
                  _PlanIcon(),
                  SizedBox(width: 22),
                  Expanded(
                    child: Text(
                      'Pro Plan\nFor personal productivity with advanced research and automation.\nManage plan',
                      style: TextStyle(
                          fontSize: 16,
                          height: 1.55,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  _VLine(height: 150),
                  SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      '+  Advanced research\n+  Long-term memory\n+  Priority support\n+  Extended history',
                      style: TextStyle(
                          color: Color(0xFF1BA86C),
                          fontSize: 14,
                          height: 1.65,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(width: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _PlanIcon extends StatelessWidget {
  const _PlanIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AgentHomeStoryboard.blue,
        shape: BoxShape.circle,
      ),
      child: const Text('P',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
    );
  }
}

final class _BillingCard extends StatelessWidget {
  const _BillingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 226,
      padding: const EdgeInsets.all(22),
      decoration: _box(radius: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Billing',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          const Text(r'$12.00 / month',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('Next billing date: Jun 12, 2025',
                    style: _mutedBold(14)),
              ),
              const _Chip('Active', tone: _Tone.green),
            ],
          ),
          const Spacer(),
          const _SmallButton('Manage billing'),
        ],
      ),
    );
  }
}

final class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 246,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: _box(radius: 9),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email & account security',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          _SettingsInfoRow(
            icon: 'E',
            title: 'Email address',
            body: 'ada.lin@example.com',
            status: 'Verified',
            action: 'Change email',
          ),
          _SettingsInfoRow(
            icon: 'L',
            title: 'Password',
            body: 'Last changed May 10, 2025',
            action: 'Change password',
          ),
          _SettingsInfoRow(
            icon: 'S',
            title: 'Two-factor authentication',
            body: 'Adds extra protection to your account',
            status: 'On',
            action: 'Manage 2FA',
          ),
        ],
      ),
    );
  }
}

final class _DataCard extends StatelessWidget {
  const _DataCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: _box(radius: 9),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          _SettingsInfoRow(
            icon: 'D',
            title: 'Export your data',
            body: 'Download a copy of your data, memory, and files.',
            action: 'Export data',
          ),
          _SettingsInfoRow(
            icon: 'X',
            title: 'Delete account',
            body: 'Permanently delete your account and all associated data.',
            action: 'Delete account',
            danger: true,
          ),
        ],
      ),
    );
  }
}

final class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    this.status,
    this.danger = false,
  });

  final String icon;
  final String title;
  final String body;
  final String action;
  final String? status;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          _Glyph(icon,
              color:
                  danger ? const Color(0xFFFF2E2E) : const Color(0xFF485777)),
          const SizedBox(width: 22),
          Expanded(
            child: Text(
              '$title\n$body',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: danger
                      ? const Color(0xFFFF2E2E)
                      : AgentHomeStoryboard.ink,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w800),
            ),
          ),
          if (status != null) ...[
            _Chip(status!, tone: _Tone.green),
            const SizedBox(width: 30),
          ],
          SizedBox(
            width: 200,
            child: _SmallButton(action, danger: danger),
          ),
        ],
      ),
    );
  }
}

final class _SettingsAccountPhoneFrame extends StatelessWidget {
  const _SettingsAccountPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_account_mobile_mock'),
      width: 470,
      height: 1128,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _SettingsAccountMobileCanvas(),
      ),
    );
  }
}

final class _SettingsAccountMobileCanvas extends StatelessWidget {
  const _SettingsAccountMobileCanvas();

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
            _SettingsMobileTabs(),
            SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsMobileProfile(),
                    SizedBox(height: 18),
                    _SettingsMobilePlan(),
                    SizedBox(height: 18),
                    _SettingsMobileSecurity(),
                    SizedBox(height: 18),
                    _SettingsMobileData(),
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

final class _SettingsMobileHeader extends StatelessWidget {
  const _SettingsMobileHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('=', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Expanded(
          child: Text('Settings',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ),
        _Glyph('P', color: Color(0xFF485777)),
      ],
    );
  }
}

final class _SettingsMobileTabs extends StatelessWidget {
  const _SettingsMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _SettingsMobileTab('Account', selected: true)),
          Expanded(child: _SettingsMobileTab('Connection')),
          Expanded(child: _SettingsMobileTab('Permissions')),
          Expanded(child: _SettingsMobileTab('Memory')),
          Expanded(child: _SettingsMobileTab('Activity')),
        ],
      ),
    );
  }
}

final class _SettingsMobileTab extends StatelessWidget {
  const _SettingsMobileTab(this.label, {this.selected = false});

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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

final class _SettingsMobileProfile extends StatelessWidget {
  const _SettingsMobileProfile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(radius: 9),
      child: const Row(
        children: [
          _Avatar(label: 'AL', color: Color(0xFF22304E), size: 66),
          SizedBox(width: 16),
          Expanded(
            child: Text('Ada Lin\nada.lin@example.com\nJoined May 12, 2025',
                style: TextStyle(
                    fontSize: 14, height: 1.5, fontWeight: FontWeight.w800)),
          ),
          Text('>',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _SettingsMobilePlan extends StatelessWidget {
  const _SettingsMobilePlan();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(radius: 9),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your plan',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          SizedBox(height: 16),
          Row(
            children: [
              _PlanIcon(),
              SizedBox(width: 18),
              Expanded(
                child: Text(
                    'Pro Plan\nNext billing date: Jun 12, 2025\nManage plan',
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w800)),
              ),
              Text(r'$12.00 / month',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
          SizedBox(height: 14),
          _SmallButton('Manage billing'),
        ],
      ),
    );
  }
}

final class _SettingsMobileSecurity extends StatelessWidget {
  const _SettingsMobileSecurity();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: _box(radius: 9),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email & account security',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          _SettingsMobileRow('Email address', 'Verified'),
          _SettingsMobileRow('Password', ''),
          _SettingsMobileRow('Two-factor authentication', 'On'),
        ],
      ),
    );
  }
}

final class _SettingsMobileData extends StatelessWidget {
  const _SettingsMobileData();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: _box(radius: 9),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your data',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          _SettingsMobileRow('Export your data', ''),
          _SettingsMobileRow('Delete account', '', danger: true),
        ],
      ),
    );
  }
}

final class _SettingsMobileRow extends StatelessWidget {
  const _SettingsMobileRow(this.title, this.status, {this.danger = false});

  final String title;
  final String status;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: danger
                        ? const Color(0xFFFF2E2E)
                        : AgentHomeStoryboard.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ),
          if (status.isNotEmpty) _Chip(status, tone: _Tone.green),
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

final class _SettingsBottomNav extends StatelessWidget {
  const _SettingsBottomNav();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 54,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BottomNavItem('Conversation', 'C'),
          _BottomNavItem('Memory', 'M'),
          _BottomNavItem('Review', 'R', badge: '2'),
          _BottomNavItem('Settings', 'S', selected: true),
        ],
      ),
    );
  }
}

final class _SettingsAccountNotesStrip extends StatelessWidget {
  const _SettingsAccountNotesStrip();

  static const _notes = [
    (
      title: 'Account is profile and plan.',
      body: 'Update your profile and manage your subscription.',
    ),
    (
      title: 'Billing stays separate from runtime.',
      body: 'Plan and payments are managed independently.',
    ),
    (
      title: 'Security lives with account.',
      body: 'Email, password, and 2FA keep your account protected.',
    ),
    (
      title: 'No permissions list here.',
      body: 'Allowed actions are managed in the Permissions tab.',
    ),
    (
      title: 'No activity timeline here.',
      body: 'History and transparency are in the Activity tab.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_settings_account_interaction_notes'),
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
