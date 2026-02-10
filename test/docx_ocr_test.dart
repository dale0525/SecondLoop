import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/content_enrichment/docx_ocr.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));

  test('tryConfiguredDocxOcr falls back from cloud to BYOK', () async {
    final docxBytes = _buildDocx(<String, List<int>>{
      'word/media/image1.png': List<int>.filled(64, 9),
    });
    var cloudCalls = 0;
    var byokCalls = 0;
    var runtimeCalls = 0;

    final result = await tryConfiguredDocxOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      docxBytes: docxBytes,
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
      cloudModelName: 'cloud-model',
      tryCloudOcr: ({
        required mimeType,
        required mediaBytes,
        required pageCountHint,
      }) async {
        cloudCalls += 1;
        expect(mimeType, 'image/png');
        expect(mediaBytes, hasLength(64));
        expect(pageCountHint, 2);
        throw StateError('cloud_unavailable');
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
        expect(mimeType, 'image/png');
        expect(mediaBytes, hasLength(64));
        expect(pageCountHint, 2);
        return const PlatformPdfOcrResult(
          fullText: 'docx byok ocr',
          excerpt: 'docx byok ocr',
          engine: 'multimodal_byok_ocr_markdown:gpt-4.1-mini',
          isTruncated: false,
          pageCount: 2,
          processedPages: 2,
        );
      },
      tryRuntimeOrNativeImageOcr: (bytes, {required languageHints}) async {
        runtimeCalls += 1;
        return null;
      },
    );

    expect(result, isNotNull);
    expect(result!.engine, 'multimodal_byok_ocr_markdown:gpt-4.1-mini');
    expect(cloudCalls, 1);
    expect(byokCalls, 1);
    expect(runtimeCalls, 0);
  });

  test('tryConfiguredDocxOcr uses runtime/native OCR after multimodal failure',
      () async {
    final docxBytes = _buildDocx(<String, List<int>>{
      'word/media/image1.jpg': List<int>.filled(42, 3),
    });
    var cloudCalls = 0;
    var byokCalls = 0;
    var runtimeCalls = 0;

    final result = await tryConfiguredDocxOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      docxBytes: docxBytes,
      pageCountHint: 1,
      languageHints: 'zh_en',
      subscriptionStatus: SubscriptionStatus.notEntitled,
      mediaAnnotationConfig: const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: true,
        allowCellular: true,
        providerMode: 'follow_ask_ai',
      ),
      llmProfiles: const <LlmProfile>[
        LlmProfile(
          id: 'p2',
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
        throw StateError('byok_unavailable');
      },
      tryRuntimeOrNativeImageOcr: (bytes, {required languageHints}) async {
        runtimeCalls += 1;
        expect(languageHints, 'zh_en');
        expect(bytes, hasLength(42));
        return const PlatformPdfOcrResult(
          fullText: 'runtime ocr',
          excerpt: 'runtime ocr',
          engine: 'desktop_rust_image_onnx',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    expect(result, isNotNull);
    expect(result!.engine, 'desktop_rust_image_onnx');
    expect(cloudCalls, 0);
    expect(byokCalls, 1);
    expect(runtimeCalls, 1);
  });

  test('tryConfiguredDocxOcr returns null when docx has no image media',
      () async {
    final docxBytes = _buildDocx(<String, List<int>>{
      'word/document.xml': utf8Bytes('<w:document></w:document>'),
    });
    var cloudCalls = 0;
    var byokCalls = 0;
    var runtimeCalls = 0;

    final result = await tryConfiguredDocxOcr(
      backend: _NoopNativeBackend(),
      sessionKey: sessionKey,
      docxBytes: docxBytes,
      pageCountHint: 1,
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
      cloudModelName: 'cloud-model',
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
      tryRuntimeOrNativeImageOcr: (bytes, {required languageHints}) async {
        runtimeCalls += 1;
        return null;
      },
    );

    expect(result, isNull);
    expect(cloudCalls, 0);
    expect(byokCalls, 0);
    expect(runtimeCalls, 0);
  });
}

Uint8List _buildDocx(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile(
        entry.key,
        entry.value.length,
        Uint8List.fromList(entry.value),
      ),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List utf8Bytes(String text) {
  return Uint8List.fromList(text.codeUnits);
}

final class _NoopNativeBackend extends NativeAppBackend {
  _NoopNativeBackend() : super(appDirProvider: () async => '/tmp/secondloop');
}
