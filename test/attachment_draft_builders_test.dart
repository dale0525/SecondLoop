import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_draft_builders.dart';

void main() {
  test('infer image mime type from path', () {
    expect(inferImageMimeTypeFromPath('photo.png'), 'image/png');
    expect(inferImageMimeTypeFromPath('photo.heic'), 'image/heif');
    expect(inferImageMimeTypeFromPath('photo.jpg'), 'image/jpeg');
  });

  test('infer attachment mime type from filename', () {
    expect(inferAttachmentMimeTypeFromFilename('clip.mp4'), 'video/mp4');
    expect(
      inferAttachmentMimeTypeFromFilename('archive.docx'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    expect(
      inferAttachmentMimeTypeFromFilename('no_extension'),
      'application/octet-stream',
    );
  });

  test('build desktop attachment draft payloads normalizes names and ids', () {
    var sequence = 0;
    final drafts = buildDesktopAttachmentDraftPayloads(
      [
        (
          filename: 'clip.mp4',
          bytes: Uint8List.fromList(const <int>[1, 2, 3]),
        ),
        (
          filename: '   ',
          bytes: Uint8List.fromList(const <int>[4, 5]),
        ),
      ],
      nextLocalId: () => 'draft_${++sequence}',
    );

    expect(drafts.length, 2);
    expect(drafts.first.localId, 'draft_1');
    expect(drafts.first.filename, 'clip.mp4');
    expect(drafts.first.mimeType, 'video/mp4');
    expect(drafts.last.localId, 'draft_2');
    expect(drafts.last.filename, 'attachment.bin');
    expect(drafts.last.mimeType, 'application/octet-stream');
  });

  test('build image attachment draft payload normalizes photo filename', () {
    final draft = buildImageAttachmentDraftPayload(
      localId: 'img_1',
      rawBytes: Uint8List.fromList(const <int>[1, 2, 3]),
      inferredMimeType: 'image/jpeg',
      filename: '   ',
    );

    expect(draft.localId, 'img_1');
    expect(draft.filename, 'photo.jpg');
    expect(draft.mimeType, 'image/jpeg');
  });
}
