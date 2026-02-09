import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/content_enrichment/multimodal_ocr.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
  final pdfBytes = Uint8List.fromList(const <int>[1, 2, 3, 4, 5]);
  final renderedBytes = Uint8List.fromList(const <int>[9, 8, 7, 6]);

  test('cloud failure falls back to BYOK with locally rendered image',
      () async {
    var cloudCalls = 0;
    var byokCalls = 0;

    final result = await tryConfiguredMultimodalPdfOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      pdfBytes: pdfBytes,
      pageCountHint: 6,
      languageHints: 'device_plus_en',
      subscriptionStatus: SubscriptionStatus.entitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: true,
        providerMode: 'cloud_gateway',
      ),
      llmProfiles: const <LlmProfile>[
        LlmProfile(
          id: 'p1',
          name: 'BYOK',
          providerType: 'openai-compatible',
          baseUrl: 'https://example.com',
          modelName: 'gpt-4.1-mini',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        )
      ],
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudIdToken: 'token',
      cloudModelName: 'cloud-ocr-model',
      renderPdfToImage: (bytes,
          {preset = PlatformPdfRenderPreset.common}) async {
        expect(bytes, pdfBytes);
        expect(preset.id, kCommonPdfOcrModelPreset);
        expect(preset.maxPages, 10000);
        expect(preset.dpi, 180);
        return PlatformPdfRenderedImage(
          imageBytes: renderedBytes,
          mimeType: 'image/jpeg',
          pageCount: 6,
          processedPages: 6,
        );
      },
      tryCloudOcr: ({
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        cloudCalls += 1;
        expect(mimeType, 'image/jpeg');
        expect(mediaBytes, renderedBytes);
        expect(pageCountHint, 6);
        throw StateError('cloud failed');
      },
      tryByokOcr: ({
        required profileId,
        required modelName,
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        byokCalls += 1;
        expect(profileId, 'p1');
        expect(modelName, 'gpt-4.1-mini');
        expect(mimeType, 'image/jpeg');
        expect(mediaBytes, renderedBytes);
        expect(pageCountHint, 6);
        return const PlatformPdfOcrResult(
          fullText: 'hello',
          excerpt: 'hello',
          engine: 'multimodal_byok_ocr_markdown:gpt-4.1-mini',
          isTruncated: false,
          pageCount: 6,
          processedPages: 6,
        );
      },
    );

    expect(cloudCalls, 1);
    expect(byokCalls, 1);
    expect(result, isNotNull);
    expect(result!.engine, 'multimodal_byok_ocr_markdown:gpt-4.1-mini');
  });

  test('BYOK failure returns null for runtime/native fallback', () async {
    var cloudCalls = 0;
    var byokCalls = 0;

    final result = await tryConfiguredMultimodalPdfOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      pdfBytes: pdfBytes,
      pageCountHint: 3,
      languageHints: 'device_plus_en',
      subscriptionStatus: SubscriptionStatus.notEntitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: true,
        providerMode: 'follow_ask_ai',
      ),
      llmProfiles: const <LlmProfile>[
        LlmProfile(
          id: 'p1',
          name: 'BYOK',
          providerType: 'openai-compatible',
          baseUrl: 'https://example.com',
          modelName: 'gpt-4.1-mini',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        )
      ],
      cloudGatewayBaseUrl: '',
      cloudIdToken: '',
      cloudModelName: 'unused',
      renderPdfToImage: (bytes,
          {preset = PlatformPdfRenderPreset.common}) async {
        expect(preset.id, kCommonPdfOcrModelPreset);
        return PlatformPdfRenderedImage(
          imageBytes: renderedBytes,
          mimeType: 'image/jpeg',
          pageCount: 3,
          processedPages: 3,
        );
      },
      tryCloudOcr: ({
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        cloudCalls += 1;
        return null;
      },
      tryByokOcr: ({
        required profileId,
        required modelName,
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        byokCalls += 1;
        throw StateError('byok failed');
      },
    );

    expect(result, isNull);
    expect(cloudCalls, 0);
    expect(byokCalls, 1);
  });

  test('render failure skips cloud and BYOK multimodal attempts', () async {
    var cloudCalls = 0;
    var byokCalls = 0;

    final result = await tryConfiguredMultimodalPdfOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      pdfBytes: pdfBytes,
      pageCountHint: 2,
      languageHints: 'device_plus_en',
      subscriptionStatus: SubscriptionStatus.entitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: true,
        providerMode: 'cloud_gateway',
      ),
      llmProfiles: const <LlmProfile>[
        LlmProfile(
          id: 'p1',
          name: 'BYOK',
          providerType: 'openai-compatible',
          baseUrl: 'https://example.com',
          modelName: 'gpt-4.1-mini',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        )
      ],
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudIdToken: 'token',
      cloudModelName: 'cloud-ocr-model',
      renderPdfToImage:
          (bytes, {preset = PlatformPdfRenderPreset.common}) async => null,
      tryCloudOcr: ({
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        cloudCalls += 1;
        return null;
      },
      tryByokOcr: ({
        required profileId,
        required modelName,
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        byokCalls += 1;
        return null;
      },
    );

    expect(result, isNull);
    expect(cloudCalls, 0);
    expect(byokCalls, 0);
  });
}

final class _NoopNativeBackend extends NativeAppBackend {
  _NoopNativeBackend() : super(appDirProvider: () async => '/tmp/secondloop');
}
