import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/detached_ask_recovery_service.dart';

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
}
