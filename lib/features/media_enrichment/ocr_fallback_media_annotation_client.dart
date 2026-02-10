import 'dart:convert';
import 'dart:typed_data';

import '../../core/content_enrichment/ocr_text_quality.dart';
import '../attachments/platform_pdf_ocr.dart';
import 'media_enrichment_runner.dart';

typedef OcrFallbackImageRunner = Future<PlatformPdfOcrResult?> Function(
  Uint8List bytes, {
  required String languageHints,
});

final class OcrFallbackMediaAnnotationClient implements MediaEnrichmentClient {
  OcrFallbackMediaAnnotationClient({
    this.primaryClient,
    required this.languageHints,
    this.minOcrTextScore = 20,
    OcrFallbackImageRunner? tryOcrImage,
  }) : _tryOcrImage = tryOcrImage ?? PlatformPdfOcr.tryOcrImageBytes;

  final MediaEnrichmentClient? primaryClient;
  final String languageHints;
  final double minOcrTextScore;
  final OcrFallbackImageRunner _tryOcrImage;

  @override
  String get annotationModelName {
    final model = primaryClient?.annotationModelName.trim() ?? '';
    if (model.isNotEmpty) return model;
    return 'ocr_fallback';
  }

  @override
  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  }) async {
    final client = primaryClient;
    if (client == null) {
      throw StateError('reverse_geocode_not_available_for_ocr_fallback_client');
    }
    return client.reverseGeocode(lat: lat, lon: lon, lang: lang);
  }

  @override
  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    Object? primaryError;
    final client = primaryClient;
    if (client != null) {
      try {
        final payload = await client.annotateImage(
          lang: lang,
          mimeType: mimeType,
          imageBytes: imageBytes,
        );
        if (_isUsablePrimaryAnnotationPayload(payload)) {
          return payload;
        }
        primaryError = StateError('annotation_payload_missing_caption_and_ocr');
      } catch (error) {
        primaryError = error;
      }
    }

    final hints =
        languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();
    final ocr = await _tryOcrImage(imageBytes, languageHints: hints);
    if (ocr == null) {
      if (primaryError != null) {
        throw StateError('ocr_fallback_unavailable:$primaryError');
      }
      throw StateError('ocr_fallback_unavailable');
    }

    final full = ocr.fullText.trim();
    if (!hasSufficientOcrTextSignal(full, minScore: minOcrTextScore)) {
      return _buildNoTextFallbackPayload();
    }

    return jsonEncode(<String, Object?>{
      'caption_long': _buildFallbackCaption(full),
      'tags': const <String>['ocr_fallback'],
      'ocr_text': full,
    });
  }
}

bool _isUsablePrimaryAnnotationPayload(String payloadJson) {
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) return false;
    final payload = Map<String, Object?>.from(decoded);
    final caption = (payload['caption_long'] ?? '').toString().trim();
    final ocrText = (payload['ocr_text'] ?? '').toString().trim();
    return caption.isNotEmpty || ocrText.isNotEmpty;
  } catch (_) {
    return false;
  }
}

String _buildFallbackCaption(String ocrText) {
  final singleLine = ocrText.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.isEmpty) {
    return 'OCR fallback caption';
  }
  if (singleLine.length <= 160) {
    return 'OCR fallback caption: $singleLine';
  }
  return 'OCR fallback caption: ${singleLine.substring(0, 160).trimRight()}...';
}

String _buildNoTextFallbackPayload() {
  return jsonEncode(const <String, Object?>{
    'caption_long': '',
    'tags': <String>['ocr_fallback_no_text'],
    'ocr_text': '',
  });
}
