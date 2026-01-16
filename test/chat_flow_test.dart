import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/main.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  testWidgets('Setup -> main stream -> send message', (tester) async {
    final backend = MemoryBackend();

    await tester.pumpWidget(MyApp(backend: backend));
    await tester.pumpAndSettle();

    expect(find.text('Set master password'), findsOneWidget);

    await tester.enterText(find.byKey(MemoryBackend.kSetupPassword), 'pw');
    await tester.enterText(
        find.byKey(MemoryBackend.kSetupConfirmPassword), 'pw');
    await tester.tap(find.byKey(MemoryBackend.kSetupContinue));
    await tester.pumpAndSettle();

    expect(find.text('Main Stream'), findsWidgets);

    await tester.enterText(find.byKey(MemoryBackend.kChatInput), 'hello');
    await tester.tap(find.byKey(MemoryBackend.kChatSend));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('Ask AI -> Stop should return to idle even if cancel hangs',
      (tester) async {
    final backend = StuckCancelBackend();

    await tester.pumpWidget(MyApp(backend: backend));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(MemoryBackend.kSetupPassword), 'pw');
    await tester.enterText(
        find.byKey(MemoryBackend.kSetupConfirmPassword), 'pw');
    await tester.tap(find.byKey(MemoryBackend.kSetupContinue));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(MemoryBackend.kChatInput), 'hello');
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_stop')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_stop')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('chat_ask_ai')), findsOneWidget);
    expect(find.text('Stopping…'), findsNothing);
  });
}

class MemoryBackend implements AppBackend {
  static const kSetupPassword = ValueKey('setup_password');
  static const kSetupConfirmPassword = ValueKey('setup_confirm_password');
  static const kSetupContinue = ValueKey('setup_continue');
  static const kChatInput = ValueKey('chat_input');
  static const kChatSend = ValueKey('chat_send');

  bool _masterPasswordSet = false;
  bool _autoUnlockEnabled = true;
  Uint8List? _savedKey;

  final List<Conversation> _conversations = [
    const Conversation(
      id: 'main_stream',
      title: 'Main Stream',
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
  ];
  final Map<String, List<Message>> _messages = {'main_stream': []};

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => _masterPasswordSet;

  @override
  Future<bool> readAutoUnlockEnabled() async => _autoUnlockEnabled;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {
    _autoUnlockEnabled = enabled;
    if (!enabled) _savedKey = null;
  }

  @override
  Future<Uint8List?> loadSavedSessionKey() async => _savedKey;

  @override
  Future<void> saveSessionKey(Uint8List key) async {
    _savedKey = Uint8List.fromList(key);
  }

  @override
  Future<void> clearSavedSessionKey() async {
    _savedKey = null;
  }

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async {
    _masterPasswordSet = true;
    return Uint8List.fromList(List<int>.filled(32, 1));
  }

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async =>
      List<Conversation>.from(_conversations);

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async =>
      _conversations.first;

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(
          Uint8List key, String conversationId) async =>
      List<Message>.from(_messages[conversationId] ?? const []);

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    final message = Message(
      id: 'm${(_messages[conversationId]?.length ?? 0) + 1}',
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: 0,
    );
    _messages.putIfAbsent(conversationId, () => []);
    _messages[conversationId]!.add(message);
    return message;
  }

  @override
  Future<void> editMessage(
      Uint8List key, String messageId, String content) async {
    for (final entry in _messages.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        final msg = list[i];
        if (msg.id != messageId) continue;
        list[i] = Message(
          id: msg.id,
          conversationId: msg.conversationId,
          role: msg.role,
          content: content,
          createdAtMs: msg.createdAtMs,
        );
        return;
      }
    }
  }

  @override
  Future<void> setMessageDeleted(
      Uint8List key, String messageId, bool isDeleted) async {
    for (final list in _messages.values) {
      list.removeWhere((msg) => msg.id == messageId);
    }
  }

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

class StuckCancelBackend extends MemoryBackend {
  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    final never = Completer<void>();
    final controller = StreamController<String>(
      onCancel: () => never.future,
    );
    return controller.stream;
  }
}
