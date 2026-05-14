part of 'agent_home_storyboard.dart';

final class AgentMemoryProjectsStoryboard extends StatelessWidget {
  const AgentMemoryProjectsStoryboard({super.key});

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
            child: _MemoryProjectsCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _MemoryProjectsCanvas extends StatelessWidget {
  const _MemoryProjectsCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1122,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MemoryProjectsWorkspace(),
                SizedBox(width: 28),
                _MemoryProjectsPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 20),
          _MemoryProjectsNotesStrip(),
        ],
      ),
    );
  }
}

final class _MemoryProjectsWorkspace extends StatelessWidget {
  const _MemoryProjectsWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_projects_workspace'),
      width: 1540,
      height: 1122,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _MemorySidebar(),
          _VLine(),
          Expanded(child: _MemoryProjectsDesktopBody()),
        ],
      ),
    );
  }
}

final class _MemoryProjectsDesktopBody extends StatelessWidget {
  const _MemoryProjectsDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(30, 30, 30, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoryHeader(),
          SizedBox(height: 26),
          _MemoryProjectsTabs(),
          SizedBox(height: 30),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 548, child: _ProjectsListPanel()),
                SizedBox(width: 20),
                Expanded(child: _ProjectDetailPanel()),
              ],
            ),
          ),
          SizedBox(height: 28),
          _ProjectPendingCandidate(),
        ],
      ),
    );
  }
}

final class _MemoryProjectsTabs extends StatelessWidget {
  const _MemoryProjectsTabs();

  static const _tabs = [
    (label: 'Preferences', selected: false),
    (label: 'People', selected: false),
    (label: 'Projects', selected: true),
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

final class _ProjectsListPanel extends StatelessWidget {
  const _ProjectsListPanel();

  static const _projects = [
    (
      title: 'Q2 Productivity Tools Research',
      body: 'Research tools to improve team productivity',
      updated: 'Updated May 20, 2025',
      color: Color(0xFF7C3AED),
      selected: false,
    ),
    (
      title: 'Client Demo Prep',
      body: 'Prepare deck and talking points for demo',
      updated: 'Updated May 18, 2025',
      color: Color(0xFF0B5CF6),
      selected: false,
    ),
    (
      title: 'Cloudflare Agent MVP',
      body: 'Build an internal proof of concept',
      updated: 'Updated May 19, 2025',
      color: Color(0xFF07895F),
      selected: true,
    ),
    (
      title: 'Budget Review',
      body: 'Review Q2 budget and variance',
      updated: 'Updated May 16, 2025',
      color: Color(0xFFFF8500),
      selected: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text('Projects',
                    style:
                        TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              ),
              Text('+',
                  style: TextStyle(
                      color: AgentHomeStoryboard.blue,
                      fontSize: 27,
                      fontWeight: FontWeight.w500)),
              SizedBox(width: 12),
              Text('Add project',
                  style: TextStyle(
                      color: AgentHomeStoryboard.blue,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 26),
          for (final project in _projects)
            _ProjectListRow(
              title: project.title,
              body: project.body,
              updated: project.updated,
              color: project.color,
              selected: project.selected,
            ),
          const Divider(color: AgentHomeStoryboard.line, height: 34),
          Text('4 projects', style: _mutedBold(14)),
        ],
      ),
    );
  }
}

final class _ProjectListRow extends StatelessWidget {
  const _ProjectListRow({
    required this.title,
    required this.body,
    required this.updated,
    required this.color,
    required this.selected,
  });

  final String title;
  final String body;
  final String updated;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 124,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _box(
        radius: 7,
        color: selected ? const Color(0xFFFBFFFD) : AgentHomeStoryboard.panel,
        border: selected ? const Color(0xFF70D7B0) : AgentHomeStoryboard.line,
        borderWidth: selected ? 1.5 : 0,
      ),
      child: Row(
        children: [
          _ProjectIcon(color: color),
          const SizedBox(width: 20),
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
                const SizedBox(height: 10),
                Text(body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedBold(13)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Active',
                  style: TextStyle(
                      color: Color(0xFF0A915F), fontWeight: FontWeight.w900)),
              const SizedBox(height: 28),
              Text(updated, style: _mutedBold(13)),
            ],
          ),
          const SizedBox(width: 18),
          Text('...', style: _mutedBold(20)),
        ],
      ),
    );
  }
}

