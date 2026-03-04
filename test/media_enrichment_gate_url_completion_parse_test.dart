import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/media_enrichment/media_enrichment_gate.dart';

void main() {
  test('parseUrlEnrichmentPayloadForTest parses normalized payload', () {
    final raw = jsonEncode({
      'title': '  Qwen3-ASR  ',
      'summary': '  speech recognition toolkit  ',
      'tags': ['asr', 'ASR', 'speech'],
    });

    final parsed = parseUrlEnrichmentPayloadForTest(raw);
    expect(parsed, isNotNull);
    expect(parsed!.title, 'Qwen3-ASR');
    expect(parsed.summary, 'speech recognition toolkit');
    expect(parsed.tags, const ['asr', 'speech']);
  });

  test('parseUrlEnrichmentPayloadForTest rejects invalid payload', () {
    expect(parseUrlEnrichmentPayloadForTest('{}'), isNull);
    expect(parseUrlEnrichmentPayloadForTest('[]'), isNull);
    expect(parseUrlEnrichmentPayloadForTest('not json'), isNull);
  });
}
