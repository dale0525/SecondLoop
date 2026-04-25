part of 'sync_settings_page_test.dart';

void registerSyncSettingsPageCoreCTests() {
  testWidgets('Save restarts a stopped engine after the page unmounts',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final runner = _BlockingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: store.loadConfiguredSync,
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();
    engine.triggerPushNow();
    await runner.pushStarted.future;

    await tester.pumpWidget(_wrap(
      backend: _SyncSettingsBackend(),
      store: store,
      engine: engine,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder name',
      ),
      'SecondLoop2',
    );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge local and remote'));
    await tester.pump();

    expect(engine.isRunning, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    runner.completePush();
    await tester.pumpAndSettle();

    expect(engine.isRunning, isTrue);
    engine.stopImmediately();
  });
}

final class _BlockingSyncRunner implements SyncRunner {
  final Completer<void> pushStarted = Completer<void>();
  final Completer<void> _pushCompleter = Completer<void>();

  void completePush() {
    if (!_pushCompleter.isCompleted) {
      _pushCompleter.complete();
    }
  }

  @override
  Future<int> push(SyncConfig config) async {
    if (!pushStarted.isCompleted) {
      pushStarted.complete();
    }
    await _pushCompleter.future;
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async => 0;
}
