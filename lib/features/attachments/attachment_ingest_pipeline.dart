import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/backend/native_backend.dart';
import '../media_backup/audio_transcode_worker.dart';
import '../media_backup/image_compression.dart';
import '../media_backup/video_proxy_segment_policy.dart';
import '../media_backup/video_transcode_worker.dart';
import 'attachment_processing_status.dart';
import 'image_exif_metadata.dart';
import 'platform_exif_metadata.dart';

const String kSecondLoopUrlManifestMimeType =
    'application/x.secondloop.url+json';
const String kSecondLoopUrlManifestSchema = 'secondloop.url_manifest.v1';

const String kSecondLoopVideoManifestMimeType =
    'application/x.secondloop.video+json';

const int kAttachmentVideoProxySegmentDurationSeconds = 20 * 60;
const int kAttachmentVideoProxySegmentDurationMs =
    kAttachmentVideoProxySegmentDurationSeconds * 1000;
const int kAttachmentVideoProxySegmentMaxBytes = 50 * 1024 * 1024;
const int kAttachmentVideoProxyMaxDurationMs = 60 * 60 * 1000;
const int kAttachmentVideoProxyMaxBytes = 200 * 1024 * 1024;

typedef AttachmentShaCallback = Future<void> Function(String attachmentSha256);
typedef AttachmentShaMimeCallback = Future<void> Function(
  String attachmentSha256,
  String mimeType,
);
typedef AttachmentShaLangCallback = Future<void> Function(
  String attachmentSha256,
  String lang,
);

final class FileAttachmentIngestOptions {
  const FileAttachmentIngestOptions({
    required this.useLocalAudioTranscode,
    required this.videoProxyEnabled,
    required this.videoProxyMaxDurationMs,
    required this.videoProxyMaxBytes,
  });

  final bool useLocalAudioTranscode;
  final bool videoProxyEnabled;
  final int videoProxyMaxDurationMs;
  final int videoProxyMaxBytes;
}

final class ImageAttachmentIngestResult {
  const ImageAttachmentIngestResult({
    required this.attachmentSha256,
    required this.capturedAtMs,
  });

  final String attachmentSha256;
  final int? capturedAtMs;
}

int sanitizeAttachmentIngestLimit(int value, int fallback) {
  if (value <= 0) return fallback;
  return value;
}

Uint8List buildUrlManifestAttachmentBytes(String url) {
  final manifest = jsonEncode({
    'schema': kSecondLoopUrlManifestSchema,
    'url': url.trim(),
  });
  return Uint8List.fromList(utf8.encode(manifest));
}

Map<String, Object?> buildInitialVideoExtractPayload({
  required String manifestMimeType,
  required String originalSha256,
  required String originalMimeType,
  required int segmentCount,
  String? audioSha256,
  String? audioMimeType,
}) {
  return <String, Object?>{
    'schema': 'secondloop.video_extract.v1',
    'mime_type': manifestMimeType,
    'original_sha256': originalSha256,
    'original_mime_type': originalMimeType,
    'needs_ocr': true,
    'ocr_auto_status': 'queued',
    'video_segment_count': segmentCount,
    'video_processed_segment_count': 0,
    if (audioSha256 != null && audioSha256.trim().isNotEmpty)
      'audio_sha256': audioSha256,
    if (audioMimeType != null && audioMimeType.trim().isNotEmpty)
      'audio_mime_type': audioMimeType,
  };
}

