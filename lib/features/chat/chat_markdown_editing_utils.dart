import 'package:flutter/services.dart';

TextEditingValue applyMarkdownInlineWrap(
  TextEditingValue value, {
  required String prefix,
  String? suffix,
  String placeholder = 'text',
}) {
  final markerSuffix = suffix ?? prefix;
  final range = _normalizedSelection(value.selection, value.text.length);
  final selected = value.text.substring(range.start, range.end);
  final hasSelection = range.start != range.end;
  final payload = hasSelection ? selected : placeholder;
  final replacement = '$prefix$payload$markerSuffix';
  final nextText = value.text.replaceRange(range.start, range.end, replacement);

  final nextSelection = hasSelection
      ? TextSelection(
          baseOffset: range.start + prefix.length,
          extentOffset: range.start + prefix.length + selected.length,
        )
      : TextSelection(
          baseOffset: range.start + prefix.length,
          extentOffset: range.start + prefix.length + placeholder.length,
        );

  return value.copyWith(
    text: nextText,
    selection: nextSelection,
    composing: TextRange.empty,
  );
}

TextEditingValue applyMarkdownCodeBlock(
  TextEditingValue value, {
  String language = '',
}) {
  final range = _normalizedSelection(value.selection, value.text.length);
  final selected = value.text.substring(range.start, range.end);
  final hasSelection = range.start != range.end;
  final code = hasSelection ? selected : 'code';
  final marker = language.trim().isEmpty ? '```' : '```${language.trim()}';
  final replacement = '$marker\n$code\n```';
  final nextText = value.text.replaceRange(range.start, range.end, replacement);

  final nextSelection = hasSelection
      ? TextSelection(
          baseOffset: range.start + marker.length + 1,
          extentOffset: range.start + marker.length + 1 + selected.length,
        )
      : TextSelection(
          baseOffset: range.start + marker.length + 1,
          extentOffset: range.start + marker.length + 1 + code.length,
        );

  return value.copyWith(
    text: nextText,
    selection: nextSelection,
    composing: TextRange.empty,
  );
}

TextEditingValue applyMarkdownLink(TextEditingValue value) {
  final range = _normalizedSelection(value.selection, value.text.length);
  final selected = value.text.substring(range.start, range.end);
  final hasSelection = range.start != range.end;
  final label = hasSelection ? selected : 'link text';
  const url = 'https://';
  final replacement = '[$label]($url)';
  final nextText = value.text.replaceRange(range.start, range.end, replacement);

  final nextSelection = hasSelection
      ? TextSelection(
          baseOffset: range.start + label.length + 3,
          extentOffset: range.start + label.length + 3 + url.length,
        )
      : TextSelection(
          baseOffset: range.start + 1,
          extentOffset: range.start + 1 + label.length,
        );

  return value.copyWith(
    text: nextText,
    selection: nextSelection,
    composing: TextRange.empty,
  );
}

TextEditingValue applyMarkdownHeading(
  TextEditingValue value, {
  required int level,
}) {
  final text = value.text;
  final range = _normalizedSelection(value.selection, text.length);
  final safeLevel = level.clamp(1, 6);
  final marker = '${'#' * safeLevel} ';

  final lineStart = _lineStartOf(text, range.start);
  final lineEnd = _lineEndOf(text, range.end);
  final line = text.substring(lineStart, lineEnd);

  final leading = RegExp(r'^\s*').stringMatch(line) ?? '';
  final trimmedLeading = line.substring(leading.length);
  final oldHeading = RegExp(r'^(#{1,6}\s*)').firstMatch(trimmedLeading);
  final oldMarkerLength = oldHeading?.group(1)?.length ?? 0;
  final content = oldHeading == null
      ? trimmedLeading
      : trimmedLeading.substring(oldMarkerLength);

  final nextLine = '$leading$marker${content.trimLeft()}';
  final nextText = text.replaceRange(lineStart, lineEnd, nextLine);

  if (!range.isCollapsed) {
    return value.copyWith(
      text: nextText,
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + nextLine.length,
      ),
      composing: TextRange.empty,
    );
  }

  final oldPrefixLength = leading.length + oldMarkerLength;
  final newPrefixLength = leading.length + marker.length;
  final relativeOffset = range.start - lineStart;
  final nextRelativeOffset = relativeOffset <= oldPrefixLength
      ? newPrefixLength
      : relativeOffset - oldPrefixLength + newPrefixLength;
  final nextOffset = (lineStart + nextRelativeOffset).clamp(
    lineStart,
    lineStart + nextLine.length,
  );

  return value.copyWith(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
    composing: TextRange.empty,
  );
}

