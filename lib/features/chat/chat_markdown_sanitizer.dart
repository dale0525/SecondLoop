import 'dart:convert';

final _fencedCodeBlockMarker = RegExp(r'^\s{0,3}(```|~~~)');
final _leadingIndent = RegExp(r'^(?:\t| {4,})');

/// Sanitizes chat markdown to avoid accidental indented code blocks.
///
/// In chat logs we frequently render plain text as Markdown. A line that starts
/// with 4+ spaces (or a tab) after a blank line is interpreted as an indented
/// code block by the Markdown parser, which can cause confusing bubble UI
/// (monospace + shaded background) when indentation is accidental.
///
/// This keeps fenced code blocks (```/~~~), but trims leading indentation from
/// lines that would start an indented code block.
String sanitizeChatMarkdown(String input) {
  final lines = const LineSplitter().convert(input);
  if (lines.isEmpty) return input;

  final output = <String>[];
  var inFencedCodeBlock = false;
  String? fenceMarker;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    final fence = _fencedCodeBlockMarker.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      if (!inFencedCodeBlock) {
        inFencedCodeBlock = true;
        fenceMarker = marker;
      } else if (marker == fenceMarker) {
        inFencedCodeBlock = false;
        fenceMarker = null;
      }
      output.add(line);
      continue;
    }

    if (!inFencedCodeBlock) {
      final shouldPreventIndentedCodeBlock = _leadingIndent.hasMatch(line) &&
          (i == 0 || lines[i - 1].trim().isEmpty);
      output.add(shouldPreventIndentedCodeBlock ? line.trimLeft() : line);
    } else {
      output.add(line);
    }
  }

  return output.join('\n');
}
