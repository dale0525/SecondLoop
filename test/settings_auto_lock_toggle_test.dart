import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Settings: toggling Auto lock persists and clears saved key',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': false,
    });

    final backend = _CountingBackend();

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Auto lock'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('app_lock_enabled_v1'), true);
    expect(backend.clearSavedSessionKeyCalls, 1);
  });

  testWidgets('Settings: enabling Auto lock without master password asks setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': false,
    });

    final backend = _CountingBackend(masterPasswordSet: false);
    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('app_lock_enabled_v1'), true);
    expect(prefs.getBool('master_password_setup_required_v1'), true);
    expect(backend.saveSessionKeyCalls, 0);
    expect(backend.clearSavedSessionKeyCalls, 0);
  });

  testWidgets('Settings: lock now without master password asks setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': false,
    });

    final backend = _CountingBackend(masterPasswordSet: false);
    var lockCalls = 0;

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () => lockCalls += 1,
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lock now'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('master_password_setup_required_v1'), true);
    expect(lockCalls, 1);
  });

  testWidgets('Settings: enabling biometrics persists session key',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': true,
      'biometric_unlock_enabled_v1': false,
    });

    final backend = _CountingBackend();

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Use biometrics'), findsOneWidget);

    await tester.tap(find.text('Use biometrics'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('biometric_unlock_enabled_v1'), true);
    expect(backend.saveSessionKeyCalls, 1);
    expect(backend.clearSavedSessionKeyCalls, 0);
  });

  testWidgets(
      'Settings (desktop): enabling Auto lock keeps saved key (default system unlock)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({
        'app_lock_enabled_v1': false,
      });

      final backend = _CountingBackend();

      await tester.pumpWidget(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              const MaterialApp(home: Scaffold(body: SettingsPage())),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_lock_enabled_v1'), true);
      expect(backend.saveSessionKeyCalls, 1);
      expect(backend.clearSavedSessionKeyCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

final class _CountingBackend extends AppBackend {
  _CountingBackend({this.masterPasswordSet = true});

  final bool masterPasswordSet;
  int saveSessionKeyCalls = 0;
  int clearSavedSessionKeyCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => masterPasswordSet;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

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
  Future<Uint8List> initMasterPassword(String password) =>
      throw UnimplementedError();

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
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) =>
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
  Stream<String> askAiStreamCloudGateway(Uint8List key, String conversationId,
          {required String question,
          int topK = 10,
          bool thisThreadOnly = false,
          required String gatewayBaseUrl,
          required String idToken,
          required String modelName}) =>
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
