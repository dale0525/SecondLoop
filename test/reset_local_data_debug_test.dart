import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'Debug reset clears local+remote synced data but preserves master password and local config',
      (tester) async {
    Future<void> pumpAndSettleShort() async {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );
    }

    SharedPreferences.setMockInitialValues({});
    final tempAppSupport =
        Directory.systemTemp.createTempSync('secondloop_appsupport_');
    final tempRemote =
        Directory.systemTemp.createTempSync('secondloop_remote_');
    addTearDown(() async {
      try {
        if (tempAppSupport.existsSync()) {
          tempAppSupport.deleteSync(recursive: true);
        }
      } catch (_) {}
      try {
        if (tempRemote.existsSync()) {
          tempRemote.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    PathProviderPlatform.instance =
        _FakePathProviderPlatform(applicationSupportPath: tempAppSupport.path);

    final authFile =
        File('${tempAppSupport.path}${Platform.pathSeparator}auth.json');
    authFile.createSync(recursive: true);
    authFile.writeAsStringSync('{"version":1}');

    final dbFile = File(
        '${tempAppSupport.path}${Platform.pathSeparator}secondloop.sqlite3');
    dbFile.createSync(recursive: true);
    dbFile.writeAsStringSync('sentinel-db');

    const remoteRoot = 'SecondLoopTest';
    final remoteData = File(
      '${tempRemote.path}${Platform.pathSeparator}$remoteRoot'
      '${Platform.pathSeparator}deviceA${Platform.pathSeparator}ops'
      '${Platform.pathSeparator}op_1.json',
    );
    remoteData.createSync(recursive: true);
    remoteData.writeAsStringSync('{"op_id":"1"}');

    final syncStore = SyncConfigStore();
    await syncStore.writeBackendType(SyncBackendType.localDir);
    await syncStore.writeAutoEnabled(true);
    await syncStore.writeLocalDir(tempRemote.path);
    await syncStore.writeRemoteRoot(remoteRoot);
    await syncStore.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _FakeBackend();
    var locked = false;

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () => locked = true,
          child: wrapWithI18n(
            const MaterialApp(
              home: Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      ),
    );
    await pumpAndSettleShort();

    await tester.runAsync(() async {
      await tester.scrollUntilVisible(
        find.text('Debug: Reset local data'),
        200,
      );
      await tester.tap(find.text('Debug: Reset local data'));
    });
    await pumpAndSettleShort();
    expect(find.text('Reset local data?'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Reset'));
    });
    await pumpAndSettleShort();

    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (!locked && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(locked, isTrue);
    expect(authFile.existsSync(), isTrue);
    expect(dbFile.existsSync(), isTrue);

    final remainingSyncConfig = await SyncConfigStore().readAll();
    expect(remainingSyncConfig[SyncConfigStore.kBackendType], isNotNull);
    expect(remainingSyncConfig[SyncConfigStore.kLocalDir], tempRemote.path);
    expect(remainingSyncConfig[SyncConfigStore.kRemoteRoot], remoteRoot);
    expect(remainingSyncConfig[SyncConfigStore.kSyncKeyB64], isNotNull);

    expect(
      Directory('${tempRemote.path}${Platform.pathSeparator}$remoteRoot')
          .existsSync(),
      isFalse,
    );
  });
}

final class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({required this.applicationSupportPath});

  final String applicationSupportPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}

final class _FakeBackend implements AppBackend {
  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async =>
      const <Conversation>[];

  @override
  Future<Conversation> createConversation(Uint8List key, String title) =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(Uint8List key, String conversationId) =>
      throw UnimplementedError();

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(Uint8List key, String messageId, String content) =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key,
          {int limit = 32}) =>
      throw UnimplementedError();

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
          Uint8List key, String query,
          {int topK = 10}) =>
      throw UnimplementedError();

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key, {int batchLimit = 256}) =>
      throw UnimplementedError();

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
      throw UnimplementedError();

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) =>
      throw UnimplementedError();

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      throw UnimplementedError();

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) =>
      throw UnimplementedError();

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> syncWebdavClearRemoteRoot({
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
  }) =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {
    final dir = Directory('$localDir${Platform.pathSeparator}$remoteRoot');
    if (!dir.existsSync()) return;
    dir.deleteSync(recursive: true);
  }

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) =>
      throw UnimplementedError();
}
