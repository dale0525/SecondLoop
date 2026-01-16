import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  testWidgets('Push persists WebDAV config for auto sync', (WidgetTester tester) async {
    final storage = _InMemorySecureStorage({});
    final store = SyncConfigStore(storage: storage);
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    await tester.pumpWidget(
      AppBackendScope(
        backend: _FakeBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: MaterialApp(
            home: SyncSettingsPage(configStore: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Base URL',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.baseUrl, 'https://example.com/dav');
    expect(configured.remoteRoot, 'SecondLoop');
  });

  testWidgets('Save persists WebDAV config for auto sync', (WidgetTester tester) async {
    final storage = _InMemorySecureStorage({});
    final store = SyncConfigStore(storage: storage);
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    await tester.pumpWidget(
      AppBackendScope(
        backend: _FakeBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: MaterialApp(
            home: SyncSettingsPage(configStore: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Base URL',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.baseUrl, 'https://example.com/dav');
    expect(configured.remoteRoot, 'SecondLoop');
  });

  testWidgets('Push awaits backend so UI stays busy', (WidgetTester tester) async {
    final storage = _InMemorySecureStorage({});
    final store = SyncConfigStore(storage: storage);
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    final pushCompleter = Completer<int>();
    final backend = _FakeBackend(webdavPushCompleter: pushCompleter);

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: MaterialApp(
            home: SyncSettingsPage(configStore: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Base URL',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pump();

    final pushButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Push'),
    );
    expect(pushButton.onPressed, isNull);

    pushCompleter.complete(0);
    await tester.pumpAndSettle();

    final pushButtonAfter = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Push'),
    );
    expect(pushButtonAfter.onPressed, isNotNull);
  });
}

final class _InMemorySecureStorage extends FlutterSecureStorage {
  _InMemorySecureStorage(this._values);

  final Map<String, String> _values;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _values[key];
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map<String, String>.from(_values);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }
}

class _FakeBackend implements AppBackend {
  _FakeBackend({this.webdavPushCompleter});

  final Completer<int>? webdavPushCompleter;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async => const [];

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async =>
      createConversation(key, 'Main Stream');

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async =>
      Conversation(
        id: 'c1',
        title: title,
        createdAtMs: 0,
        updatedAtMs: 0,
      );

  @override
  Future<List<Message>> listMessages(Uint8List key, String conversationId) async =>
      const [];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async =>
      Message(
        id: 'm1',
        conversationId: conversationId,
        role: role,
        content: content,
        createdAtMs: 0,
      );

  @override
  Future<void> editMessage(Uint8List key, String messageId, String content) async {}

  @override
  Future<void> setMessageDeleted(Uint8List key, String messageId, bool isDeleted) async {}

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key, {int limit = 32}) async => 0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(Uint8List key, String query, {int topK = 10}) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key, {int batchLimit = 256}) async => 0;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async => const <LlmProfile>[];

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {}

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      const Stream<String>.empty();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    final completer = webdavPushCompleter;
    if (completer != null) return completer.future;
    return 0;
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<void> syncLocaldirTestConnection({required String localDir, required String remoteRoot}) async {}

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;
}
