import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/main.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  testWidgets(
      'app lock enabled -> requires unlock even if saved session key exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': true,
    });

    final backend = _SavedKeyBackend();

    await tester.pumpWidget(MyApp(backend: backend));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unlock_password')), findsOneWidget);
  });

  testWidgets('setup required flag -> requires master password setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': false,
      'master_password_setup_required_v1': true,
    });

    final backend = _SavedKeyBackend(masterPasswordSet: false);

    await tester.pumpWidget(MyApp(backend: backend));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('setup_password')), findsOneWidget);
  });
}

final class _SavedKeyBackend extends AppBackend {
  _SavedKeyBackend({this.masterPasswordSet = true});

  final bool masterPasswordSet;
  final Uint8List _savedKey = Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => masterPasswordSet;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async =>
      Uint8List.fromList(_savedKey);

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
