import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/content_enrichment/multimodal_ocr.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));
  final pdfBytes = Uint8List.fromList(const <int>[1, 2, 3, 4]);

  test('tryConfiguredMultimodalPdfOcr chunks 25 pages into 10/10/5 windows',
      () async {
    final renderWindows = <String>[];
    var cloudCalls = 0;

    final result = await tryConfiguredMultimodalPdfOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      pdfBytes: pdfBytes,
      pageCountHint: 25,
      languageHints: 'device_plus_en',
      subscriptionStatus: SubscriptionStatus.entitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: true,
        providerMode: 'cloud_gateway',
      ),
      llmProfiles: const <LlmProfile>[],
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudIdToken: 'token',
      cloudModelName: 'gpt-4.1-mini',
      renderPdfToImage: (bytes,
          {preset = PlatformPdfRenderPreset.common}) async {
        renderWindows.add('${preset.startPage}/${preset.maxPages}');
        final start = preset.startPage;
        final remaining = (25 - start + 1).clamp(0, 10000).toInt();
        final processed =
            remaining > preset.maxPages ? preset.maxPages : remaining;
        return PlatformPdfRenderedImage(
          imageBytes: Uint8List.fromList(<int>[start]),
          mimeType: 'image/jpeg',
          pageCount: 25,
          processedPages: processed,
        );
      },
      tryCloudOcr: ({
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        cloudCalls += 1;
        return PlatformPdfOcrResult(
          fullText: 'chunk-$pageCountHint',
          excerpt: 'chunk-$pageCountHint',
          engine: 'multimodal_cloud_ocr_markdown:gpt-4.1-mini',
          isTruncated: false,
          pageCount: pageCountHint,
          processedPages: pageCountHint,
        );
      },
    );

    expect(renderWindows, <String>['1/10', '11/10', '21/5']);
    expect(cloudCalls, 3);
    expect(result, isNotNull);
    expect(result!.pageCount, 25);
    expect(result.processedPages, 25);
    expect(result.isTruncated, isFalse);
    expect(result.engine, 'multimodal_cloud_ocr_markdown:gpt-4.1-mini');
    expect(result.fullText, contains('[pages 1-10]'));
    expect(result.fullText, contains('[pages 11-20]'));
    expect(result.fullText, contains('[pages 21-25]'));
  });

  test('tryConfiguredMultimodalPdfOcr returns partial result with retry ranges',
      () async {
    final result = await tryConfiguredMultimodalPdfOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      pdfBytes: pdfBytes,
      pageCountHint: 25,
      languageHints: 'device_plus_en',
      subscriptionStatus: SubscriptionStatus.entitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: true,
        providerMode: 'cloud_gateway',
      ),
      llmProfiles: const <LlmProfile>[],
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudIdToken: 'token',
      cloudModelName: 'gpt-4.1-mini',
      renderPdfToImage: (bytes,
          {preset = PlatformPdfRenderPreset.common}) async {
        final start = preset.startPage;
        final remaining = (25 - start + 1).clamp(0, 10000).toInt();
        final processed =
            remaining > preset.maxPages ? preset.maxPages : remaining;
        return PlatformPdfRenderedImage(
          imageBytes: Uint8List.fromList(<int>[start]),
          mimeType: 'image/jpeg',
          pageCount: 25,
          processedPages: processed,
        );
      },
      tryCloudOcr: ({
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        if (mediaBytes.first == 11) {
          return null;
        }
        return PlatformPdfOcrResult(
          fullText: 'ok-${mediaBytes.first}',
          excerpt: 'ok-${mediaBytes.first}',
          engine: 'multimodal_cloud_ocr_markdown:gpt-4.1-mini',
          isTruncated: false,
          pageCount: pageCountHint,
          processedPages: pageCountHint,
        );
      },
    );

    expect(result, isNotNull);
    expect(result!.pageCount, 25);
    expect(result.processedPages, 15);
    expect(result.isTruncated, isTrue);
    expect(result.engine, contains('+partial'));
    expect(
      result.failedRanges,
      <Map<String, int>>[
        {'start_page': 11, 'end_page': 20},
      ],
    );
    expect(result.completedRanges.length, 2);
  });

  test('tryConfiguredMultimodalPdfOcr returns null when all chunks fail',
      () async {
    final result = await tryConfiguredMultimodalPdfOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      pdfBytes: pdfBytes,
      pageCountHint: 25,
      languageHints: 'device_plus_en',
      subscriptionStatus: SubscriptionStatus.entitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: true,
        providerMode: 'cloud_gateway',
      ),
      llmProfiles: const <LlmProfile>[],
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudIdToken: 'token',
      cloudModelName: 'gpt-4.1-mini',
      renderPdfToImage: (bytes,
          {preset = PlatformPdfRenderPreset.common}) async {
        final start = preset.startPage;
        final remaining = (25 - start + 1).clamp(0, 10000).toInt();
        final processed =
            remaining > preset.maxPages ? preset.maxPages : remaining;
        return PlatformPdfRenderedImage(
          imageBytes: Uint8List.fromList(<int>[start]),
          mimeType: 'image/jpeg',
          pageCount: 25,
          processedPages: processed,
        );
      },
      tryCloudOcr: ({
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        return null;
      },
    );

    expect(result, isNull);
  });
}

final class _NoopNativeBackend extends NativeAppBackend {
  _NoopNativeBackend() : super(appDirProvider: () async => '/tmp/secondloop');
}
