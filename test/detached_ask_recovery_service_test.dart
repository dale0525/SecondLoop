import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/detached_ask_recovery_service.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persist draft snapshot before request id and keep conversation id',
      () async {
    await DetachedAskRecoveryService.persistSnapshot(
      requestId: null,
      question: 'hello',
      conversationId: 'conv_1',
      gatewayBaseUrl: 'https://gateway.example',
      state: DetachedAskSnapshotState.streamingConnected,
    );

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAskAiDetachedJobPrefsKey);
    expect(raw, isNotNull);

    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['request_id'], isNull);
    expect(decoded['conversation_id'], 'conv_1');
    expect(decoded['state'], 'streaming_connected');
  });

  test('read snapshot keeps attempt and poll fields', () async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await DetachedAskRecoveryService.persistSnapshot(
      requestId: 'req_123456',
      question: 'hello',
      conversationId: 'conv_1',
      gatewayBaseUrl: 'https://gateway.example',
      state: DetachedAskSnapshotState.streamingDisconnectedRecovering,
      createdAtMs: nowMs - 1000,
      attemptCount: 4,
      lastPollAtMs: nowMs - 200,
    );

    final snapshot = await DetachedAskRecoveryService.readSnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.requestId, 'req_123456');
    expect(snapshot.conversationId, 'conv_1');
    expect(
      snapshot.state,
      DetachedAskSnapshotState.streamingDisconnectedRecovering,
    );
    expect(snapshot.attemptCount, 4);
    expect(snapshot.lastPollAtMs, nowMs - 200);
  });

  test(
      'applyCompletionOnceViaEventMarker falls back to backend atomic recovery without partial writes',
      () async {
    final backend = _DetachedRecoveryBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    final applied =
        await DetachedAskRecoveryService.applyCompletionOnceViaEventMarker(
      backend: backend,
      sessionKey: key,
      requestId: 'req_123456',
      conversationId: 'loop_home',
      question: 'hello',
      answer: 'world',
      citationsJson: '{"direct_sources":[]}',
      gatewayBaseUrl: 'https://gateway.example',
    );

    expect(applied, isTrue);
    expect(backend.recoveryCalls, 1);

    final messages = await backend.listMessages(key, 'loop_home');
    expect(messages, hasLength(2));
    expect(messages.map((message) => message.role).toList(), [
      'user',
      'assistant',
    ]);
    expect(messages.every((message) => !message.isMemory), isTrue);
    expect(messages.last.citationsJson, '{"direct_sources":[]}');
    expect(backend.insertMessageCalls, 0);
  });

  test(
      'applyCompletionOnceViaEventMarker refuses unsafe fallback when backend atomic recovery is unavailable',
      () async {
    final backend = TestAppBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    final applied =
        await DetachedAskRecoveryService.applyCompletionOnceViaEventMarker(
      backend: backend,
      sessionKey: key,
      requestId: 'req_654321',
      conversationId: 'loop_home',
      question: 'hello',
      answer: 'world',
    );

    expect(applied, isFalse);
    expect(await backend.listMessages(key, 'loop_home'), isEmpty);
  });
}

final class _DetachedRecoveryBackend extends TestAppBackend
    implements DetachedAskCompletionRecoveryBackend {
  int recoveryCalls = 0;
  int insertMessageCalls = 0;
  final Map<String, List<Message>> _messagesByConversation =
      <String, List<Message>>{};

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) {
    insertMessageCalls += 1;
    throw StateError('generic insertMessage should not be used');
  }

  @override
  Future<List<Message>> listMessages(
      Uint8List key, String conversationId) async {
    return List<Message>.from(
      _messagesByConversation[conversationId] ?? const <Message>[],
    );
  }

  @override
  Future<bool> applyDetachedAskCompletionOnce(
    Uint8List key, {
    required String requestId,
    required String conversationId,
    required String question,
    required String answer,
    String? citationsJson,
  }) async {
    recoveryCalls += 1;
    final existing = await listMessages(key, conversationId);
    if (existing.any((message) => message.content == answer)) {
      return false;
    }
    final list = _messagesFor(conversationId);
    list.add(
      Message(
        id: 'm${list.length + 1}',
        conversationId: conversationId,
        role: 'user',
        content: question,
        createdAtMs: list.length + 1,
        isMemory: false,
      ),
    );
    list.add(
      Message(
        id: 'm${list.length + 1}',
        conversationId: conversationId,
        role: 'assistant',
        content: answer,
        createdAtMs: list.length + 1,
        isMemory: false,
        citationsJson: citationsJson,
      ),
    );
    return true;
  }

  List<Message> _messagesFor(String conversationId) =>
      _messagesByConversation.putIfAbsent(conversationId, () => <Message>[]);
}