Map<String, Object?> buildVideoManifestPayload({
  required String videoSha256,
  required String videoMimeType,
  String? videoProxySha256,
  String? posterSha256,
  String? posterMimeType,
  List<({int index, String sha256, String mimeType, int tMs, String kind})>?
      keyframes,
  String? audioSha256,
  String? audioMimeType,
  int? segmentCount,
  List<({int index, String sha256, String mimeType})>? videoSegments,
  int videoProxyMaxDurationMs = kAttachmentVideoProxyMaxDurationMs,
  int videoProxyMaxBytes = kAttachmentVideoProxyMaxBytes,
  int? videoProxyTotalBytes,
  bool videoProxyTruncated = false,
}) {
  return <String, Object?>{
    'schema': 'secondloop.video_manifest.v2',
    'video_sha256': videoSha256,
    'video_mime_type': videoMimeType,
    // Backward-compatible fields for readers that still expect v1 keys.
    'original_sha256': videoSha256,
    'original_mime_type': videoMimeType,
    if (videoProxySha256 != null && videoProxySha256.trim().isNotEmpty)
      'video_proxy_sha256': videoProxySha256,
    if (posterSha256 != null && posterSha256.trim().isNotEmpty)
      'poster_sha256': posterSha256,
    if (posterMimeType != null && posterMimeType.trim().isNotEmpty)
      'poster_mime_type': posterMimeType,
    if (keyframes != null && keyframes.isNotEmpty)
      'keyframes': keyframes
          .map(
            (frame) => <String, Object?>{
              'index': frame.index,
              'sha256': frame.sha256,
              'mime_type': frame.mimeType,
              't_ms': frame.tMs,
              'kind': frame.kind,
            },
          )
          .toList(growable: false),
    if (segmentCount != null && segmentCount > 0) 'segment_count': segmentCount,
    'segment_max_duration_ms': kAttachmentVideoProxySegmentDurationMs,
    'segment_max_bytes': kAttachmentVideoProxySegmentMaxBytes,
    'video_proxy_max_duration_ms': videoProxyMaxDurationMs,
    'video_proxy_max_bytes': videoProxyMaxBytes,
    if (videoProxyTotalBytes != null && videoProxyTotalBytes > 0)
      'video_proxy_total_bytes': videoProxyTotalBytes,
    if (videoProxyTruncated) 'video_proxy_truncated': true,
    if (videoSegments != null && videoSegments.isNotEmpty)
      'video_segments': videoSegments
          .map(
            (segment) => <String, Object?>{
              'index': segment.index,
              'sha256': segment.sha256,
              'mime_type': segment.mimeType,
            },
          )
          .toList(growable: false),
    if (audioSha256 != null && audioSha256.trim().isNotEmpty)
      'audio_sha256': audioSha256,
    if (audioMimeType != null && audioMimeType.trim().isNotEmpty)
      'audio_mime_type': audioMimeType,
  };
}

