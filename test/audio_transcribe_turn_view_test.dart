import 'dart:collection';

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

  test('hard gap still starts a new turn even when next fragment is short', () {
    final view = buildAudioTranscriptTurnView(
      const <AudioTranscriptTurnSourceSegment>[
        AudioTranscriptTurnSourceSegment(tMs: 0, text: 'we start here'),
        AudioTranscriptTurnSourceSegment(tMs: 5000, text: 'yeah'),
        AudioTranscriptTurnSourceSegment(tMs: 6000, text: 'next topic'),
      ],
    );

    expect(view.status, AudioTranscriptTurnViewStatus.ok);
    expect(view.turns, hasLength(2));
    expect(view.turns.first.text, 'we start here');
    expect(view.turns.last.text, 'yeah next topic');
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

  test('formats both timestamps with hours across hour boundary', () {
    const view = AudioTranscriptTurnView(
      builderVersion: kAudioTranscriptTurnViewBuilderVersion,
      status: AudioTranscriptTurnViewStatus.ok,
      turns: <AudioTranscriptTurn>[
        AudioTranscriptTurn(
          startMs: 3599000,
          endMs: 3601000,
          text: 'crossing boundary',
          segmentCount: 1,
          sourceSegmentStartIndex: 0,
          sourceSegmentEndIndex: 0,
        ),
      ],
      params: <String, Object?>{},
    );

    final full = formatAudioTranscriptTurnViewFull(view);

    expect(full, '[0:59:59–1:00:01] crossing boundary');
  });

  test('fromJson reads builder version only once', () {
    final raw = _BuilderVersionReadTrackingMap(
      <String, Object?>{
        'status': 'ok',
        'turns': const <Object?>[],
        'params': const <String, Object?>{},
      },
    );

    final view = AudioTranscriptTurnView.fromJson(raw);

    expect(view, isNotNull);
    expect(view!.builderVersion, 'custom_v2');
    expect(raw.builderVersionReadCount, 1);
  });

  test('excerpt truncates at a word boundary when possible', () {
    final view = buildAudioTranscriptTurnView(
      const <AudioTranscriptTurnSourceSegment>[
        AudioTranscriptTurnSourceSegment(
          tMs: 12000,
          text: 'hello everyone thanks for joining',
        ),
      ],
    );

    final excerpt = excerptAudioTranscriptTurnView(view, maxChars: 24);

    expect(excerpt, '[00:12–00:12] hello…');
  });
}

final class _BuilderVersionReadTrackingMap extends MapBase<String, Object?> {
  _BuilderVersionReadTrackingMap(this._values);

  final Map<String, Object?> _values;
  int builderVersionReadCount = 0;

  @override
  Object? operator [](Object? key) {
    if (key == 'builder_version') {
      builderVersionReadCount += 1;
      return builderVersionReadCount == 1 ? ' custom_v2 ' : '';
    }
    return _values[key];
  }

  @override
  void operator []=(String key, Object? value) {
    _values[key] = value;
  }

  @override
  void clear() {
    _values.clear();
  }

  @override
  Iterable<String> get keys =>
      _values.keys.followedBy(const ['builder_version']);

  @override
  Object? remove(Object? key) {
    if (key == 'builder_version') {
      return null;
    }
    return _values.remove(key);
  }
}
