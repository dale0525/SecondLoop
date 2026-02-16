import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/features/media_backup/video_kind_classifier.dart';

final class _VideoKindEvalSample {
  const _VideoKindEvalSample({
    required this.id,
    required this.language,
    required this.source,
    required this.expectedKind,
    required this.sourceMimeType,
    required this.filename,
    required this.ocrText,
    required this.languageHints,
  });

  final String id;
  final String language;
  final String source;
  final String expectedKind;
  final String sourceMimeType;
  final String filename;
  final String ocrText;
  final String languageHints;

  bool get usesOcr => source == 'ocr' && ocrText.trim().isNotEmpty;

  static _VideoKindEvalSample fromMap(Map<String, Object?> map) {
    String readString(String key) => (map[key] ?? '').toString().trim();

    return _VideoKindEvalSample(
      id: readString('id'),
      language: readString('language'),
      source: readString('source'),
      expectedKind: normalizeVideoKind(readString('expected_kind')),
      sourceMimeType: readString('source_mime_type'),
      filename: readString('filename'),
      ocrText: readString('ocr_text'),
      languageHints: readString('language_hints'),
    );
  }
}

void main() {
  test('multilingual offline baseline builds confusion matrix', () async {
    final samples =
        _loadEvalSamplesFromDirectory('test/data/video_kind_eval_samples');

    expect(samples.length, greaterThanOrEqualTo(100));

    final kinds = <String>{for (final sample in samples) sample.expectedKind};
    final matrix = <String, Map<String, int>>{};
    final languageTotals = <String, int>{};
    final languageCorrect = <String, int>{};

    var correct = 0;

    for (final sample in samples) {
      final predicted = await _predictSample(sample);
      final expected = sample.expectedKind;

      matrix
          .putIfAbsent(expected, () => <String, int>{})
          .update(predicted, (value) => value + 1, ifAbsent: () => 1);

      languageTotals.update(sample.language, (value) => value + 1,
          ifAbsent: () => 1);
      if (predicted == expected) {
        correct += 1;
        languageCorrect.update(sample.language, (value) => value + 1,
            ifAbsent: () => 1);
      }
    }

    final overallAccuracy = correct / samples.length;
    final macroF1 = _computeMacroF1(matrix, kinds);
    final minLanguageAccuracy = _computeMinLanguageAccuracy(
      languageTotals,
      languageCorrect,
    );

    final confusionMatrix = _formatConfusionMatrix(
        matrix, kinds.toList()..sort((a, b) => a.compareTo(b)));
    final perLanguageAccuracy = _formatPerLanguageAccuracy(
      languageTotals,
      languageCorrect,
    );

    // Ignore in normal pass output; useful when running this test by itself.
    // ignore: avoid_print
    print(
        'video_kind_offline_eval overall_accuracy=${overallAccuracy.toStringAsFixed(4)} '
        'macro_f1=${macroF1.toStringAsFixed(4)} '
        'min_language_accuracy=${minLanguageAccuracy.toStringAsFixed(4)}');
    // ignore: avoid_print
    print(confusionMatrix);
    // ignore: avoid_print
    print(perLanguageAccuracy);

    expect(overallAccuracy, greaterThanOrEqualTo(0.90));
    expect(macroF1, greaterThanOrEqualTo(0.88));
    expect(minLanguageAccuracy, greaterThanOrEqualTo(0.75));
  });
}

List<_VideoKindEvalSample> _loadEvalSamplesFromDirectory(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) {
    throw StateError('missing_eval_dataset_directory');
  }

  final files = directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList(growable: false)
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    throw StateError('missing_eval_dataset_files');
  }

  final samples = <_VideoKindEvalSample>[];

  for (final file in files) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw StateError('invalid_eval_payload');
    }

    final payload = Map<String, Object?>.from(decoded);
    final schema = (payload['schema'] ?? '').toString().trim();
    if (schema != 'secondloop.video_kind_eval.v1') {
      throw StateError('invalid_eval_schema');
    }

    final rawSamples = payload['samples'];
    if (rawSamples is! List<Object?>) {
      throw StateError('invalid_eval_samples');
    }

    for (final raw in rawSamples.whereType<Map<String, Object?>>()) {
      samples.add(_VideoKindEvalSample.fromMap(raw));
    }
  }

  return List<_VideoKindEvalSample>.unmodifiable(samples);
}

