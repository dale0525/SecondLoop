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

  test('inferVideoContentKind returns knowledge for dense transcript content',
      () {
    final transcript =
        List<String>.filled(40, 'topic insight and key takeaways').join(' ');

    expect(
      inferVideoContentKind(
        transcriptFull: transcript,
        ocrTextFull: '',
        readableTextFull: transcript,
      ),
      'knowledge',
    );
  });

  test('inferVideoContentKind returns non_knowledge for short narrative', () {
    const readable = 'A short travel vlog with walking scenes and city views.';

    expect(
      inferVideoContentKind(
        transcriptFull: '',
        ocrTextFull: '',
        readableTextFull: readable,
      ),
      'non_knowledge',
    );
  });

  test(
      'inferVideoContentKind returns knowledge for short structured tutorial notes',
      () {
    const readable =
        'Step 1: Install ffmpeg\nStep 2: Extract audio\nStep 3: Summarize key points\nConclusion: Keep segments under 20 minutes.';

    expect(
      inferVideoContentKind(
        transcriptFull: '',
        ocrTextFull: '',
        readableTextFull: readable,
      ),
      'knowledge',
    );
  });

  test(
      'inferVideoContentKind returns knowledge for structured Chinese tutorial',
      () {
    const readable = '教程要点：\n第一步：导入素材\n第二步：识别字幕\n第三步：整理知识点\n总结：输出 Markdown 笔记';

    expect(
      inferVideoContentKind(
        transcriptFull: '',
        ocrTextFull: '',
        readableTextFull: readable,
      ),
      'knowledge',
    );
  });

  test('inferVideoContentKind returns unknown for very short ambiguous text',
      () {
    expect(
      inferVideoContentKind(
        transcriptFull: '',
        ocrTextFull: '',
        readableTextFull: 'Nice!',
      ),
      'unknown',
    );
  });

  test('inferVideoContentKind returns unknown when readable text is empty', () {
    expect(
      inferVideoContentKind(
        transcriptFull: '',
        ocrTextFull: '',
        readableTextFull: '',
      ),
      'unknown',
    );
  });

  test('buildVideoSummaryText trims and utf8-truncates output', () {
    final source = ('  这是一个视频总结。' * 300).trim();

    final summary = buildVideoSummaryText(source, maxBytes: 120);

    expect(summary.isNotEmpty, isTrue);
    expect(summary.length < source.length, isTrue);
    expect(summary.trim(), summary);
  });
}
