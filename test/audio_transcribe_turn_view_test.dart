import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/audio_transcribe/audio_transcribe_turn_view.dart';

void main() {
  test('returns fallback_no_segments when input segments are empty', () {
    final view = buildAudioTranscriptTurnView(
        const <AudioTranscriptTurnSourceSegment>[]);

    expect(view.status, AudioTranscriptTurnViewStatus.fallbackNoSegments);
    expect(view.turns, isEmpty);
  });

  test('keeps small-gap continuation in the same turn', () {
    final view = buildAudioTranscriptTurnView(
      const <AudioTranscriptTurnSourceSegment>[
        AudioTranscriptTurnSourceSegment(tMs: 1000, text: 'hello everyone'),
        AudioTranscriptTurnSourceSegment(
            tMs: 1600, text: 'thanks for joining us today'),
      ],
    );

    expect(view.status, AudioTranscriptTurnViewStatus.ok);
    expect(view.turns, hasLength(1));
    expect(view.turns.first.text, 'hello everyone thanks for joining us today');
    expect(view.turns.first.startMs, 1000);
    expect(view.turns.first.endMs, 1600);
  });

  test('starts a new turn when the time gap is large', () {
    final view = buildAudioTranscriptTurnView(
      const <AudioTranscriptTurnSourceSegment>[
        AudioTranscriptTurnSourceSegment(tMs: 1000, text: 'first point'),
        AudioTranscriptTurnSourceSegment(tMs: 3200, text: 'second point'),
      ],
    );

    expect(view.status, AudioTranscriptTurnViewStatus.ok);
    expect(view.turns, hasLength(2));
    expect(view.turns.first.text, 'first point');
    expect(view.turns.last.text, 'second point');
  });

  test('does not break only because a chunk boundary is crossed', () {
    final view = buildAudioTranscriptTurnView(
      const <AudioTranscriptTurnSourceSegment>[
        AudioTranscriptTurnSourceSegment(
            tMs: 599500, text: 'and the next point is'),
        AudioTranscriptTurnSourceSegment(
            tMs: 600100, text: 'we should delay the launch'),
      ],
    );

    expect(view.status, AudioTranscriptTurnViewStatus.ok);
    expect(view.turns, hasLength(1));
    expect(
      view.turns.single.text,
      'and the next point is we should delay the launch',
    );
  });

  test('short fragment is absorbed into the nearby turn', () {
    final view = buildAudioTranscriptTurnView(
      const <AudioTranscriptTurnSourceSegment>[
        AudioTranscriptTurnSourceSegment(tMs: 1000, text: 'we can do it'),
        AudioTranscriptTurnSourceSegment(tMs: 1300, text: 'yeah'),
        AudioTranscriptTurnSourceSegment(tMs: 1600, text: 'before friday'),
      ],
    );

    expect(view.status, AudioTranscriptTurnViewStatus.ok);
    expect(view.turns, hasLength(1));
    expect(view.turns.single.text, 'we can do it yeah before friday');
  });

  test('formats turn view as timestamped display text', () {
    final view = buildAudioTranscriptTurnView(
      const <AudioTranscriptTurnSourceSegment>[
        AudioTranscriptTurnSourceSegment(tMs: 12000, text: 'hello everyone'),
        AudioTranscriptTurnSourceSegment(
            tMs: 12800, text: 'thanks for joining'),
        AudioTranscriptTurnSourceSegment(
            tMs: 40000, text: 'next topic starts here'),
      ],
    );

    final full = formatAudioTranscriptTurnViewFull(view);
    final excerpt = excerptAudioTranscriptTurnView(view, maxChars: 32);

    expect(full, contains('[00:12–00:12] hello everyone thanks for joining'));
    expect(full, contains('[00:40–00:40] next topic starts here'));
    expect(excerpt, isNotEmpty);
  });
}
