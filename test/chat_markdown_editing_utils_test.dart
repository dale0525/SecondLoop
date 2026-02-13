import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_editing_utils.dart';

void main() {
  group('applyMarkdownHeading', () {
    test('adds heading marker to current line and keeps caret aligned', () {
      const value = TextEditingValue(
        text: 'hello world',
        selection: TextSelection.collapsed(offset: 11),
      );

      final updated = applyMarkdownHeading(value, level: 2);

      expect(updated.text, '## hello world');
      expect(updated.selection, const TextSelection.collapsed(offset: 14));
    });
  });

  group('applyMarkdownInlineWrap', () {
    test('wraps selected text with markers', () {
      const value = TextEditingValue(
        text: 'hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );

      final updated = applyMarkdownInlineWrap(
        value,
        prefix: '**',
      );

      expect(updated.text, 'hello **world**');
      expect(updated.selection,
          const TextSelection(baseOffset: 8, extentOffset: 13));
    });
  });

  group('applyMarkdownLink', () {
    test('inserts placeholder link when selection is empty', () {
      const value = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );

      final updated = applyMarkdownLink(value);

      expect(updated.text, 'hello[link text](https://)');
      expect(updated.selection,
          const TextSelection(baseOffset: 6, extentOffset: 15));
    });
  });

  group('MarkdownSmartContinuationFormatter', () {
    test('continues unordered list on enter', () {
      const formatter = MarkdownSmartContinuationFormatter();
      const oldValue = TextEditingValue(
        text: '- item',
        selection: TextSelection.collapsed(offset: 6),
      );
      const newValue = TextEditingValue(
        text: '- item\n',
        selection: TextSelection.collapsed(offset: 7),
      );

      final updated = formatter.formatEditUpdate(oldValue, newValue);

      expect(updated.text, '- item\n- ');
      expect(updated.selection, const TextSelection.collapsed(offset: 9));
    });

    test('increments ordered list on enter', () {
      const formatter = MarkdownSmartContinuationFormatter();
      const oldValue = TextEditingValue(
        text: '2. item',
        selection: TextSelection.collapsed(offset: 7),
      );
      const newValue = TextEditingValue(
        text: '2. item\n',
        selection: TextSelection.collapsed(offset: 8),
      );

      final updated = formatter.formatEditUpdate(oldValue, newValue);

      expect(updated.text, '2. item\n3. ');
      expect(updated.selection, const TextSelection.collapsed(offset: 11));
    });

    test('exits list when previous list item is empty', () {
      const formatter = MarkdownSmartContinuationFormatter();
      const oldValue = TextEditingValue(
        text: '- ',
        selection: TextSelection.collapsed(offset: 2),
      );
      const newValue = TextEditingValue(
        text: '- \n',
        selection: TextSelection.collapsed(offset: 3),
      );

      final updated = formatter.formatEditUpdate(oldValue, newValue);

      expect(updated.text, '\n');
      expect(updated.selection, const TextSelection.collapsed(offset: 1));
    });
  });
}
