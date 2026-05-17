import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_coordinator.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  test('send creates one message and links all successful drafts', () async {
    const coordinator = AttachmentDraftSendCoordinator();
    final drafts = <AttachmentDraftPayload>[
      AttachmentDraftPayload(
        localId: 'a',
        filename: 'a.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[1]),
      ),
      AttachmentDraftPayload(
        localId: 'b',
        filename: 'b.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[2]),
      ),
    ];

    var createMessageCalls = 0;
    final linkCalls = <String>[];

    final result = await coordinator.send(
      text: 'hello',
      drafts: drafts,
      createUserMessage: (content) async {
        createMessageCalls += 1;
        return Message(
          id: 'm1',
          conversationId: 'c1',
          role: 'user',
          content: content,
          createdAtMs: 1,
          isMemory: true,
        );
      },
      ingestAttachment: (draft) async => 'sha_${draft.localId}',
      linkAttachmentToMessage: (messageId, attachmentSha256) async {
        linkCalls.add('$messageId:$attachmentSha256');
      },
    );

    expect(createMessageCalls, 1);
    expect(linkCalls, <String>['m1:sha_a', 'm1:sha_b']);
    expect(result.messageId, 'm1');
    expect(result.linkedAttachmentShas, <String>['sha_a', 'sha_b']);
    expect(result.failedItems, isEmpty);
    expect(result.attemptedCount, 2);
  });

  test('send returns partial success when one draft ingest fails', () async {
    const coordinator = AttachmentDraftSendCoordinator();
    final drafts = <AttachmentDraftPayload>[
      AttachmentDraftPayload(
        localId: 'ok',
        filename: 'ok.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[1]),
      ),
      AttachmentDraftPayload(
        localId: 'bad',
        filename: 'bad.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[2]),
      ),
    ];

    final result = await coordinator.send(
      text: 'note',
      drafts: drafts,
      createUserMessage: (content) async => Message(
        id: 'm2',
        conversationId: 'c1',
        role: 'user',
        content: content,
        createdAtMs: 2,
        isMemory: true,
      ),
      ingestAttachment: (draft) async {
        if (draft.localId == 'bad') {
          throw StateError('ingest_failed_bad');
        }
        return 'sha_${draft.localId}';
      },
      linkAttachmentToMessage: (_, __) async {},
    );

    expect(result.messageId, 'm2');
    expect(result.linkedAttachmentShas, <String>['sha_ok']);
    expect(result.failedItems.length, 1);
    expect(result.failedItems.single.payload.localId, 'bad');
    expect(result.failedItems.single.kind, SendFailureKind.ingestFailed);
  });

  test('send does not create empty message when text empty and all drafts fail',
      () async {
    const coordinator = AttachmentDraftSendCoordinator();
    final drafts = <AttachmentDraftPayload>[
      AttachmentDraftPayload(
        localId: 'f1',
        filename: 'f1.bin',
        mimeType: 'application/octet-stream',
        bytes: Uint8List.fromList(<int>[9]),
      ),
    ];

    var createMessageCalls = 0;
    final result = await coordinator.send(
      text: '   ',
      drafts: drafts,
      createUserMessage: (content) async {
        createMessageCalls += 1;
        return Message(
          id: 'm3',
          conversationId: 'c1',
          role: 'user',
          content: content,
          createdAtMs: 3,
          isMemory: true,
        );
      },
      ingestAttachment: (_) async => throw StateError('ingest_failed'),
      linkAttachmentToMessage: (_, __) async {},
    );

    expect(createMessageCalls, 0);
    expect(result.messageId, isNull);
    expect(result.linkedAttachmentShas, isEmpty);
    expect(result.failedItems.length, 1);
    expect(result.failedItems.single.kind, SendFailureKind.ingestFailed);
  });

  test('send dedupes duplicate drafts before ingest and link', () async {
    const coordinator = AttachmentDraftSendCoordinator();
    final sameBytes = Uint8List.fromList(<int>[7, 7, 7]);
    final drafts = <AttachmentDraftPayload>[
      AttachmentDraftPayload(
        localId: 'a',
        filename: 'same.txt',
        mimeType: 'text/plain',
        bytes: sameBytes,
      ),
      AttachmentDraftPayload(
        localId: 'b',
        filename: 'same.txt',
        mimeType: 'text/plain',
        bytes: sameBytes,
      ),
    ];

    var ingestCalls = 0;
    var linkCalls = 0;
    final result = await coordinator.send(
      text: 'hello',
      drafts: drafts,
      createUserMessage: (content) async => Message(
        id: 'm4',
        conversationId: 'c1',
        role: 'user',
        content: content,
        createdAtMs: 4,
        isMemory: true,
      ),
      ingestAttachment: (_) async {
        ingestCalls += 1;
        return 'sha_same';
      },
      linkAttachmentToMessage: (_, __) async {
        linkCalls += 1;
      },
    );

    expect(ingestCalls, 1);
    expect(linkCalls, 1);
    expect(result.attemptedCount, 1);
    expect(result.linkedAttachmentShas, const <String>['sha_same']);
  });
}
