import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/chat/audio_recording_recovery_snapshot.dart';
import 'package:secondloop/features/chat/audio_recording_recovery_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('tracks active/completed segment paths in order', () async {
    await AudioRecordingRecoveryStore.beginSession(
      sessionId: 'session-1',
      startedAtMs: 1000,
      conversationId: 'loop_home',
      createdAtMs: 2000,
    );
    await AudioRecordingRecoveryStore.markActiveSegment(
      sessionId: 'session-1',
      path: '/tmp/a.m4a',
    );
    await AudioRecordingRecoveryStore.markSegmentCompleted(
      sessionId: 'session-1',
      path: '/tmp/a.m4a',
    );
    await AudioRecordingRecoveryStore.markActiveSegment(
      sessionId: 'session-1',
      path: '/tmp/b.m4a',
    );

    final snapshot = await AudioRecordingRecoveryStore.loadSnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.completedSegmentPaths, <String>['/tmp/a.m4a']);
    expect(snapshot.activeSegmentPath, '/tmp/b.m4a');
    expect(
        snapshot.recoverableSegmentPaths, <String>['/tmp/a.m4a', '/tmp/b.m4a']);
  });

  test('returns null for stale recoverable session', () async {
    await AudioRecordingRecoveryStore.beginSession(
      sessionId: 'session-stale',
      startedAtMs: DateTime.utc(2026, 2, 1).millisecondsSinceEpoch,
      conversationId: 'loop_home',
      createdAtMs: DateTime.utc(2026, 2, 1).millisecondsSinceEpoch,
    );
    await AudioRecordingRecoveryStore.markActiveSegment(
      sessionId: 'session-stale',
      path: '/tmp/stale.m4a',
    );

    final recoverable =
        await AudioRecordingRecoveryStore.loadRecoverableSession(
      now: DateTime.utc(2026, 2, 3),
    );
    expect(recoverable, isNull);
  });

  test('does not clear when expected session id mismatches', () async {
    await AudioRecordingRecoveryStore.beginSession(
      sessionId: 'session-keep',
      startedAtMs: 1000,
      conversationId: 'loop_home',
      createdAtMs: 2000,
    );
    await AudioRecordingRecoveryStore.clearSession(
      expectedSessionId: 'session-other',
    );

    final snapshot = await AudioRecordingRecoveryStore.loadSnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.sessionId, 'session-keep');
  });

  test('loads valid recoverable session within age window', () async {
    final now = DateTime.utc(2026, 2, 24, 12);
    await AudioRecordingRecoveryStore.beginSession(
      sessionId: 'session-valid',
      startedAtMs:
          now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
      conversationId: 'chat_1',
      createdAtMs:
          now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
    );
    await AudioRecordingRecoveryStore.markActiveSegment(
      sessionId: 'session-valid',
      path: '/tmp/valid.m4a',
    );

    final recoverable =
        await AudioRecordingRecoveryStore.loadRecoverableSession(
      now: now,
    );
    expect(recoverable, isA<RecordedAudioRecoverySnapshot>());
    expect(recoverable!.sessionId, 'session-valid');
  });
}