TextEditingValue applyMarkdownBlockquote(TextEditingValue value) {
  return _togglePrefixOnSelectedLines(
    value,
    marker: '> ',
    existingPattern: RegExp(r'^\s*>\s+'),
  );
}

TextEditingValue toggleMarkdownUnorderedList(TextEditingValue value) {
  return _togglePrefixOnSelectedLines(
    value,
    marker: '- ',
    existingPattern: RegExp(r'^\s*[-+*]\s+'),
  );
}

TextEditingValue toggleMarkdownOrderedList(TextEditingValue value) {
  final range = _selectedLineRange(value.text, value.selection);
  final section = value.text.substring(range.start, range.end);
  final lines = section.split('\n');
  final pattern = RegExp(r'^\s*\d+[.)]\s+');
  final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).toList();
  final shouldRemove =
      nonEmptyLines.isNotEmpty && nonEmptyLines.every(pattern.hasMatch);

  var number = 1;
  final nextLines = lines.map((line) {
    if (line.trim().isEmpty) return line;
    if (shouldRemove) {
      return line.replaceFirst(pattern, '');
    }
    final leading = RegExp(r'^\s*').stringMatch(line) ?? '';
    final content = line.substring(leading.length).replaceFirst(pattern, '');
    final formatted = '$leading$number. $content';
    number += 1;
    return formatted;
  }).toList();

  final replacement = nextLines.join('\n');
  final nextText = value.text.replaceRange(range.start, range.end, replacement);

  return value.copyWith(
    text: nextText,
    selection: TextSelection(
      baseOffset: range.start,
      extentOffset: range.start + replacement.length,
    ),
    composing: TextRange.empty,
  );
}

TextEditingValue toggleMarkdownTaskList(TextEditingValue value) {
  return _togglePrefixOnSelectedLines(
    value,
    marker: '- [ ] ',
    existingPattern: RegExp(r'^\s*[-+*]\s+\[(?: |x|X)\]\s+'),
  );
}

TextEditingValue _togglePrefixOnSelectedLines(
  TextEditingValue value, {
  required String marker,
  required RegExp existingPattern,
}) {
  final range = _selectedLineRange(value.text, value.selection);
  final section = value.text.substring(range.start, range.end);
  final lines = section.split('\n');
  final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).toList();
  final shouldRemove =
      nonEmptyLines.isNotEmpty && nonEmptyLines.every(existingPattern.hasMatch);

  final nextLines = lines.map((line) {
    if (line.trim().isEmpty) return line;
    if (shouldRemove) {
      return line.replaceFirst(existingPattern, '');
    }
    final leading = RegExp(r'^\s*').stringMatch(line) ?? '';
    return '$leading$marker${line.substring(leading.length)}';
  }).toList();

  final replacement = nextLines.join('\n');
  final nextText = value.text.replaceRange(range.start, range.end, replacement);

  return value.copyWith(
    text: nextText,
    selection: TextSelection(
      baseOffset: range.start,
      extentOffset: range.start + replacement.length,
    ),
    composing: TextRange.empty,
  );
}

class MarkdownSmartContinuationFormatter extends TextInputFormatter {
  const MarkdownSmartContinuationFormatter();

  static final RegExp _taskPattern =
      RegExp(r'^(\s*)([-+*])\s+\[( |x|X)\]\s*(.*)$');
  static final RegExp _unorderedPattern = RegExp(r'^(\s*)([-+*])\s*(.*)$');
  static final RegExp _orderedPattern = RegExp(r'^(\s*)(\d+)([.)])\s*(.*)$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid ||
        !newValue.selection.isValid ||
        !oldValue.selection.isCollapsed ||
        !newValue.selection.isCollapsed) {
      return newValue;
    }

    final insertStart = oldValue.selection.baseOffset;
    final insertEnd = newValue.selection.baseOffset;
    if (insertStart < 0 ||
        insertEnd <= insertStart ||
        insertEnd > newValue.text.length) {
      return newValue;
    }

