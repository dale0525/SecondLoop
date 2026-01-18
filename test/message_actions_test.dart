import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Long press message -> delete removes it', (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(_wrapChat(backend: backend));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_delete')));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsNothing);
    expect(backend.deletedMessageIds, contains('m1'));
  });

  testWidgets('Long press message -> edit updates content', (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(_wrapChat(backend: backend));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_edit')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('edit_message_content')), 'updated');
    await tester.tap(find.byKey(const ValueKey('edit_message_save')));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsNothing);
    expect(find.text('updated'), findsOneWidget);
    expect(backend.editedMessageIds, contains('m1'));
  });
}

Widget _wrapChat({required AppBackend backend}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: const ChatPage(
            conversation: Conversation(
              id: 'main_stream',
              title: 'Main Stream',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ),
        ),
      ),
    ),
  );
}

class MessageActionsBackend implements AppBackend {
  MessageActionsBackend({required List<Message> messages})
      : _messages = List<Message>.from(messages);

  final List<Message> _messages;

  final List<String> editedMessageIds = [];
  final List<String> deletedMessageIds = [];

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
  Future<List<Conversation>> listConversations(Uint8List key) async => const [];

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(
          Uint8List key, String conversationId) async =>
      List<Message>.from(_messages);

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(
      Uint8List key, String messageId, String content) async {
    editedMessageIds.add(messageId);
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].id == messageId) {
        _messages[i] = Message(
          id: _messages[i].id,
          conversationId: _messages[i].conversationId,
          role: _messages[i].role,
          content: content,
          createdAtMs: _messages[i].createdAtMs,
        );
        break;
      }
    }
  }

  @override
  Future<void> setMessageDeleted(
      Uint8List key, String messageId, bool isDeleted) async {
    deletedMessageIds.add(messageId);
    _messages.removeWhere((m) => m.id == messageId);
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async =>
      0;

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async =>
      const <String>['secondloop-default-embed-v0'];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async =>
      'secondloop-default-embed-v0';

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
      Future<bool>.value(modelName != 'secondloop-default-embed-v0');

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

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
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {}

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
  }) async =>
      0;

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
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {}

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
