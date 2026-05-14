part of 'agent_home_storyboard.dart';

final class _ResearchPhoneFrame extends StatelessWidget {
  const _ResearchPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_research_mobile_mock'),
      width: 430,
      height: 1115,
      decoration: _box(
        radius: 58,
        border: const Color(0xFF111827),
        borderWidth: 5,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(52),
        child: const _ResearchMobileCanvas(),
      ),
    );
  }
}

final class _ResearchMobileCanvas extends StatelessWidget {
  const _ResearchMobileCanvas();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AgentHomeStoryboard.panel,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 24, 22, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PhoneStatus(),
            SizedBox(height: 22),
            _MobileHeader(),
            Divider(height: 26, color: AgentHomeStoryboard.line),
            Expanded(child: _ResearchMobileBody()),
            _Composer(fullText: false),
            SizedBox(height: 12),
            _DailyBriefMobileNav(),
          ],
        ),
      ),
    );
  }
}

final class _ResearchMobileBody extends StatelessWidget {
  const _ResearchMobileBody();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          _MobileMessage(
            author: 'You',
            time: '09:01',
            avatar: _Avatar(
              label: 'AL',
              color: AgentHomeStoryboard.blue,
              size: 32,
            ),
            text: 'Research Hermes Agent and OpenClaw.',
          ),
          SizedBox(height: 16),
          _ResearchMobileConfirmation(),
          SizedBox(height: 16),
          _MobileMessage(
            author: 'You',
            time: '09:02',
            avatar: _Avatar(
              label: 'AL',
              color: AgentHomeStoryboard.blue,
              size: 32,
            ),
            text: 'Start.',
          ),
          SizedBox(height: 16),
          _ResearchMobileResultReply(),
        ],
      ),
    );
  }
}

final class _ResearchMobileConfirmation extends StatelessWidget {
  const _ResearchMobileConfirmation();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LoopAvatar(size: 32),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'SecondLoop', time: '09:01'),
              SizedBox(height: 8),
              Text(
                'This research needs confirmation before starting.',
                style: TextStyle(
                    fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              _ResearchMobileBudgetCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ResearchMobileBudgetCard extends StatelessWidget {
  const _ResearchMobileBudgetCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(
        radius: 10,
        color: const Color(0xFFFFFCF7),
        border: const Color(0xFFFFD59B),
      ),
      padding: const EdgeInsets.all(14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('High-cost research',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          SizedBox(height: 14),
          _ResearchMobileMetric('Search up to\n20 pages'),
          SizedBox(height: 8),
          _ResearchMobileMetric('Estimated tokens\n120K'),
          SizedBox(height: 8),
          _ResearchMobileMetric('Estimated cost\n\$1.24'),
          SizedBox(height: 14),
          _TinyActionButton('Start research', primary: true),
          SizedBox(height: 8),
          _TinyActionButton('Reduce scope'),
          SizedBox(height: 8),
          _TinyActionButton('Cancel'),
        ],
      ),
    );
  }
}

final class _ResearchMobileMetric extends StatelessWidget {
  const _ResearchMobileMetric(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 12, height: 1.35, fontWeight: FontWeight.w800),
    );
  }
}

final class _ResearchMobileResultReply extends StatelessWidget {
  const _ResearchMobileResultReply();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LoopAvatar(size: 32),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'SecondLoop', time: '09:06'),
              SizedBox(height: 8),
              Text(
                'Research is complete. Here is the summary.',
                style: TextStyle(
                    fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              _ResearchMobileResultCard(),
              SizedBox(height: 12),
              _ResearchMobileDraftSavedCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ResearchMobileResultCard extends StatelessWidget {
  const _ResearchMobileResultCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(child: _SettingsMobileTab('Brief', selected: true)),
                Expanded(child: _SettingsMobileTab('Key points')),
                Expanded(child: _SettingsMobileTab('Sources (5)')),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hermes Agent appears stronger for orchestration. OpenClaw is closer to editor and code workflow automation.',
                  style: TextStyle(
                      fontSize: 12, height: 1.45, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12),
                _ResearchBullet('Hermes Agent: long-running tasks.'),
                _ResearchBullet('OpenClaw: code workflow efficiency.'),
                _ResearchBullet('Choice depends on operating style.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ResearchMobileDraftSavedCard extends StatelessWidget {
  const _ResearchMobileDraftSavedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(
        radius: 10,
        color: const Color(0xFFF0FBF7),
        border: const Color(0xFFCFEFE2),
      ),
      padding: const EdgeInsets.all(14),
      child: const Row(
        children: [
          Expanded(
            child: Text(
              'Saved as draft note\nHermes Agent vs OpenClaw research',
              style: TextStyle(
                  fontSize: 12, height: 1.35, fontWeight: FontWeight.w900),
            ),
          ),
          SizedBox(width: 92, child: _TinyActionButton('Open draft')),
        ],
      ),
    );
  }
}