final class _ProjectDetailPanel extends StatelessWidget {
  const _ProjectDetailPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProjectDetailHeader(),
          SizedBox(height: 30),
          _ProjectSectionTitle('Objective'),
          SizedBox(height: 12),
          _ProjectTextBox(
            'Validate Cloudflare\'s agent platform for internal automation use cases.',
          ),
          SizedBox(height: 24),
          _ProjectSectionTitle('Active documents'),
          SizedBox(height: 12),
          _ProjectDocumentList(),
          SizedBox(height: 24),
          _ProjectSectionTitle('Current constraints'),
          SizedBox(height: 12),
          _ConstraintList(),
          SizedBox(height: 24),
          _ProjectSectionTitle('Latest summary'),
          SizedBox(height: 12),
          _ProjectTextBox(
            'Completed requirements v1.0 and drafted the initial architecture.\nNext: build a minimal agent that can fetch docs and summarize.',
          ),
          Spacer(),
          Row(
            children: [
              SizedBox(
                width: 238,
                child: _ProjectActionButton(
                  'Open in conversation',
                  primary: true,
                ),
              ),
              SizedBox(width: 20),
              Expanded(child: _ProjectActionButton('Edit memory')),
              SizedBox(width: 20),
              SizedBox(width: 148, child: _ProjectActionButton('Archive')),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ProjectDetailHeader extends StatelessWidget {
  const _ProjectDetailHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _ProjectIcon(color: Color(0xFF07895F)),
        SizedBox(width: 22),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cloudflare Agent MVP',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Text('Build an internal proof of concept',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        _Chip('Active', tone: _Tone.green),
      ],
    );
  }
}

final class _ProjectSectionTitle extends StatelessWidget {
  const _ProjectSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: _titleStyle(15));
  }
}

final class _ProjectTextBox extends StatelessWidget {
  const _ProjectTextBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _box(radius: 8, color: const Color(0xFFFBFCFE)),
      child: Text(
        text,
        style: _mutedBold(13),
      ),
    );
  }
}

final class _ProjectDocumentList extends StatelessWidget {
  const _ProjectDocumentList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 8),
      child: const Column(
        children: [
          _ProjectDocumentRow(
            icon: 'D',
            color: AgentHomeStoryboard.blue,
            title: 'Agent MVP Requirements.docx',
            updated: 'Updated May 19, 2025',
          ),
          _ProjectDocumentRow(
            icon: 'PDF',
            color: Color(0xFFFF3B30),
            title: 'Architecture Overview.pdf',
            updated: 'Updated May 17, 2025',
          ),
        ],
      ),
    );
  }
}

final class _ProjectDocumentRow extends StatelessWidget {
  const _ProjectDocumentRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.updated,
  });

  final String icon;
  final Color color;
  final String title;
  final String updated;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _Glyph(icon, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ),
          Text(updated, style: _mutedBold(13)),
        ],
      ),
    );
  }
}

final class _ConstraintList extends StatelessWidget {
  const _ConstraintList();

  @override
  Widget build(BuildContext context) {
    const items = [
      'No shell or OS-level automation',
      'Operate within Cloudflare Workers / Pages',
      'Keep costs within the free tier where possible',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('-  $item',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }
}

final class _ProjectActionButton extends StatelessWidget {
  const _ProjectActionButton(this.label, {this.primary = false});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: _box(
        radius: 7,
        color: primary ? AgentHomeStoryboard.blue : AgentHomeStoryboard.panel,
        border: primary ? AgentHomeStoryboard.blue : AgentHomeStoryboard.line,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: primary ? Colors.white : AgentHomeStoryboard.ink,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _ProjectPendingCandidate extends StatelessWidget {
  const _ProjectPendingCandidate();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pending project memory candidate (1)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          SizedBox(height: 14),
          _ProjectPendingBody(),
        ],
      ),
    );
  }
}

final class _ProjectPendingBody extends StatelessWidget {
  const _ProjectPendingBody();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 98,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _box(radius: 8),
      child: const Row(
        children: [
          _ProjectIcon(color: Color(0xFF815CFF), small: true),
          SizedBox(width: 22),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cloudflare Agent MVP excludes shell automation',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                Text('From your message  -  May 19, 2025',
                    style: TextStyle(
                        color: AgentHomeStoryboard.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text('Suggested because it may limit available actions.',
                    style: TextStyle(
                        color: AgentHomeStoryboard.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          SizedBox(width: 150, child: _SmallButton('Accept', success: true)),
          SizedBox(width: 18),
          SizedBox(width: 140, child: _SmallButton('Edit')),
          SizedBox(width: 18),
          SizedBox(width: 150, child: _SmallButton('Ignore')),
        ],
      ),
    );
  }
}

final class _MemoryProjectsPhoneFrame extends StatelessWidget {
  const _MemoryProjectsPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_projects_mobile_mock'),
      width: 470,
      height: 1122,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _MemoryProjectsMobileCanvas(),
      ),
    );
  }
}

