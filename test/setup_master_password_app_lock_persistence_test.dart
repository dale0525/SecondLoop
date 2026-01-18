import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/features/lock/setup_master_password_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('setup: auto lock off -> persists session key', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': false,
    });

    final backend = _CountingBackend();

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: wrapWithI18n(
          const MaterialApp(
            home: SetupMasterPasswordPage(onUnlocked: _noop),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('setup_password')), 'pw');
    await tester.enterText(
        find.byKey(const ValueKey('setup_confirm_password')), 'pw');
    await tester.tap(find.byKey(const ValueKey('setup_continue')));
    await tester.pumpAndSettle();

    expect(backend.saveSessionKeyCalls, 1);
    expect(backend.clearSavedSessionKeyCalls, 0);
  });

  testWidgets('setup: auto lock on -> does not persist session key',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': true,
    });

    final backend = _CountingBackend();

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: wrapWithI18n(
          const MaterialApp(
            home: SetupMasterPasswordPage(onUnlocked: _noop),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('setup_password')), 'pw');
    await tester.enterText(
        find.byKey(const ValueKey('setup_confirm_password')), 'pw');
    await tester.tap(find.byKey(const ValueKey('setup_continue')));
    await tester.pumpAndSettle();

    expect(backend.saveSessionKeyCalls, 0);
    expect(backend.clearSavedSessionKeyCalls, 1);
  });

  testWidgets('setup: auto lock on + biometric on -> persists session key',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': true,
      'biometric_unlock_enabled_v1': true,
    });

    final backend = _CountingBackend();

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: wrapWithI18n(
          const MaterialApp(
            home: SetupMasterPasswordPage(onUnlocked: _noop),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('setup_password')), 'pw');
    await tester.enterText(
        find.byKey(const ValueKey('setup_confirm_password')), 'pw');
    await tester.tap(find.byKey(const ValueKey('setup_continue')));
    await tester.pumpAndSettle();

    expect(backend.saveSessionKeyCalls, 1);
    expect(backend.clearSavedSessionKeyCalls, 0);
  });

  testWidgets(
      'setup: desktop auto lock on (default system unlock) -> persists session key',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({
        'app_lock_enabled_v1': true,
      });

      final backend = _CountingBackend();

      await tester.pumpWidget(
        AppBackendScope(
          backend: backend,
          child: wrapWithI18n(
            const MaterialApp(
              home: SetupMasterPasswordPage(onUnlocked: _noop),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('setup_password')), 'pw');
      await tester.enterText(
          find.byKey(const ValueKey('setup_confirm_password')), 'pw');
      await tester.tap(find.byKey(const ValueKey('setup_continue')));
      await tester.pumpAndSettle();

      expect(backend.saveSessionKeyCalls, 1);
      expect(backend.clearSavedSessionKeyCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void _noop(Uint8List _) {}

final class _CountingBackend implements AppBackend {
  int saveSessionKeyCalls = 0;
  int clearSavedSessionKeyCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => false;

  @override
  Future<bool> readAutoUnlockEnabled() async => false;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {
    saveSessionKeyCalls += 1;
  }

  @override
  Future<void> clearSavedSessionKey() async {
    clearSavedSessionKeyCalls += 1;
  }

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) =>
      throw UnimplementedError();

  @override
  Future<List<Conversation>> listConversations(Uint8List key) =>
      throw UnimplementedError();

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
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) =>
      throw UnimplementedError();

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
  Stream<String> askAiStream(Uint8List key, String conversationId,
          {required String question,
          int topK = 10,
          bool thisThreadOnly = false}) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) =>
      throw UnimplementedError();

  @override
  Future<void> syncWebdavTestConnection(
          {required String baseUrl,
          String? username,
          String? password,
          required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<void> syncWebdavClearRemoteRoot(
          {required String baseUrl,
          String? username,
          String? password,
          required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPush(Uint8List key, Uint8List syncKey,
          {required String baseUrl,
          String? username,
          String? password,
          required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPull(Uint8List key, Uint8List syncKey,
          {required String baseUrl,
          String? username,
          String? password,
          required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirTestConnection(
          {required String localDir, required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirClearRemoteRoot(
          {required String localDir, required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPush(Uint8List key, Uint8List syncKey,
          {required String localDir, required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPull(Uint8List key, Uint8List syncKey,
          {required String localDir, required String remoteRoot}) =>
      throw UnimplementedError();
}
