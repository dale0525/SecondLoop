import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  group('CloudWebBackend', () {
    test('creates conversation and stores messages in memory', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      final conversation = await backend.createConversation(key, 'Web Chat');
      final inserted = await backend.insertMessage(
        key,
        conversation.id,
        role: 'user',
        content: 'hello from web',
      );

      final conversations = await backend.listConversations(key);
      final messages = await backend.listMessages(key, conversation.id);

      expect(conversations, hasLength(1));
      expect(conversations.single.title, 'Web Chat');
      expect(messages, hasLength(1));
      expect(messages.single.id, inserted.id);
      expect(messages.single.content, 'hello from web');
    });

    test('stores web attachments and serves bytes from memory', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final bytes = Uint8List.fromList('hello web'.codeUnits);
      const attachment = Attachment(
        sha256: 'sha-text',
        mimeType: 'text/plain',
        path: 'vault/sha-text.bin',
        byteLen: 9,
        createdAtMs: 0,
      );

      backend.rememberAttachment(attachment, bytes: bytes);

      final loadedAttachment = await backend.readAttachmentBySha256('sha-text');
      final loadedBytes =
          await backend.readAttachmentBytes(Uint8List(0), sha256: 'sha-text');

      expect(loadedAttachment?.sha256, 'sha-text');
      expect(String.fromCharCodes(loadedBytes), 'hello web');
    });

    test('getMessageById finds inserted messages in memory', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      final conversation = await backend.createConversation(key, 'Web Chat');
      final inserted = await backend.insertMessage(
        key,
        conversation.id,
        role: 'assistant',
        content: 'stored reply',
      );

      final loaded = await backend.getMessageById(key, inserted.id);

      expect(loaded, isNotNull);
      expect(loaded!.id, inserted.id);
      expect(loaded.content, 'stored reply');
    });

    test('setMessageDeleted can restore a previously deleted message',
        () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      final conversation = await backend.createConversation(key, 'Web Chat');
      final inserted = await backend.insertMessage(
        key,
        conversation.id,
        role: 'user',
        content: 'restore me',
      );

      await backend.setMessageDeleted(key, inserted.id, true);
      expect(await backend.listMessages(key, conversation.id), isEmpty);

      await backend.setMessageDeleted(key, inserted.id, false);
      final restored = await backend.listMessages(key, conversation.id);

      expect(restored, hasLength(1));
      expect(restored.single.id, inserted.id);
      expect(restored.single.content, 'restore me');
    });

    test('runAiPromptCloudGateway delegates to chat client', () async {
      final client = _FakeCloudWebChatClient(responseText: 'cloud result');
      final backend = CloudWebBackend(chatClient: client);

      final result = await backend.runAiPromptCloudGateway(
        Uint8List(0),
        prompt: 'rank my tasks',
        gatewayBaseUrl: 'https://gateway.test',
        idToken: 'token-1',
        modelName: 'cloud',
      );

      expect(result, 'cloud result');
      expect(client.calls, hasLength(1));
      expect(client.calls.single.idToken, 'token-1');
      expect(client.calls.single.messages.single['content'], 'rank my tasks');
    });

    test('unsupported native-only methods throw controlled error', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );

      expect(
        () => backend.unlockWithPassword('secret'),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('not available in web'),
          ),
        ),
      );
    });
  });
}

final class _FakeCloudWebChatClient implements CloudWebChatClient {
  _FakeCloudWebChatClient({required this.responseText});

  final String responseText;
  final List<_ChatCall> calls = <_ChatCall>[];

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) async {
    calls.add(
      _ChatCall(
        idToken: idToken,
        gatewayBaseUrl: gatewayBaseUrl,
        modelName: modelName,
        messages: messages,
      ),
    );
    return responseText;
  }
}

final class _ChatCall {
  const _ChatCall({
    required this.idToken,
    required this.gatewayBaseUrl,
    required this.modelName,
    required this.messages,
  });

  final String idToken;
  final String gatewayBaseUrl;
  final String modelName;
  final List<Map<String, String>> messages;
}