final class _MemoryProjectsMobileCanvas extends StatelessWidget {
  const _MemoryProjectsMobileCanvas();

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
            _ProjectsMobileTabs(),
            SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProjectsMobileTitle(),
                    SizedBox(height: 12),
                    _ProjectsMobileList(),
                    SizedBox(height: 18),
                    _ProjectMobileDetailCard(),
                    SizedBox(height: 18),
                    _ProjectMobilePendingCard(),
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

final class _ProjectsMobileTabs extends StatelessWidget {
  const _ProjectsMobileTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _MemoryTab(label: 'Preferences', selected: false)),
          Expanded(child: _MemoryTab(label: 'People', selected: false)),
          Expanded(child: _MemoryTab(label: 'Projects', selected: true)),
          Expanded(child: _MemoryTab(label: 'More', selected: false)),
        ],
      ),
    );
  }
}

final class _ProjectsMobileTitle extends StatelessWidget {
  const _ProjectsMobileTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: Text('Projects',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        ),
        Text('+',
            style: TextStyle(
                color: AgentHomeStoryboard.blue,
                fontSize: 28,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

final class _ProjectsMobileList extends StatelessWidget {
  const _ProjectsMobileList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: const Column(
        children: [
          _ProjectMobileListRow(
            'Q2 Productivity Tools Research',
            'Research tools to improve team productivity',
            Color(0xFF7C3AED),
          ),
          _ProjectMobileListRow(
            'Client Demo Prep',
            'Prepare deck and talking points for demo',
            Color(0xFF0B5CF6),
          ),
          _ProjectMobileListRow(
            'Cloudflare Agent MVP',
            'Build an internal proof of concept',
            Color(0xFF07895F),
            selected: true,
          ),
          _ProjectMobileListRow(
            'Budget Review',
            'Review Q2 budget and variance',
            Color(0xFFFF8500),
          ),
        ],
      ),
    );
  }
}

final class _ProjectMobileListRow extends StatelessWidget {
  const _ProjectMobileListRow(
    this.title,
    this.body,
    this.color, {
    this.selected = false,
  });

  final String title;
  final String body;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? const Color(0xFF70D7B0) : AgentHomeStoryboard.line,
          width: selected ? 1.4 : 0.8,
        ),
      ),
      child: Row(
        children: [
          _ProjectIcon(color: color, small: true),
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
                        fontSize: 13, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedBold(10)),
              ],
            ),
          ),
          const Text('Active',
              style: TextStyle(
                  color: Color(0xFF0A915F),
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _ProjectMobileDetailCard extends StatelessWidget {
  const _ProjectMobileDetailCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(radius: 9),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ProjectIcon(color: Color(0xFF07895F), small: true),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                    'Cloudflare Agent MVP\nBuild an internal proof of concept',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              ),
              _Chip('Active', tone: _Tone.green),
            ],
          ),
          SizedBox(height: 10),
          _ProjectSectionTitle('Objective'),
          SizedBox(height: 6),
          _ProjectTextBox(
            'Validate Cloudflare\'s agent platform for internal automation use cases.',
          ),
          SizedBox(height: 10),
          _ProjectSectionTitle('Active documents'),
          SizedBox(height: 6),
          _ProjectDocumentRow(
            icon: 'D',
            color: AgentHomeStoryboard.blue,
            title: 'Agent MVP Requirements.docx',
            updated: 'May 19',
          ),
          _ProjectDocumentRow(
            icon: 'PDF',
            color: Color(0xFFFF3B30),
            title: 'Architecture Overview.pdf',
            updated: 'May 17',
          ),
          SizedBox(height: 8),
          Text('View full details  >',
              style: TextStyle(
                  color: AgentHomeStoryboard.blue,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _ProjectMobilePendingCard extends StatelessWidget {
  const _ProjectMobilePendingCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pending project memory (1)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: _box(radius: 9),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ProjectIcon(color: Color(0xFF815CFF), small: true),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cloudflare Agent MVP excludes shell automation',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
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
        ),
      ],
    );
  }
}

final class _ProjectIcon extends StatelessWidget {
  const _ProjectIcon({required this.color, this.small = false});

  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 30.0 : 42.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'F',
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 16 : 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _MemoryProjectsNotesStrip extends StatelessWidget {
  const _MemoryProjectsNotesStrip();

  static const _notes = [
    (
      title: 'Projects hold reusable work context.',
      body:
          'Each project stores goals, constraints, and key updates for ongoing work.',
    ),
    (
      title: 'Each project has its own scope.',
      body: 'Context stays focused and does not bleed between projects.',
    ),
    (
      title: 'Drafts and files can be linked.',
      body: 'Attach docs and notes so the assistant has what it needs.',
    ),
    (
      title: 'New project facts need review.',
      body: 'Suggested insights wait for your approval before saving.',
    ),
    (
      title: 'No personal preference content here.',
      body: 'Projects are for work context only, not personal settings.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_projects_interaction_notes'),
      height: 216,
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
