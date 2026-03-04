import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

  test('URL semantic analysis prefers llm summary over parsed page text',
      () async {
    final backend = _SemanticInputBackend(
      messages: <String, Message>{
        'msg:url': _message(id: 'msg:url', content: ''),
      },
      attachmentsByMessageId: <String, List<Attachment>>{
        'msg:url': <Attachment>[
          _attachment(
            sha256: 'sha:url',
            mimeType: 'application/x.secondloop.url+json',
          ),
        ],
      },
      captionsBySha: const <String, String>{
        'sha:url': 'Legacy caption that should be ignored.',
      },
      payloadJsonBySha: <String, String>{
        'sha:url': jsonEncode(
          <String, Object?>{
            'mime_type': 'application/x.secondloop.url+json',
            'llm_summary': 'Cloud concise summary for semantic parse.',
            'readable_text_excerpt': 'Noisy local excerpt.',
            'readable_text_full': 'Noisy local full page content.',
          },
        ),
      },
    );
    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: sessionKey,
    );

    final input = await store.getMessageInput('msg:url');

    expect(input, isNotNull);
    expect(input!.analysisText, 'Cloud concise summary for semantic parse.');
    expect(input.analysisText, isNot(contains('Noisy local')));
    expect(input.analysisText, isNot(contains('Legacy caption')));
    expect(input.allowCreate, isFalse);
  });

  test('attachment semantic context disables create even with short message',
      () async {
    final backend = _SemanticInputBackend(
      messages: <String, Message>{
        'msg:mixed': _message(id: 'msg:mixed', content: '明天提交周报'),
      },
      attachmentsByMessageId: <String, List<Attachment>>{
        'msg:mixed': <Attachment>[
          _attachment(
            sha256: 'sha:mixed',
            mimeType: 'application/x.secondloop.url+json',
          ),
        ],
      },
      payloadJsonBySha: <String, String>{
        'sha:mixed': jsonEncode(
          <String, Object?>{
            'mime_type': 'application/x.secondloop.url+json',
            'llm_summary': '项目周报链接摘要',
          },
        ),
      },
    );
    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: sessionKey,
    );

    final input = await store.getMessageInput('msg:mixed');

    expect(input, isNotNull);
    expect(input!.analysisText, contains('明天提交周报'));
    expect(input.analysisText, contains('项目周报链接摘要'));
    expect(input.allowCreate, isFalse);
  });
}

Message _message({
  required String id,
  required String content,
}) {
  return Message(
    id: id,
    conversationId: 'loop_home',
    role: 'user',
    content: content,
    createdAtMs: PlatformInt64Util.from(1),
    isMemory: true,
  );
}

Attachment _attachment({
  required String sha256,
  required String mimeType,
}) {
  return Attachment(
    sha256: sha256,
    mimeType: mimeType,
    path: '/tmp/$sha256',
    byteLen: PlatformInt64Util.from(1),
    createdAtMs: PlatformInt64Util.from(1),
  );
}

final class _SemanticInputBackend extends NativeAppBackend {
  _SemanticInputBackend({
    required this.messages,
    required this.attachmentsByMessageId,
    this.captionsBySha = const <String, String>{},
    this.payloadJsonBySha = const <String, String>{},
  }) : super(appDirProvider: () async => '/tmp/secondloop-test');

  final Map<String, Message> messages;
  final Map<String, List<Attachment>> attachmentsByMessageId;
  final Map<String, String> captionsBySha;
  final Map<String, String> payloadJsonBySha;

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    return messages[messageId];
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async {
    return List<Attachment>.from(
      attachmentsByMessageId[messageId] ?? const <Attachment>[],
    );
  }

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async {
    return captionsBySha[sha256];
  }

  @override
  Future<String?> readAttachmentAnnotationPayloadJson(
    Uint8List key, {
    required String sha256,
  }) async {
    return payloadJsonBySha[sha256];
  }
}