Future<String> ingestFileAttachmentBytes({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required Uint8List rawBytes,
  required String mimeType,
  required FileAttachmentIngestOptions options,
  AttachmentProcessingStageCallback? onStage,
  AttachmentShaCallback? onBackupCandidate,
  AttachmentShaMimeCallback? onMaybeEnqueueAudioTranscribe,
}) async {
  final normalizedMimeType = mimeType.trim();
  final normalizedLowerMimeType = normalizedMimeType.toLowerCase();

  if (normalizedLowerMimeType.startsWith('video/')) {
    if (!options.videoProxyEnabled) {
      onStage?.call(AttachmentProcessingStage.finalizingAttachment);
      final attachment = await backend.insertAttachment(
        sessionKey,
        bytes: rawBytes,
        mimeType: normalizedMimeType,
      );
      _runBestEffort(() => onBackupCandidate?.call(attachment.sha256));
      return attachment.sha256;
    }

    onStage?.call(AttachmentProcessingStage.transcodingVideo);
    final videoProxy = await VideoTranscodeWorker.transcodeToSegmentedMp4Proxy(
      rawBytes,
      sourceMimeType: normalizedMimeType,
      maxSegmentDurationSeconds: kAttachmentVideoProxySegmentDurationSeconds,
      maxSegmentBytes: kAttachmentVideoProxySegmentMaxBytes,
    );
    final selectedSegments = selectVideoProxySegments(videoProxy.segments);
    if (!selectedSegments.hasSegments) {
      throw StateError('video_proxy_segments_empty');
    }

    final videoSegments = <({int index, String sha256, String mimeType})>[];
    for (final segment in selectedSegments.segments) {
      final segmentAttachment = await backend.insertAttachment(
        sessionKey,
        bytes: segment.bytes,
        mimeType: segment.mimeType,
      );
      videoSegments.add(
        (
          index: segment.index,
          sha256: segmentAttachment.sha256,
          mimeType: segmentAttachment.mimeType,
        ),
      );
      _runBestEffort(() => onBackupCandidate?.call(segmentAttachment.sha256));
    }

    final primarySegment = selectedSegments.segments.first;
    final primaryVideo = videoSegments.first;

    String? posterSha256;
    String? posterMimeType;
    final keyframeRefs =
        <({int index, String sha256, String mimeType, int tMs, String kind})>[];
    onStage?.call(AttachmentProcessingStage.generatingKeyframes);
    final preview = await VideoTranscodeWorker.extractPreviewFrames(
      primarySegment.bytes,
      sourceMimeType: primarySegment.mimeType,
    );
    const resolvedKeyframeKind = 'scene';
    final posterBytes = preview.posterBytes;
    if (posterBytes != null && posterBytes.isNotEmpty) {
      final posterAttachment = await backend.insertAttachment(
        sessionKey,
        bytes: posterBytes,
        mimeType: preview.posterMimeType,
      );
      posterSha256 = posterAttachment.sha256;
      posterMimeType = posterAttachment.mimeType;
      _runBestEffort(() => onBackupCandidate?.call(posterAttachment.sha256));
    }

    for (final frame in preview.keyframes) {
      final frameAttachment = await backend.insertAttachment(
        sessionKey,
        bytes: frame.bytes,
        mimeType: frame.mimeType,
      );
      keyframeRefs.add(
        (
          index: frame.index,
          sha256: frameAttachment.sha256,
          mimeType: frameAttachment.mimeType,
          tMs: frame.tMs,
          kind: resolvedKeyframeKind,
        ),
      );
      _runBestEffort(() => onBackupCandidate?.call(frameAttachment.sha256));
    }

    String? audioSha256;
    String? audioMimeType;
    final shouldExtractVideoAudio = options.useLocalAudioTranscode ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (shouldExtractVideoAudio) {
      onStage?.call(AttachmentProcessingStage.extractingAudio);
      final audioProxy =
          await AudioTranscodeWorker.transcodeVideoAudioForManifest(
        rawBytes,
        originalMimeType: normalizedMimeType,
        primarySegmentBytes: primarySegment.bytes,
        primarySegmentMimeType: primarySegment.mimeType,
      );
      if (audioProxy.didTranscode &&
          audioProxy.bytes.isNotEmpty &&
          audioProxy.mimeType.trim().toLowerCase().startsWith('audio/')) {
        final audioAttachment = await backend.insertAttachment(
          sessionKey,
          bytes: audioProxy.bytes,
          mimeType: audioProxy.mimeType,
        );
        audioSha256 = audioAttachment.sha256;
        audioMimeType = audioAttachment.mimeType;
        _runBestEffort(() => onBackupCandidate?.call(audioAttachment.sha256));
      }
    }

    final queuedTranscriptShas = <String>{};

    void enqueueVideoTranscriptBestEffort(String sha256, String mimeType) {
      final normalizedSha = sha256.trim();
      if (normalizedSha.isEmpty) return;
      if (!queuedTranscriptShas.add(normalizedSha)) return;
      _runBestEffort(
        () => onMaybeEnqueueAudioTranscribe?.call(normalizedSha, mimeType),
      );
    }

    for (final segment in videoSegments) {
      enqueueVideoTranscriptBestEffort(segment.sha256, segment.mimeType);
    }

    audioSha256 ??= primaryVideo.sha256;
    audioMimeType ??= primaryVideo.mimeType;
    enqueueVideoTranscriptBestEffort(audioSha256, audioMimeType);

    final manifest = jsonEncode({
      ...buildVideoManifestPayload(
        videoSha256: primaryVideo.sha256,
        videoMimeType: primaryVideo.mimeType,
        videoProxySha256: primaryVideo.sha256,
        posterSha256: posterSha256,
        posterMimeType: posterMimeType,
        keyframes: keyframeRefs,
        audioSha256: audioSha256,
        audioMimeType: audioMimeType,
        segmentCount: videoSegments.length,
        videoSegments: videoSegments,
        videoProxyMaxDurationMs: options.videoProxyMaxDurationMs,
        videoProxyMaxBytes: options.videoProxyMaxBytes,
        videoProxyTotalBytes: selectedSegments.totalBytes,
        videoProxyTruncated: selectedSegments.isTruncated,
      ),
    });
    final manifestBytes = Uint8List.fromList(utf8.encode(manifest));
    onStage?.call(AttachmentProcessingStage.finalizingAttachment);
    final manifestAttachment = await backend.insertAttachment(
      sessionKey,
      bytes: manifestBytes,
      mimeType: kSecondLoopVideoManifestMimeType,
    );

    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final initialPayload = buildInitialVideoExtractPayload(
        manifestMimeType: kSecondLoopVideoManifestMimeType,
        originalSha256: primaryVideo.sha256,
        originalMimeType: primaryVideo.mimeType,
        audioSha256: audioSha256,
        audioMimeType: audioMimeType,
        segmentCount: videoSegments.length,
      );
      await backend.markAttachmentAnnotationOkJson(
        sessionKey,
        attachmentSha256: manifestAttachment.sha256,
        lang: 'und',
        modelName: 'video_extract.v1',
        payloadJson: jsonEncode(initialPayload),
        nowMs: nowMs,
      );
    } catch (_) {
      // ignore
    }

    return manifestAttachment.sha256;
  }

  if (normalizedLowerMimeType.startsWith('audio/')) {
    onStage?.call(AttachmentProcessingStage.transcodingAudio);
    final proxy = options.useLocalAudioTranscode
        ? await AudioTranscodeWorker.transcodeToM4aProxy(
            rawBytes,
            sourceMimeType: normalizedMimeType,
          )
        : AudioTranscodeResult(
            bytes: rawBytes,
            mimeType: normalizedMimeType,
            didTranscode: false,
          );
    onStage?.call(AttachmentProcessingStage.finalizingAttachment);
    final attachment = await backend.insertAttachment(
      sessionKey,
      bytes: proxy.bytes,
      mimeType: proxy.mimeType,
    );

    _runBestEffort(() => onBackupCandidate?.call(attachment.sha256));
    _runBestEffort(
      () => onMaybeEnqueueAudioTranscribe?.call(
        attachment.sha256,
        proxy.mimeType,
      ),
    );
    return attachment.sha256;
  }

  onStage?.call(AttachmentProcessingStage.finalizingAttachment);
  final attachment = await backend.insertAttachment(
    sessionKey,
    bytes: rawBytes,
    mimeType: normalizedMimeType,
  );
  _runBestEffort(() => onBackupCandidate?.call(attachment.sha256));
  return attachment.sha256;
}