Future<String> _predictSample(_VideoKindEvalSample sample) async {
  final ocrText = sample.ocrText.trim();
  final withOcr = sample.usesOcr;

  final result = await classifyVideoKind(
    filename: sample.filename,
    sourceMimeType: sample.sourceMimeType,
    languageHints: sample.languageHints,
    posterBytes: withOcr ? Uint8List.fromList(const <int>[1, 2, 3]) : null,
    ocrImageFn: withOcr
        ? (bytes, {required languageHints}) async => PlatformPdfOcrResult(
              fullText: ocrText,
              excerpt: ocrText,
              engine: 'offline_eval_stub',
              isTruncated: false,
              pageCount: 1,
              processedPages: 1,
            )
        : null,
  );

  return normalizeVideoKind(result.kind);
}

double _computeMacroF1(
    Map<String, Map<String, int>> matrix, Set<String> kinds) {
  if (kinds.isEmpty) return 0;

  var totalF1 = 0.0;
  for (final kind in kinds) {
    final truePositive = matrix[kind]?[kind] ?? 0;

    var falsePositive = 0;
    for (final entry in matrix.entries) {
      if (entry.key == kind) continue;
      falsePositive += entry.value[kind] ?? 0;
    }

    final row = matrix[kind] ?? const <String, int>{};
    final rowTotal = row.values.fold<int>(0, (sum, value) => sum + value);
    final falseNegative = rowTotal - truePositive;

    final precisionDenominator = truePositive + falsePositive;
    final recallDenominator = truePositive + falseNegative;

    final precision =
        precisionDenominator <= 0 ? 0.0 : truePositive / precisionDenominator;
    final recall =
        recallDenominator <= 0 ? 0.0 : truePositive / recallDenominator;

    final f1 = (precision + recall) <= 0
        ? 0.0
        : (2 * precision * recall) / (precision + recall);
    totalF1 += f1;
  }

  return totalF1 / kinds.length;
}

double _computeMinLanguageAccuracy(
  Map<String, int> totals,
  Map<String, int> correct,
) {
  if (totals.isEmpty) return 0;

  double? minValue;
  for (final entry in totals.entries) {
    final hit = correct[entry.key] ?? 0;
    final accuracy = entry.value <= 0 ? 0.0 : hit / entry.value;
    if (minValue == null || accuracy < minValue) {
      minValue = accuracy;
    }
  }
  return minValue ?? 0;
}

String _formatConfusionMatrix(
  Map<String, Map<String, int>> matrix,
  List<String> kinds,
) {
  final buffer = StringBuffer();
  buffer.writeln('video_kind_offline_eval_confusion_matrix');
  buffer.writeln('expected\\predicted: ${kinds.join(', ')}');

  for (final expected in kinds) {
    final row = <String>[];
    final counts = matrix[expected] ?? const <String, int>{};
    for (final predicted in kinds) {
      row.add('${counts[predicted] ?? 0}');
    }
    buffer.writeln('$expected => ${row.join(', ')}');
  }

  return buffer.toString().trimRight();
}

String _formatPerLanguageAccuracy(
  Map<String, int> totals,
  Map<String, int> correct,
) {
  final languages = totals.keys.toList(growable: false)..sort();
  final parts = <String>[];

  for (final language in languages) {
    final total = totals[language] ?? 0;
    final hit = correct[language] ?? 0;
    final accuracy = total <= 0 ? 0.0 : hit / total;
    parts.add('$language=${accuracy.toStringAsFixed(3)}($hit/$total)');
  }

  return 'video_kind_offline_eval_language_accuracy ${parts.join(' | ')}';
}
