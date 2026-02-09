import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/content_enrichment/multimodal_ocr.dart';
import 'package:secondloop/src/rust/db.dart';

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
}