Future<ImageAttachmentIngestResult> ingestImageAttachmentBytes({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required Uint8List rawBytes,
  required String inferredMimeType,
  required String lang,
  int? fallbackCapturedAtMs,
  PlatformExifMetadata? platformExif,
  AttachmentShaCallback? onBackupCandidate,
  AttachmentShaLangCallback? onMaybeEnqueuePlace,
  AttachmentShaLangCallback? onMaybeEnqueueAnnotation,
}) async {
  final compressed =
      await compressImageForStorage(rawBytes, mimeType: inferredMimeType);
  final rawExif = tryReadImageExifMetadata(rawBytes);
  final storedExif = tryReadImageExifMetadata(compressed.bytes);

  final capturedAtMs = platformExif?.capturedAtMsUtc ??
      rawExif?.capturedAt?.toUtc().millisecondsSinceEpoch ??
      storedExif?.capturedAt?.toUtc().millisecondsSinceEpoch ??
      fallbackCapturedAtMs;

  (double, double)? pickLatLon(ImageExifMetadata? meta) {
    final lat = meta?.latitude;
    final lon = meta?.longitude;
    if (lat == null || lon == null) return null;
    if (lat == 0.0 && lon == 0.0) return null;
    if (lat.isNaN || lon.isNaN) return null;
    return (lat, lon);
  }

  final latLon = pickLatLon(platformExif?.toImageExifMetadata()) ??
      pickLatLon(rawExif) ??
      pickLatLon(storedExif);
  final latitude = latLon?.$1;
  final longitude = latLon?.$2;

  final attachment = await backend.insertAttachment(
    sessionKey,
    bytes: compressed.bytes,
    mimeType: compressed.mimeType,
  );

  if (capturedAtMs != null || latitude != null || longitude != null) {
    await backend.upsertAttachmentExifMetadata(
      sessionKey,
      sha256: attachment.sha256,
      capturedAtMs: capturedAtMs,
      latitude: latitude,
      longitude: longitude,
    );
  }

  if (latitude != null && longitude != null) {
    _runBestEffort(
      () => onMaybeEnqueuePlace?.call(attachment.sha256, lang),
    );
  }

  _runBestEffort(() => onBackupCandidate?.call(attachment.sha256));
  _runBestEffort(
    () => onMaybeEnqueueAnnotation?.call(attachment.sha256, lang),
  );

  return ImageAttachmentIngestResult(
    attachmentSha256: attachment.sha256,
    capturedAtMs: capturedAtMs,
  );
}

void _runBestEffort(Future<void>? Function()? callback) {
  if (callback == null) return;
  final future = callback();
  if (future == null) return;
  unawaited(future.catchError((_) {}));
}
