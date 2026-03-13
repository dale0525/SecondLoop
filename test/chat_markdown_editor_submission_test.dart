import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';
import 'package:secondloop/features/chat/chat_markdown_editor_submission.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('send flow creates message with rewritten markdown and links refs',
      () async {
    final linked = <String>[];
    final createdContents = <String>[];

    final result = await sendMarkdownEditorMessage(
      markdown: [
        '![old](secondloop://attachment/existing_sha)',
        '![new](secondloop-draft://image/draft_1)',
      ].join('\n'),
      draftAttachments: <AttachmentDraftPayload>[_draft('draft_1')],
      ingestAttachment: (draft) async => 'new_sha',
      createMessage: (content) async {
        createdContents.add(content);
        return Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'user',
          content: content,
          createdAtMs: 1,
          isMemory: false,
        );
      },
      linkAttachmentToMessage: (messageId, attachmentSha256) async {
        linked.add('$messageId:$attachmentSha256');
      },
    );

    expect(createdContents.single, contains('secondloop://attachment/new_sha'));
    expect(result.messageId, 'm1');
    expect(
        result.referencedAttachmentShas, <String>{'existing_sha', 'new_sha'});
    expect(linked, containsAll(<String>['m1:existing_sha', 'm1:new_sha']));
  });

  test('edit flow rewrites markdown and links referenced attachments',
      () async {
    String? editedMessageId;
    String? editedContent;
    final linked = <String>[];

    final result = await editMarkdownEditorMessage(
      messageId: 'm2',
      markdown: '![new](secondloop-draft://image/draft_1)',
      draftAttachments: <AttachmentDraftPayload>[_draft('draft_1')],
      ingestAttachment: (draft) async => 'edited_sha',
      editMessage: (messageId, content) async {
        editedMessageId = messageId;
        editedContent = content;
      },
      linkAttachmentToMessage: (messageId, attachmentSha256) async {
        linked.add('$messageId:$attachmentSha256');
      },
    );

    expect(editedMessageId, 'm2');
    expect(editedContent, contains('secondloop://attachment/edited_sha'));
    expect(result.referencedAttachmentShas, <String>{'edited_sha'});
    expect(linked, <String>['m2:edited_sha']);
  });
}

AttachmentDraftPayload _draft(String localId) {
  return AttachmentDraftPayload(
    localId: localId,
    filename: '$localId.png',
    mimeType: 'image/png',
    bytes: Uint8List.fromList(const <int>[1, 2, 3]),
  );
}
