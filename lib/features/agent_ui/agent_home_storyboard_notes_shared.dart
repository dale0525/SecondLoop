part of 'agent_home_storyboard.dart';

final class _InteractionNotesStrip extends StatelessWidget {
  const _InteractionNotesStrip();

  static const _notes = [
    (
      title: 'One permanent conversation.',
      body: 'All requests and memory stay in one continuous conversation.',
    ),
    (
      title: 'Capture and search start as messages or attachments.',
      body:
          'Tell SecondLoop what you need or attach files; the assistant acts from the conversation.',
    ),
    (
      title: 'Assistant status is human-readable.',
      body:
          "You'll see Thinking, Needs your OK, or Done, not technical details.",
    ),
    (
      title: 'The right context rail is stable across scenarios.',
      body:
          'Your priorities, memory, people, files, and pending reviews stay in view.',
    ),
    (
      title: 'No technical identifiers are shown.',
      body: 'You never see run IDs, tool traces, or provider information.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_home_interaction_notes'),
      height: 220,
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(28, 24, 26, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 130,
            child: Text('Interaction Notes',
                style: TextStyle(
                    fontSize: 21, height: 1.25, fontWeight: FontWeight.w900)),
          ),
          const _NoteDivider(),
          for (var i = 0; i < _notes.length; i++) ...[
            Expanded(
              child: _NoteItem(
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

final class _NoteItem extends StatelessWidget {
  const _NoteItem({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NumberBubble(number),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, height: 1.25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Expanded(
                child: Text(body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _Composer extends StatelessWidget {
  const _Composer({required this.fullText});

  final bool fullText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 58,
            decoration: _box(radius: 10),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Text('@', style: _mutedBold(20)),
                const SizedBox(width: 20),
                Text('M', style: _mutedBold(19)),
                const SizedBox(width: 20),
                const _VLine(height: 30),
                const SizedBox(width: 22),
                Expanded(
                  child: Text(
                    fullText
                        ? 'Ask, capture, search, or attach a file...'
                        : 'Ask, capture, search...',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF8490A7),
                        fontSize: 17,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AgentHomeStoryboard.blue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('>',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

final class _Bubble extends StatelessWidget {
  const _Bubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

final class _Outcome extends StatelessWidget {
  const _Outcome(this.title, this.body, this.chip);

  final String title;
  final String body;
  final String chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(chip,
              style: const TextStyle(
                  color: Color(0xFF08A86B),
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

final class _ActionButton extends StatelessWidget {
  const _ActionButton(this.label, {this.primary = false, this.danger = false});

  final String label;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      alignment: Alignment.center,
      decoration: _box(
        radius: 5,
        color: primary ? AgentHomeStoryboard.blue : AgentHomeStoryboard.panel,
        border: danger
            ? const Color(0xFFFFB5B5)
            : primary
                ? AgentHomeStoryboard.blue
                : AgentHomeStoryboard.line,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: primary
              ? Colors.white
              : danger
                  ? const Color(0xFFFF2E2E)
                  : AgentHomeStoryboard.ink,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _Tone { green, orange, red, blue }

final class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.tone});

  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      _Tone.green => (
          bg: const Color(0xFFEAF9F2),
          fg: const Color(0xFF159364),
          bd: const Color(0xFFC8ECD9),
        ),
      _Tone.orange => (
          bg: const Color(0xFFFFF5E8),
          fg: const Color(0xFFFF7A00),
          bd: const Color(0xFFFFE0B8),
        ),
      _Tone.red => (
          bg: const Color(0xFFFFEFEF),
          fg: const Color(0xFFE43E3E),
          bd: const Color(0xFFFFCACA),
        ),
      _Tone.blue => (
          bg: const Color(0xFFEFF3FF),
          fg: AgentHomeStoryboard.blue,
          bd: const Color(0xFFDCE6FF),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: _box(radius: 6, color: colors.bg, border: colors.bd),
      child: Text(label,
          style: TextStyle(
              color: colors.fg, fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }
}

final class _Glyph extends StatelessWidget {
  const _Glyph(this.glyph, {this.color = AgentHomeStoryboard.muted});

  final String glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(glyph,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

final class _LoopAvatar extends StatelessWidget {
  const _LoopAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration:
          const BoxDecoration(color: Color(0xFF0B9B63), shape: BoxShape.circle),
      child: _LoopMark(size: size * 0.7, color: AgentHomeStoryboard.blue),
    );
  }
}

final class _LoopMark extends StatelessWidget {
  const _LoopMark({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LoopMarkPainter(color)),
    );
  }
}

final class _LoopMarkPainter extends CustomPainter {
  const _LoopMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.13
      ..color = color;
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.06,
        size.height * 0.28,
        size.width * 0.48,
        size.height * 0.44,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.46,
        size.height * 0.28,
        size.width * 0.48,
        size.height * 0.44,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LoopMarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

final class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    required this.color,
    required this.size,
  });

  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(label,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.32,
              fontWeight: FontWeight.w900)),
    );
  }
}

final class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 21,
      height: 21,
      alignment: Alignment.center,
      decoration:
          const BoxDecoration(color: Color(0xFFFF9500), shape: BoxShape.circle),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

final class _NumberBubble extends StatelessWidget {
  const _NumberBubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
          color: AgentHomeStoryboard.blue, shape: BoxShape.circle),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
    );
  }
}

final class _PresenceDot extends StatelessWidget {
  const _PresenceDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration:
          const BoxDecoration(color: Color(0xFF13A66B), shape: BoxShape.circle),
    );
  }
}

final class _Square extends StatelessWidget {
  const _Square({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF52627E), width: 1.6),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

final class _VLine extends StatelessWidget {
  const _VLine({this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      color: AgentHomeStoryboard.line,
    );
  }
}

final class _NoteDivider extends StatelessWidget {
  const _NoteDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 1,
        height: double.infinity,
        color: AgentHomeStoryboard.line,
      ),
    );
  }
}

BoxDecoration _box({
  required double radius,
  Color color = AgentHomeStoryboard.panel,
  Color border = AgentHomeStoryboard.line,
  double borderWidth = 1,
}) {
  return BoxDecoration(
    color: color,
    border: Border.all(color: border, width: borderWidth),
    borderRadius: BorderRadius.circular(radius),
  );
}

TextStyle _titleStyle(double size) {
  return TextStyle(fontSize: size, fontWeight: FontWeight.w900);
}

TextStyle _mutedBold(double size) {
  return TextStyle(
    color: AgentHomeStoryboard.muted,
    fontSize: size,
    fontWeight: FontWeight.w800,
  );
}
