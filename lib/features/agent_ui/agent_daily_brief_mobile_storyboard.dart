part of 'agent_home_storyboard.dart';

final class _DailyBriefPhoneFrame extends StatelessWidget {
  const _DailyBriefPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_daily_brief_mobile_mock'),
      width: 430,
      height: 1115,
      decoration: _box(
        radius: 58,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(52),
        child: const _DailyBriefMobileCanvas(),
      ),
    );
  }
}

final class _DailyBriefMobileCanvas extends StatelessWidget {
  const _DailyBriefMobileCanvas();

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
            Expanded(child: _DailyBriefMobileBody()),
            _DailyBriefMobileComposer(),
            SizedBox(height: 12),
            _DailyBriefMobileNav(),
          ],
        ),
      ),
    );
  }
}

final class _DailyBriefMobileBody extends StatelessWidget {
  const _DailyBriefMobileBody();

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
            text: 'What should I focus on today?',
          ),
          SizedBox(height: 18),
          _DailyBriefMobileAssistant(),
          SizedBox(height: 18),
          _MobileMessage(
            author: 'You',
            time: '09:05',
            avatar: _Avatar(
              label: 'AL',
              color: AgentHomeStoryboard.blue,
              size: 32,
            ),
            text: "Remind me before my child's birthday.",
          ),
          SizedBox(height: 16),
          _MobileMessage(
            author: 'SecondLoop',
            time: '09:05',
            avatar: _LoopAvatar(size: 32),
            text: "Sure. What date is your child's birthday?",
          ),
          SizedBox(height: 16),
          _MobileMessage(
            author: 'You',
            time: '09:06',
            avatar: _Avatar(
              label: 'AL',
              color: AgentHomeStoryboard.blue,
              size: 32,
            ),
            text: 'June 20.',
          ),
          SizedBox(height: 16),
          _DailyBriefMobileCandidateReply(),
        ],
      ),
    );
  }
}

final class _DailyBriefMobileAssistant extends StatelessWidget {
  const _DailyBriefMobileAssistant();

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
                "Good morning. Here's your daily brief.",
                style: TextStyle(
                    fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              _DailyBriefMobileCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _DailyBriefMobileCard extends StatelessWidget {
  const _DailyBriefMobileCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Top priorities',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                _DailyMobilePriority('1', 'Finish weekly report', 'High'),
                _DailyMobilePriority('2', 'Prepare Q2 budget report', 'High'),
                _DailyMobilePriority('3', 'Client product demo prep', 'Medium'),
              ],
            ),
          ),
          Divider(height: 1, color: AgentHomeStoryboard.line),
          SizedBox(
            height: 118,
            child: Row(
              children: [
                Expanded(
                    child: _DailyMobileMiniPanel(
                        title: 'Calendar windows',
                        count: '2',
                        body: '09:00 - 10:00    Free\n14:00 - 15:00    Focus')),
                _VLine(),
                Expanded(
                    child: _DailyMobileMiniPanel(
                        title: 'Reminders', count: '3', body: '3 scheduled')),
              ],
            ),
          ),
          Divider(height: 1, color: AgentHomeStoryboard.line),
          SizedBox(
            height: 86,
            child: Row(
              children: [
                Expanded(
                    child: _DailyMobileMiniPanel(
                        title: 'Commitments owed',
                        count: '2',
                        body: 'Follow-ups due today')),
                _VLine(),
                Expanded(
                    child: _DailyMobileMiniPanel(
                        title: 'Pending reviews',
                        count: '3',
                        body: 'Open Review')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _DailyMobilePriority extends StatelessWidget {
  const _DailyMobilePriority(this.number, this.text, this.chip);

  final String number;
  final String text;
  final String chip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(number,
                style: const TextStyle(
                    color: Color(0xFFFF2E2E),
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
          ),
          Expanded(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          _Chip(chip, tone: chip == 'Medium' ? _Tone.orange : _Tone.red),
        ],
      ),
    );
  }
}

final class _DailyMobileMiniPanel extends StatelessWidget {
  const _DailyMobileMiniPanel({
    required this.title,
    required this.count,
    required this.body,
  });

  final String title;
  final String count;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900)),
              ),
              Text(count, style: _mutedBold(11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, height: 1.45, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

final class _DailyBriefMobileCandidateReply extends StatelessWidget {
  const _DailyBriefMobileCandidateReply();

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
                'I prepared two items for Review before enabling them.',
                style: TextStyle(
                    fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              _DailyBriefMobileCandidateCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _DailyBriefMobileCandidateCard extends StatelessWidget {
  const _DailyBriefMobileCandidateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      padding: const EdgeInsets.all(14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Needs confirmation (2)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          _DailyMobileCandidateLine('M', 'Memory candidate: child birthday'),
          Divider(height: 20, color: AgentHomeStoryboard.line),
          _DailyMobileCandidateLine(
              'R', 'Recurring reminder candidate: buy gift before birthday'),
        ],
      ),
    );
  }
}

final class _DailyMobileCandidateLine extends StatelessWidget {
  const _DailyMobileCandidateLine(this.glyph, this.title);

  final String glyph;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Glyph(glyph, color: const Color(0xFFFF8A00)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, height: 1.35, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

final class _DailyBriefMobileComposer extends StatelessWidget {
  const _DailyBriefMobileComposer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 42,
      child: Row(
        children: [
          _Glyph('@', color: AgentHomeStoryboard.muted),
          SizedBox(width: 10),
          _Glyph('M', color: AgentHomeStoryboard.muted),
          SizedBox(width: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFF8FAFD),
                borderRadius: BorderRadius.all(Radius.circular(10)),
                border: Border.fromBorderSide(
                  BorderSide(color: AgentHomeStoryboard.line),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  'Ask, capture, search...',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Color(0xFF8490A7),
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
          _MobileSendButton(),
        ],
      ),
    );
  }
}

final class _MobileSendButton extends StatelessWidget {
  const _MobileSendButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AgentHomeStoryboard.blue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('>',
          style: TextStyle(
              color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
    );
  }
}

final class _DailyBriefMobileNav extends StatelessWidget {
  const _DailyBriefMobileNav();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(child: _DailyMobileNavItem('C', 'Conversation', true)),
          Expanded(child: _DailyMobileNavItem('M', 'Memory', false)),
          Expanded(
              child: _DailyMobileNavItem('R', 'Review', false, badge: '3')),
          Expanded(child: _DailyMobileNavItem('S', 'Settings', false)),
        ],
      ),
    );
  }
}

final class _DailyMobileNavItem extends StatelessWidget {
  const _DailyMobileNavItem(
    this.glyph,
    this.label,
    this.selected, {
    this.badge = '',
  });

  final String glyph;
  final String label;
  final bool selected;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _Glyph(glyph,
                color: selected
                    ? AgentHomeStoryboard.blue
                    : AgentHomeStoryboard.muted),
            if (badge.isNotEmpty)
              const Positioned(
                right: -8,
                top: -7,
                child: _Badge('3'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
