import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';
import 'package:secondloop/features/chat/chat_markdown_bundle_export.dart';

void main() {
  test('exports markdown bundle for draft image refs', () async {
    final dir = await Directory.systemTemp.createTemp('markdown-bundle-');

    try {
      final result = await exportChatMarkdownBundle(
        markdown: '![draft](secondloop-draft://image/draft_1)',
        filenameStem: 'note',
        outputDirectory: dir,
        draftAttachments: <AttachmentDraftPayload>[
          AttachmentDraftPayload(
            localId: 'draft_1',
            filename: 'draft.png',
            mimeType: 'image/png',
            bytes: _pngBytes(),
          ),
        ],
      );

      expect(await result.markdownFile.exists(), isTrue);
      expect(await result.assetDirectory.exists(), isTrue);

      final markdownText = await result.markdownFile.readAsString();
      expect(markdownText, contains('![draft](note.assets/draft_1.png)'));
      expect(await File('${result.assetDirectory.path}/draft_1.png').exists(),
          isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('exports markdown bundle for persisted attachment refs', () async {
    final dir = await Directory.systemTemp.createTemp('markdown-bundle-');

    try {
      final result = await exportChatMarkdownBundle(
        markdown: '![saved](secondloop://attachment/sha_1)',
        filenameStem: 'note',
        outputDirectory: dir,
        readPersistedAttachment: (sha256) async {
          if (sha256 != 'sha_1') return null;
          return MarkdownBundleAssetData(
            bytes: _pngBytes(),
            mimeType: 'image/png',
            filename: 'saved.png',
          );
        },
      );

      expect(await result.markdownFile.exists(), isTrue);
      final markdownText = await result.markdownFile.readAsString();
      expect(markdownText, contains('note.assets/sha_1.png'));
      expect(await File('${result.assetDirectory.path}/sha_1.png').exists(),
          isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('exports markdown bundle with a unique suffix when stem already exists',
      () async {
    final dir = await Directory.systemTemp.createTemp('markdown-bundle-');

    try {
      await File('${dir.path}/note.md').writeAsString('existing');
      await Directory('${dir.path}/note.assets').create();

      final result = await exportChatMarkdownBundle(
        markdown: '![draft](secondloop-draft://image/draft_1)',
        filenameStem: 'note',
        outputDirectory: dir,
        draftAttachments: <AttachmentDraftPayload>[
          AttachmentDraftPayload(
            localId: 'draft_1',
            filename: 'draft.png',
            mimeType: 'image/png',
            bytes: _pngBytes(),
          ),
        ],
      );

      expect(result.markdownFile.path, endsWith('note-2.md'));
      expect(result.assetDirectory.path, endsWith('note-2.assets'));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
      'exports markdown bundle with a unique suffix when assets dir already exists',
      () async {
    final dir = await Directory.systemTemp.createTemp('markdown-bundle-');

    try {
      await Directory('${dir.path}/note.assets').create();
      await File('${dir.path}/note.assets/stale.png').writeAsBytes(_pngBytes());

      final result = await exportChatMarkdownBundle(
        markdown: '![draft](secondloop-draft://image/draft_1)',
        filenameStem: 'note',
        outputDirectory: dir,
        draftAttachments: <AttachmentDraftPayload>[
          AttachmentDraftPayload(
            localId: 'draft_1',
            filename: 'draft.png',
            mimeType: 'image/png',
            bytes: _pngBytes(),
          ),
        ],
      );

      expect(result.markdownFile.path, endsWith('note-2.md'));
      expect(result.assetDirectory.path, endsWith('note-2.assets'));
      expect(await File('${dir.path}/note.assets/stale.png').exists(), isTrue);
      expect(await File('${result.assetDirectory.path}/draft_1.png').exists(),
          isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('keeps persisted refs when attachment bytes are unavailable', () async {
    final dir = await Directory.systemTemp.createTemp('markdown-bundle-');

    try {
      final result = await exportChatMarkdownBundle(
        markdown: '![saved](secondloop://attachment/sha_missing)',
        filenameStem: 'note',
        outputDirectory: dir,
      );

      expect(await result.markdownFile.exists(), isTrue);
      final markdownText = await result.markdownFile.readAsString();
      expect(markdownText, contains('secondloop://attachment/sha_missing'));
      expect(await result.assetDirectory.list().isEmpty, isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

Uint8List _pngBytes() => Uint8List.fromList(const <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      0x00,
      0x00,
      0x00,
      0x0d,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1f,
      0x15,
      0xc4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0a,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9c,
      0x63,
      0xf8,
      0xcf,
      0xc0,
      0x00,
      0x00,
      0x03,
      0x01,
      0x01,
      0x00,
      0x18,
      0xdd,
      0x8d,
      0xb1,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4e,
      0x44,
      0xae,
      0x42,
      0x60,
      0x82,
    ]);
