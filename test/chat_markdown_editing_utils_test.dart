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

    test('toggles wrapped selection off when already bold', () {
      const value = TextEditingValue(
        text: 'hello **world**',
        selection: TextSelection(baseOffset: 8, extentOffset: 13),
      );

      final updated = toggleMarkdownInlineWrap(value, marker: '**');

      expect(updated.text, 'hello world');
      expect(
        updated.selection,
        const TextSelection(baseOffset: 6, extentOffset: 11),
      );
    });

    test('detects inline style state from wrapped selection', () {
      const boldValue = TextEditingValue(
        text: 'hello **world**',
        selection: TextSelection(baseOffset: 8, extentOffset: 13),
      );

      expect(isMarkdownInlineWrapActive(boldValue, marker: '**'), isTrue);
      expect(isMarkdownInlineWrapActive(boldValue, marker: '*'), isFalse);

      const italicValue = TextEditingValue(
        text: 'hello *world*',
        selection: TextSelection(baseOffset: 7, extentOffset: 12),
      );
      expect(isMarkdownInlineWrapActive(italicValue, marker: '*'), isTrue);

      const boldItalicValue = TextEditingValue(
        text: 'hello ***world***',
        selection: TextSelection(baseOffset: 9, extentOffset: 14),
      );
      expect(isMarkdownInlineWrapActive(boldItalicValue, marker: '**'), isTrue);
      expect(isMarkdownInlineWrapActive(boldItalicValue, marker: '*'), isTrue);

      final toggledItalic =
          toggleMarkdownInlineWrap(boldItalicValue, marker: '*');
      expect(toggledItalic.text, 'hello **world**');
      expect(
        toggledItalic.selection,
        const TextSelection(baseOffset: 8, extentOffset: 13),
      );

      const underscoreWrapped = TextEditingValue(
        text: 'hello ___world___',
        selection: TextSelection(baseOffset: 9, extentOffset: 14),
      );
      expect(
        isMarkdownInlineWrapActive(
          underscoreWrapped,
          marker: '**',
          alternateMarkers: const <String>['__'],
        ),
        isTrue,
      );
      expect(
        isMarkdownInlineWrapActive(
          underscoreWrapped,
          marker: '*',
          alternateMarkers: const <String>['_'],
        ),
        isTrue,
      );

      final toggledUnderscoreItalic = toggleMarkdownInlineWrap(
        underscoreWrapped,
        marker: '*',
        alternateMarkers: const <String>['_'],
      );
      expect(toggledUnderscoreItalic.text, 'hello __world__');
      expect(
        toggledUnderscoreItalic.selection,
        const TextSelection(baseOffset: 8, extentOffset: 13),
      );
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

  group('list toggles on empty lines', () {
    test('unordered list inserts marker on empty line', () {
      const value = TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );

      final updated = toggleMarkdownUnorderedList(value);

      expect(updated.text, '- ');
      expect(
        updated.selection,
        const TextSelection.collapsed(offset: 2),
      );
    });

    test('ordered list inserts first marker on empty line', () {
      const value = TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );

      final updated = toggleMarkdownOrderedList(value);

      expect(updated.text, '1. ');
      expect(
        updated.selection,
        const TextSelection.collapsed(offset: 3),
      );
    });

    test('task list inserts checkbox marker on empty line', () {
      const value = TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );

      final updated = toggleMarkdownTaskList(value);

      expect(updated.text, '- [ ] ');
      expect(
        updated.selection,
        const TextSelection.collapsed(offset: 6),
      );
    });
  });

  group('markdown list depth indentation', () {
    test('tab indents current list line when caret is collapsed', () {
      const value = TextEditingValue(
        text: '- item',
        selection: TextSelection.collapsed(offset: 6),
      );

      final updated = indentMarkdownListDepth(value);

      expect(updated.text, '  - item');
      expect(updated.selection, const TextSelection.collapsed(offset: 8));
    });

    test('shift tab outdents current list line when possible', () {
      const value = TextEditingValue(
        text: '  - item',
        selection: TextSelection.collapsed(offset: 8),
      );

      final updated = outdentMarkdownListDepth(value);

      expect(updated.text, '- item');
      expect(updated.selection, const TextSelection.collapsed(offset: 6));
    });

    test('tab inserts spaces for non-list text', () {
      const value = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );

      final updated = indentMarkdownListDepth(value);

      expect(updated.text, 'hello  ');
      expect(updated.selection, const TextSelection.collapsed(offset: 7));
    });
  });
}
