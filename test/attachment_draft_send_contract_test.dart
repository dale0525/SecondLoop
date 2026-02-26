import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';

void main() {
  test('dedupeAttachmentDraftPayloads drops same fingerprint items', () {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final items = <AttachmentDraftPayload>[
      AttachmentDraftPayload(
        localId: 'a',
        filename: 'demo.txt',
        mimeType: 'text/plain',
        bytes: bytes,
      ),
      AttachmentDraftPayload(
        localId: 'b',
        filename: ' demo.txt ',
        mimeType: ' text/plain ',
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      ),
      AttachmentDraftPayload(
        localId: 'c',
        filename: 'other.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[9]),
      ),
    ];

    final deduped = dedupeAttachmentDraftPayloads(items);

    expect(deduped.length, 2);
    expect(deduped.first.localId, 'a');
    expect(deduped.last.localId, 'c');
  });

  test('AttachmentDraftProgress supports state transitions', () {
    const queued = AttachmentDraftProgress(
      localId: 'x',
      status: AttachmentDraftItemStatus.queued,
    );
    const ingesting = AttachmentDraftProgress(
      localId: 'x',
      status: AttachmentDraftItemStatus.ingesting,
    );
    const linked = AttachmentDraftProgress(
      localId: 'x',
      status: AttachmentDraftItemStatus.linked,
      attachmentSha256: 'sha_x',
    );

    expect(queued.status, AttachmentDraftItemStatus.queued);
    expect(ingesting.status, AttachmentDraftItemStatus.ingesting);
    expect(linked.status, AttachmentDraftItemStatus.linked);
    expect(linked.attachmentSha256, 'sha_x');
  });

  test('SendDraftResult keeps linked and failed items', () {
    final failed = FailedAttachmentDraft(
      payload: AttachmentDraftPayload(
        localId: 'f1',
        filename: 'bad.bin',
        mimeType: 'application/octet-stream',
        bytes: Uint8List.fromList(<int>[7]),
      ),
      kind: SendFailureKind.ingestFailed,
      error: 'ingest_failed',
    );

    final result = SendDraftResult(
      messageId: 'm1',
      sourceMessageId: 'm1',
      linkedAttachmentShas: const <String>['sha1', 'sha2'],
      failedItems: <FailedAttachmentDraft>[failed],
      attemptedCount: 3,
    );

    expect(result.messageId, 'm1');
    expect(result.sourceMessageId, 'm1');
    expect(result.linkedAttachmentShas, const <String>['sha1', 'sha2']);
    expect(result.failedItems.length, 1);
    expect(result.failedItems.single.kind, SendFailureKind.ingestFailed);
    expect(result.attemptedCount, 3);
  });
}
