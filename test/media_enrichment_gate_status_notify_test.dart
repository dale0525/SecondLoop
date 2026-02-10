import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/media_enrichment/media_enrichment_gate.dart';

void main() {
  test('notify when auto OCR enters running state', () {
    final shouldNotify = shouldNotifyAutoPdfOcrStatusTransition(
      previousPayload: const <String, Object?>{},
      nextPayload: const <String, Object?>{
        'ocr_auto_status': 'running',
      },
    );

    expect(shouldNotify, isTrue);
  });

  test('does not notify when auto OCR stays running', () {
    final shouldNotify = shouldNotifyAutoPdfOcrStatusTransition(
      previousPayload: const <String, Object?>{
        'ocr_auto_status': 'running',
      },
      nextPayload: const <String, Object?>{
        'ocr_auto_status': 'running',
      },
    );

    expect(shouldNotify, isFalse);
  });

  test('notify when auto OCR leaves running', () {
    final shouldNotify = shouldNotifyAutoPdfOcrStatusTransition(
      previousPayload: const <String, Object?>{
        'ocr_auto_status': 'running',
      },
      nextPayload: const <String, Object?>{
        'ocr_auto_status': 'ok',
      },
    );

    expect(shouldNotify, isTrue);
  });
}
