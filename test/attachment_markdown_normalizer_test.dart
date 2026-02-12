import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_markdown_normalizer.dart';

void main() {
  test(
      'normalizeAttachmentMarkdown restores escaped newlines for markdown text',
      () {
    final normalized = normalizeAttachmentMarkdown(
      r'# Title\n\n- first\n- second',
    );

    expect(normalized, '# Title\n\n- first\n- second');
  });

  test('normalizeAttachmentMarkdown keeps escaped windows-style paths', () {
    const raw = r'C:\\new\\folder\\notes.txt';

    final normalized = normalizeAttachmentMarkdown(raw);

    expect(normalized, raw);
  });
}
