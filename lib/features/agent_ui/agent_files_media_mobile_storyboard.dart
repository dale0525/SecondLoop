part of 'agent_home_storyboard.dart';

final class _FilesMediaPhoneFrame extends StatelessWidget {
  const _FilesMediaPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_files_media_mobile_mock'),
      width: 430,
      height: 1115,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _FilesMediaMobileCanvas(),
      ),
    );
  }
}

final class _FilesMediaMobileCanvas extends StatelessWidget {
  const _FilesMediaMobileCanvas();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AgentHomeStoryboard.panel,
      child: Stack(
        children: [
          Positioned.fill(child: _FilesMediaMobileBody()),
          Positioned(left: 0, right: 0, bottom: 0, child: _MobileSheet()),
        ],
      ),
    );
  }
}

final class _FilesMediaMobileBody extends StatelessWidget {
  const _FilesMediaMobileBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 24, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneStatus(),
          SizedBox(height: 22),
          _MobileHeader(),
          SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MobileFilesUserBlock(),
                  SizedBox(height: 20),
                  _MobileFilesAssistantBlock(),
                ],
              ),
            ),
          ),
          SizedBox(height: 250),
        ],
      ),
    );
  }
}

final class _MobileFilesUserBlock extends StatelessWidget {
  const _MobileFilesUserBlock();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 36),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'You', time: '09:20'),
              SizedBox(height: 8),
              Text(
                'Please summarize today\'s meeting audio, invoice, and passport scan, then extract details and suggested actions.',
                style: TextStyle(
                    fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MobileAttachmentTile(
                      glyph: 'A',
                      color: Color(0xFF8D57FF),
                      title: 'meeting_audio.mp3',
                      body: '45:12',
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _MobileAttachmentTile(
                      glyph: 'PDF',
                      color: Color(0xFFE82424),
                      title: 'invoice.pdf',
                      body: '3 pages',
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _MobileAttachmentTile(
                      glyph: 'IMG',
                      color: Color(0xFF0B9B63),
                      title: 'passport_scan.jpg',
                      body: '1 page',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _MobileAttachmentTile extends StatelessWidget {
  const _MobileAttachmentTile({
    required this.glyph,
    required this.color,
    required this.title,
    required this.body,
  });

  final String glyph;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.all(8),
      decoration: _box(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(glyph,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(body, style: _mutedBold(11)),
        ],
      ),
    );
  }
}

final class _MobileFilesAssistantBlock extends StatelessWidget {
  const _MobileFilesAssistantBlock();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LoopAvatar(size: 36),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'SecondLoop', time: '09:22'),
              SizedBox(height: 8),
              Text(
                "I processed your files. Here's a summary, key points, extracted details, and suggested actions.",
                style: TextStyle(
                    fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 16),
              _MobileSummaryCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _MobileSummaryCard extends StatelessWidget {
  const _MobileSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileFilesTabs(),
          Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meeting summary',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                Text(
                  'The meeting covered Q2 progress, launch timing, and market strategy. The team agreed to stay on schedule and focus on growth channels.',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 14),
                Divider(color: AgentHomeStoryboard.line),
                SizedBox(height: 10),
                Text('Decisions',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text(
                  '+  Q2 plan stays on track\n+  Campaign budget increases 15%\n+  Next review: Monday 10:00',
                  style: TextStyle(
                      fontSize: 12, height: 1.55, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12),
                Text('View all details',
                    style: TextStyle(
                        color: AgentHomeStoryboard.blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _MobileFilesTabs extends StatelessWidget {
  const _MobileFilesTabs();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: _SettingsMobileTab('Summary', selected: true)),
          Expanded(child: _SettingsMobileTab('Transcript')),
          Expanded(child: _SettingsMobileTab('Fields')),
          Expanded(child: _SettingsMobileTab('Actions')),
          Expanded(child: _SettingsMobileTab('Sources')),
        ],
      ),
    );
  }
}
