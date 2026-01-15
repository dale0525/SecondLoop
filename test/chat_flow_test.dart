import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/main.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  testWidgets('Setup -> open chat -> send message', (tester) async {
    final backend = MemoryBackend();

    await tester.pumpWidget(MyApp(backend: backend));
    await tester.pumpAndSettle();

    expect(find.text('Set master password'), findsOneWidget);

    await tester.enterText(find.byKey(MemoryBackend.kSetupPassword), 'pw');
    await tester.enterText(find.byKey(MemoryBackend.kSetupConfirmPassword), 'pw');
    await tester.tap(find.byKey(MemoryBackend.kSetupContinue));
    await tester.pumpAndSettle();

    expect(find.text('Inbox'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('conversation_c1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(MemoryBackend.kChatInput), 'hello');
    await tester.tap(find.byKey(MemoryBackend.kChatSend));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
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
    const Conversation(id: 'c1', title: 'Inbox', createdAtMs: 0, updatedAtMs: 0),
  ];
  final Map<String, List<Message>> _messages = {'c1': []};

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
  Future<Conversation> createConversation(Uint8List key, String title) async =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(Uint8List key, String conversationId) async =>
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
}
