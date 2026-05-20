import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/features/agent_ui/agent_runtime_file_context.dart';

void main() {
  test('recent file item shows media summary without raw OCR/status/mime chain',
      () {
    const attachmentId = 'sha-image-1';
    final state = RuntimeAgentState.fromJson(const {
      'vault_id': 'uid_1',
      'conversation_id': 'loop_home',
      'conversation_turns': [
        {
          'turn_id': 'turn-user-media',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'role': 'user',
          'content': '帮我看看这张图片里写了什么。',
          'attachment_refs': [attachmentId],
          'attachments': [
            {
              'attachment_id': attachmentId,
              'filename': 'qa-ocr-sample.png',
              'mime_type': 'image/png',
              'media_type': 'image',
            },
          ],
          'created_at_ms': 1700000000000,
        },
      ],
      'working_set_records': [
        {
          'id': 'media-result-sha-image-1',
          'kind': 'media_result',
          'attachment_id': attachmentId,
          'media_type': 'image',
          'ocr_text': 'QA PICTURE',
          'summary': '识别到测试标题。',
          'status': 'completed',
        },
      ],
    });

    final items = agentRuntimeRecentFileItems(state, null);

    expect(items, hasLength(1));
    expect(items.single.title, 'qa-ocr-sample.png');
    expect(items.single.subtitle, '识别到测试标题。');
    expect(items.single.subtitle, isNot(contains('QA PICTURE')));
    expect(items.single.subtitle, isNot(contains('completed')));
    expect(items.single.subtitle, isNot(contains('image/png')));
  });

  test('recent file item shows uploaded file type before media result exists',
      () {
    const attachmentId = 'sha-image-1';
    final state = RuntimeAgentState.fromJson(const {
      'vault_id': 'uid_1',
      'conversation_id': 'loop_home',
      'conversation_turns': [
        {
          'turn_id': 'turn-user-media',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'role': 'user',
          'content': '帮我看看这张图片里写了什么。',
          'attachment_refs': [attachmentId],
          'attachments': [
            {
              'attachment_id': attachmentId,
              'filename': 'qa-ocr-sample.png',
              'mime_type': 'image/png',
              'media_type': 'image',
            },
          ],
          'created_at_ms': 1700000000000,
        },
      ],
      'working_set_records': [],
    });

    final items = agentRuntimeRecentFileItems(state, null);

    expect(items, hasLength(1));
    expect(items.single.title, 'qa-ocr-sample.png');
    expect(items.single.subtitle, 'Image uploaded');
  });
}
