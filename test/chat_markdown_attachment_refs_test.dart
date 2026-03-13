import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/chat/chat_markdown_attachment_refs.dart';

void main() {
  test('parses draft markdown image refs', () {
    final ref = parseDraftMarkdownImageRef('secondloop-draft://image/draft_1');

    expect(ref, isNotNull);
    expect(ref?.localId, 'draft_1');
  });

  test('builds draft markdown image refs', () {
    expect(
      buildDraftMarkdownImageSource('draft_1'),
      'secondloop-draft://image/draft_1',
    );
  });

  test('builds persisted markdown attachment refs', () {
    expect(
      buildPersistedMarkdownAttachmentImageSource('sha_123'),
      'secondloop://attachment/sha_123',
    );
  });

  test('rewrites draft markdown image refs to persisted refs', () {
    final markdown = [
      'before',
      '![one](secondloop-draft://image/draft_1)',
      '![two](<secondloop-draft://image/draft_2>)',
      '![keep](https://example.com/image.png)',
    ].join('\n');

    final rewritten = rewriteDraftMarkdownImageRefs(
      markdown,
      const <String, String>{
        'draft_1': 'sha_one',
        'draft_2': 'sha_two',
      },
    );

    expect(rewritten, contains('![one](secondloop://attachment/sha_one)'));
    expect(rewritten, contains('![two](<secondloop://attachment/sha_two>)'));
    expect(rewritten, contains('![keep](https://example.com/image.png)'));
  });

  test('collects persisted attachment shas from markdown image refs', () {
    final markdown = [
      '![one](secondloop://attachment/sha_one)',
      '![two](<secondloop://attachment/sha_two>)',
      '![external](https://example.com/image.png)',
      '[link](secondloop://attachment/sha_three)',
    ].join('\n');

    expect(
      collectPersistedMarkdownAttachmentShas(markdown),
      <String>{'sha_one', 'sha_two'},
    );
  });
}
