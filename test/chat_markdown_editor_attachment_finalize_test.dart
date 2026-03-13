import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';
import 'package:secondloop/features/chat/chat_markdown_editor_attachment_finalize.dart';

void main() {
  test('finalizes draft markdown image refs into persisted attachment refs',
      () async {
    final result = await finalizeMarkdownEditorAttachments(
      markdown: [
        'hello',
        '![one](secondloop-draft://image/draft_1)',
        '![two](secondloop-draft://image/draft_2)',
      ].join('\n'),
      draftAttachments: <AttachmentDraftPayload>[
        _draft('draft_1'),
        _draft('draft_2'),
      ],
      ingestAttachment: (draft) async => 'sha_${draft.localId}',
    );

    expect(result.markdown, contains('secondloop://attachment/sha_draft_1'));
    expect(result.markdown, contains('secondloop://attachment/sha_draft_2'));
    expect(result.referencedAttachmentShas,
        <String>{'sha_draft_1', 'sha_draft_2'});
    expect(result.ingestedAttachmentShaByLocalId, const <String, String>{
      'draft_1': 'sha_draft_1',
      'draft_2': 'sha_draft_2',
    });
  });

  test('keeps existing persisted refs in referenced sha set', () async {
    final result = await finalizeMarkdownEditorAttachments(
      markdown: [
        '![existing](secondloop://attachment/existing_sha)',
        '![new](secondloop-draft://image/draft_1)',
      ].join('\n'),
      draftAttachments: <AttachmentDraftPayload>[_draft('draft_1')],
      ingestAttachment: (draft) async => 'new_sha',
    );

    expect(
        result.referencedAttachmentShas, <String>{'existing_sha', 'new_sha'});
  });

  test('ingests only draft attachments still referenced in markdown', () async {
    final ingestedLocalIds = <String>[];

    final result = await finalizeMarkdownEditorAttachments(
      markdown: '![keep](secondloop-draft://image/draft_1)',
      draftAttachments: <AttachmentDraftPayload>[
        _draft('draft_1'),
        _draft('draft_2'),
      ],
      ingestAttachment: (draft) async {
        ingestedLocalIds.add(draft.localId);
        return 'sha_${draft.localId}';
      },
    );

    expect(ingestedLocalIds, <String>['draft_1']);
    expect(result.ingestedAttachmentShaByLocalId, const <String, String>{
      'draft_1': 'sha_draft_1',
    });
    expect(result.referencedAttachmentShas, <String>{'sha_draft_1'});
  });

  test('throws when markdown still contains unresolved draft refs', () async {
    expect(
      () => finalizeMarkdownEditorAttachments(
        markdown: '![missing](secondloop-draft://image/draft_missing)',
        draftAttachments: const <AttachmentDraftPayload>[],
        ingestAttachment: (draft) async => 'ignored',
      ),
      throwsA(isA<StateError>()),
    );
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