    final inserted = newValue.text.substring(insertStart, insertEnd);
    if (inserted != '\n') return newValue;

    final lineStart = _lineStartOf(oldValue.text, insertStart);
    final previousLine = oldValue.text.substring(lineStart, insertStart);

    final taskMatch = _taskPattern.firstMatch(previousLine);
    if (taskMatch != null) {
      final indent = taskMatch.group(1)!;
      final bullet = taskMatch.group(2)!;
      final content = taskMatch.group(4) ?? '';
      if (content.trim().isEmpty) {
        return _removeListMarker(
          newValue,
          lineStart: lineStart,
          insertEnd: insertEnd,
          indent: indent,
        );
      }
      return _insertContinuation(
        newValue,
        insertStart: insertStart,
        insertEnd: insertEnd,
        prefix: '$indent$bullet [ ] ',
      );
    }

    final unorderedMatch = _unorderedPattern.firstMatch(previousLine);
    if (unorderedMatch != null) {
      final indent = unorderedMatch.group(1)!;
      final bullet = unorderedMatch.group(2)!;
      final content = unorderedMatch.group(3) ?? '';
      if (content.trim().isEmpty) {
        return _removeListMarker(
          newValue,
          lineStart: lineStart,
          insertEnd: insertEnd,
          indent: indent,
        );
      }
      return _insertContinuation(
        newValue,
        insertStart: insertStart,
        insertEnd: insertEnd,
        prefix: '$indent$bullet ',
      );
    }

    final orderedMatch = _orderedPattern.firstMatch(previousLine);
    if (orderedMatch != null) {
      final indent = orderedMatch.group(1)!;
      final number = int.tryParse(orderedMatch.group(2) ?? '1') ?? 1;
      final delimiter = orderedMatch.group(3)!;
      final content = orderedMatch.group(4) ?? '';
      if (content.trim().isEmpty) {
        return _removeListMarker(
          newValue,
          lineStart: lineStart,
          insertEnd: insertEnd,
          indent: indent,
        );
      }
      return _insertContinuation(
        newValue,
        insertStart: insertStart,
        insertEnd: insertEnd,
        prefix: '$indent${number + 1}$delimiter ',
      );
    }

    return newValue;
  }

  TextEditingValue _insertContinuation(
    TextEditingValue value, {
    required int insertStart,
    required int insertEnd,
    required String prefix,
  }) {
    final replacement = '\n$prefix';
    final nextText =
        value.text.replaceRange(insertStart, insertEnd, replacement);
    return value.copyWith(
      text: nextText,
      selection:
          TextSelection.collapsed(offset: insertStart + replacement.length),
      composing: TextRange.empty,
    );
  }

  TextEditingValue _removeListMarker(
    TextEditingValue value, {
    required int lineStart,
    required int insertEnd,
    required String indent,
  }) {
    final replacement = '$indent\n';
    final nextText = value.text.replaceRange(lineStart, insertEnd, replacement);
    return value.copyWith(
      text: nextText,
      selection:
          TextSelection.collapsed(offset: lineStart + replacement.length),
      composing: TextRange.empty,
    );
  }
}

({int start, int end}) _selectedLineRange(
    String text, TextSelection selection) {
  final range = _normalizedSelection(selection, text.length);
  final start = _lineStartOf(text, range.start);
  final end = _lineEndOf(text, range.end);
  return (start: start, end: end);
}

int _lineStartOf(String text, int offset) {
  final safeOffset = offset.clamp(0, text.length);
  final idx = text.lastIndexOf('\n', safeOffset - 1);
  return idx == -1 ? 0 : idx + 1;
}

int _lineEndOf(String text, int offset) {
  final safeOffset = offset.clamp(0, text.length);
  final idx = text.indexOf('\n', safeOffset);
  return idx == -1 ? text.length : idx;
}

({int start, int end, bool isCollapsed}) _normalizedSelection(
  TextSelection selection,
  int textLength,
) {
  final valid = selection.isValid
      ? selection
      : TextSelection.collapsed(offset: textLength);
  final start = valid.start.clamp(0, textLength);
  final end = valid.end.clamp(0, textLength);
  return (
    start: start < end ? start : end,
    end: start < end ? end : start,
    isCollapsed: start == end,
  );
}
