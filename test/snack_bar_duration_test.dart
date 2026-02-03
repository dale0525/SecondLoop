import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('All SnackBar durations are <= 3 seconds', () {
    final offenders = <String>[];
    for (final file in _dartFilesUnder('lib')) {
      final content = File(file).readAsStringSync();
      for (final snack in _snackBarConstructorCalls(content)) {
        final duration = _parseDurationLiteral(snack);
        if (duration == null) {
          offenders.add('$file: SnackBar missing duration');
          continue;
        }
        if (duration > const Duration(seconds: 3)) {
          offenders.add('$file: SnackBar duration too long ($duration)');
        }
      }
    }

    if (offenders.isNotEmpty) {
      fail(offenders.join('\n'));
    }
  });
}

Iterable<String> _dartFilesUnder(String root) sync* {
  for (final entry in Directory(root).listSync(recursive: true)) {
    if (entry is! File) continue;
    if (!entry.path.endsWith('.dart')) continue;
    yield entry.path;
  }
}

Iterable<String> _snackBarConstructorCalls(String source) sync* {
  final re = RegExp(r'\bSnackBar\s*\(');
  for (final match in re.allMatches(source)) {
    final openParenIndex = match.end - 1;
    if (openParenIndex < 0) continue;
    final endIndex = _findMatchingParen(source, openParenIndex);
    if (endIndex == null) continue;
    yield source.substring(match.start, endIndex + 1);
  }
}

int? _findMatchingParen(String source, int openParenIndex) {
  var depth = 0;
  var i = openParenIndex;
  while (i < source.length) {
    final char = source[i];

    if (char == '/' && i + 1 < source.length) {
      final next = source[i + 1];
      if (next == '/') {
        i = _skipLineComment(source, i);
        continue;
      }
      if (next == '*') {
        i = _skipBlockComment(source, i);
        continue;
      }
    }

    if (char == '"' || char == '\'') {
      i = _skipStringLiteral(source, i);
      continue;
    }

    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) {
        return i;
      }
    }

    i++;
  }

  return null;
}

int _skipLineComment(String source, int index) {
  var i = index + 2;
  while (i < source.length && source[i] != '\n') {
    i++;
  }
  return i;
}

int _skipBlockComment(String source, int index) {
  var i = index + 2;
  while (i + 1 < source.length) {
    if (source[i] == '*' && source[i + 1] == '/') {
      return i + 2;
    }
    i++;
  }
  return source.length;
}

int _skipStringLiteral(String source, int quoteIndex) {
  final quote = source[quoteIndex];
  final isTriple = quoteIndex + 2 < source.length &&
      source[quoteIndex + 1] == quote &&
      source[quoteIndex + 2] == quote;
  if (isTriple) {
    var i = quoteIndex + 3;
    while (i + 2 < source.length) {
      if (source[i] == quote &&
          source[i + 1] == quote &&
          source[i + 2] == quote) {
        return i + 3;
      }
      i++;
    }
    return source.length;
  }

  var i = quoteIndex + 1;
  while (i < source.length) {
    final char = source[i];
    if (char == '\\\\') {
      i += 2;
      continue;
    }
    if (char == quote) {
      return i + 1;
    }
    i++;
  }
  return source.length;
}

Duration? _parseDurationLiteral(String snackBarConstructorCall) {
  final secondsMatch = RegExp(
    r'duration\s*:\s*(?:const\s*)?Duration\s*\(\s*seconds\s*:\s*(\d+)\s*\)',
  ).firstMatch(snackBarConstructorCall);
  if (secondsMatch != null) {
    return Duration(seconds: int.parse(secondsMatch.group(1)!));
  }

  final millisMatch = RegExp(
    r'duration\s*:\s*(?:const\s*)?Duration\s*\(\s*milliseconds\s*:\s*(\d+)\s*\)',
  ).firstMatch(snackBarConstructorCall);
  if (millisMatch != null) {
    return Duration(milliseconds: int.parse(millisMatch.group(1)!));
  }

  return null;
}
