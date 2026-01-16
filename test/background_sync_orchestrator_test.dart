import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/background_sync_orchestrator.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  final syncKey = Uint8List.fromList(List<int>.filled(32, 0));

  test('Auto disabled -> cancels background sync', () async {
    final scheduler = _FakeScheduler();
    final orchestrator = BackgroundSyncOrchestrator(
      readAutoEnabled: () async => false,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: syncKey,
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      hasSavedSessionKey: () async => true,
      scheduler: scheduler,
    );

    await orchestrator.refreshSchedule();

    expect(scheduler.cancelCalls, 1);
    expect(scheduler.scheduleCalls, 0);
  });

  test('Missing config -> cancels background sync', () async {
    final scheduler = _FakeScheduler();
    final orchestrator = BackgroundSyncOrchestrator(
      readAutoEnabled: () async => true,
      loadConfig: () async => null,
      hasSavedSessionKey: () async => true,
      scheduler: scheduler,
    );

    await orchestrator.refreshSchedule();

    expect(scheduler.cancelCalls, 1);
    expect(scheduler.scheduleCalls, 0);
  });

  test('Missing session key -> cancels background sync', () async {
    final scheduler = _FakeScheduler();
    final orchestrator = BackgroundSyncOrchestrator(
      readAutoEnabled: () async => true,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: syncKey,
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      hasSavedSessionKey: () async => false,
      scheduler: scheduler,
    );

    await orchestrator.refreshSchedule();

    expect(scheduler.cancelCalls, 1);
    expect(scheduler.scheduleCalls, 0);
  });

  test('Configured + session key -> schedules background sync', () async {
    final scheduler = _FakeScheduler();
    final orchestrator = BackgroundSyncOrchestrator(
      readAutoEnabled: () async => true,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: syncKey,
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      hasSavedSessionKey: () async => true,
      scheduler: scheduler,
    );

    await orchestrator.refreshSchedule();

    expect(scheduler.cancelCalls, 0);
    expect(scheduler.scheduleCalls, 1);
    expect(scheduler.lastFrequency, const Duration(minutes: 15));
  });
}

final class _FakeScheduler implements BackgroundSyncScheduler {
  int scheduleCalls = 0;
  int cancelCalls = 0;
  Duration? lastFrequency;

  @override
  Future<void> schedulePeriodicSync({required Duration frequency}) async {
    scheduleCalls += 1;
    lastFrequency = frequency;
  }

  @override
  Future<void> cancelPeriodicSync() async {
    cancelCalls += 1;
  }
}
