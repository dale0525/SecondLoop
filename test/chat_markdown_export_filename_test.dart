import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_export_filename.dart';

void main() {
  group('deriveMarkdownExportFilenameStem', () {
    test('uses the first heading when available', () {
      const markdown = '# Product roadmap\n\nSecond paragraph.';

      final stem = deriveMarkdownExportFilenameStem(markdown);

      expect(stem, 'Product-roadmap');
    });

    test('falls back to the first sentence when no heading exists', () {
      const markdown = 'Today we ship editor upgrades. More details below.';

      final stem = deriveMarkdownExportFilenameStem(markdown);

      expect(stem, 'Today-we-ship-editor-upgrades');
    });

    test('removes invalid filename characters and truncates length', () {
      const markdown =
          '# Sprint: Alpha/Beta?* with very very very very very long name';

      final stem = deriveMarkdownExportFilenameStem(markdown, maxLength: 24);

      expect(stem, 'Sprint-Alpha-Beta-with-v');
      expect(stem.length, lessThanOrEqualTo(24));
    });

    test('uses default fallback when no valid content can be extracted', () {
      const markdown = '???///***';

      final stem = deriveMarkdownExportFilenameStem(markdown);

      expect(stem, 'markdown-export');
    });
  });
}
