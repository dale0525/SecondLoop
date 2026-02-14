import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/content_enrichment/video_ocr_auto_policy.dart';

void main() {
  test('shouldAutoRunVideoManifestOcr allows unresolved video extract payload',
      () {
    final payload = <String, Object?>{
      'schema': 'secondloop.video_extract.v1',
      'mime_type': 'application/x.secondloop.video+json',
      'needs_ocr': true,
    };

    expect(shouldAutoRunVideoManifestOcr(payload), isTrue);
  });

  test('shouldAutoRunVideoManifestOcr skips when OCR engine already exists',
      () {
    final payload = <String, Object?>{
      'schema': 'secondloop.video_extract.v1',
      'mime_type': 'application/x.secondloop.video+json',
      'needs_ocr': true,
      'ocr_engine': 'apple_vision',
    };

    expect(shouldAutoRunVideoManifestOcr(payload), isFalse);
  });

  test('shouldAutoRunVideoManifestOcr skips when needs_ocr is false', () {
    final payload = <String, Object?>{
      'schema': 'secondloop.video_extract.v1',
      'mime_type': 'application/x.secondloop.video+json',
      'needs_ocr': false,
    };

    expect(shouldAutoRunVideoManifestOcr(payload), isFalse);
  });

  test('shouldAutoRunVideoManifestOcr skips when auto OCR is running recently',
      () {
    const nowMs = 1760000000000;
    final payload = <String, Object?>{
      'schema': 'secondloop.video_extract.v1',
      'mime_type': 'application/x.secondloop.video+json',
      'needs_ocr': true,
      'ocr_auto_status': 'running',
      'ocr_auto_running_ms': nowMs - 60 * 1000,
    };

    expect(
      shouldAutoRunVideoManifestOcr(payload, nowMs: nowMs),
      isFalse,
    );
  });

  test('shouldAutoRunVideoManifestOcr retries when running state is stale', () {
    const nowMs = 1760000000000;
    final payload = <String, Object?>{
      'schema': 'secondloop.video_extract.v1',
      'mime_type': 'application/x.secondloop.video+json',
      'needs_ocr': true,
      'ocr_auto_status': 'running',
      'ocr_auto_running_ms': nowMs - 5 * 60 * 1000,
    };

    expect(
      shouldAutoRunVideoManifestOcr(payload, nowMs: nowMs),
      isTrue,
    );
  });

  test('shouldAutoRunVideoManifestOcr respects failure cooldown', () {
    const nowMs = 1760000000000;
    final payload = <String, Object?>{
      'schema': 'secondloop.video_extract.v1',
      'mime_type': 'application/x.secondloop.video+json',
      'needs_ocr': true,
      'ocr_auto_status': 'failed',
      'ocr_auto_last_failure_ms': nowMs - 30 * 1000,
    };

    expect(
      shouldAutoRunVideoManifestOcr(payload, nowMs: nowMs),
      isFalse,
    );
  });
}
