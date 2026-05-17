import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/content_enrichment/multimodal_ocr.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  test('Pro cloud mode prefers multimodal OCR even when local mode stored', () {
    final result = shouldAttemptMultimodalPdfOcr(
      ocrEngineMode: 'platform_native',
      subscriptionStatus: SubscriptionStatus.entitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: false,
        providerMode: 'cloud_gateway',
      ),
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudIdToken: 'token',
    );

    expect(result, isTrue);
  });

  test('Pro subscription uses cloud multimodal regardless provider mode', () {
    final result = shouldAttemptMultimodalPdfOcr(
      ocrEngineMode: 'platform_native',
      subscriptionStatus: SubscriptionStatus.entitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: false,
        providerMode: 'follow_ask_ai',
      ),
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudIdToken: 'token',
    );

    expect(result, isTrue);
  });

  test('Without cloud token, local mode does not force multimodal OCR', () {
    final result = shouldAttemptMultimodalPdfOcr(
      ocrEngineMode: 'platform_native',
      subscriptionStatus: SubscriptionStatus.entitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: false,
        providerMode: 'cloud_gateway',
      ),
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudIdToken: '',
    );

    expect(result, isFalse);
  });

  test('BYOK multimodal setting still enables multimodal OCR', () {
    final result = shouldAttemptMultimodalPdfOcr(
      ocrEngineMode: 'multimodal_llm',
      subscriptionStatus: SubscriptionStatus.notEntitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: false,
        providerMode: 'follow_ask_ai',
      ),
      cloudGatewayBaseUrl: '',
      cloudIdToken: '',
    );

    expect(result, isTrue);
  });

  test('without cloud and BYOK providers returns null for runtime fallback',
      () async {
    final result = await tryConfiguredMultimodalPdfOcr(
      backend: _NoopNativeBackend(),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      pdfBytes: Uint8List.fromList(const <int>[1, 2, 3]),
      pageCountHint: 25,
      languageHints: 'device_plus_en',
      subscriptionStatus: SubscriptionStatus.notEntitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: true,
        providerMode: 'follow_ask_ai',
      ),
      llmProfiles: const <LlmProfile>[],
      cloudGatewayBaseUrl: '',
      cloudIdToken: '',
      cloudModelName: 'unused',
      renderPdfToImage: (bytes,
          {preset = PlatformPdfRenderPreset.common}) async {
        final remaining = (25 - preset.startPage + 1).clamp(0, 10000).toInt();
        final processed =
            remaining > preset.maxPages ? preset.maxPages : remaining;
        return PlatformPdfRenderedImage(
          imageBytes: Uint8List.fromList(<int>[preset.startPage]),
          mimeType: 'image/jpeg',
          pageCount: 25,
          processedPages: processed,
        );
      },
    );

    expect(result, isNull);
  });
}

final class _NoopNativeBackend extends NativeAppBackend {
  _NoopNativeBackend() : super(appDirProvider: () async => '/tmp/secondloop');
}
