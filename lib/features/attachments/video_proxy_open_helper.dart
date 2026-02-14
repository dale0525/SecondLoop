import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'video_attachment_player_page.dart';

typedef LoadAttachmentBytesBySha = Future<Uint8List?> Function(String sha256);
typedef OpenVideoProxyInAppOverride = Future<bool> Function(
  String sha256,
  String mimeType,
);

final class VideoProxySegmentToOpen {
  const VideoProxySegmentToOpen({
    required this.sha256,
    required this.mimeType,
  });

  final String sha256;
  final String mimeType;
}

List<VideoProxySegmentToOpen> resolveVideoProxySegments({
  required String primarySha256,
  required String primaryMimeType,
  List<({String sha256, String mimeType})>? segmentRefs,
}) {
  final fallbackSha = primarySha256.trim();
  final fallbackMime = primaryMimeType.trim();
  if (fallbackSha.isEmpty || fallbackMime.isEmpty) {
    return const <VideoProxySegmentToOpen>[];
  }

  final resolved = <VideoProxySegmentToOpen>[];
  final seenShas = <String>{};

  void tryAddSegment(String sha256, String mimeType) {
    final normalizedSha = sha256.trim();
    final normalizedMime = mimeType.trim();
    if (normalizedSha.isEmpty || normalizedMime.isEmpty) return;
    if (!seenShas.add(normalizedSha)) return;
    resolved.add(
      VideoProxySegmentToOpen(
        sha256: normalizedSha,
        mimeType: normalizedMime,
      ),
    );
  }

  tryAddSegment(fallbackSha, fallbackMime);

  final refs = segmentRefs;
  if (refs != null) {
    for (final ref in refs) {
      tryAddSegment(ref.sha256, ref.mimeType);
    }
  }

  return List<VideoProxySegmentToOpen>.unmodifiable(resolved);
}

bool supportsInAppVideoProxyPlayback({
  required TargetPlatform platform,
  required bool isWeb,
}) {
  if (isWeb) return false;
  switch (platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return false;
  }
}

Future<void> openVideoProxyWithBestEffort(
  BuildContext context, {
  required String sha256,
  required String mimeType,
  required LoadAttachmentBytesBySha loadBytes,
  required Future<void> Function() openWithSystem,
  OpenVideoProxyInAppOverride? onOpenVideoProxyInApp,
  List<({String sha256, String mimeType})>? segmentRefs,
}) async {
  final platform = Theme.of(context).platform;
  final override = onOpenVideoProxyInApp;
  if (override != null) {
    try {
      final didHandle = await override(sha256, mimeType);
      if (didHandle) return;
    } catch (_) {
      // Ignore override failures and continue with default behavior.
    }
  }

  final canOpenInApp = supportsInAppVideoProxyPlayback(
    platform: platform,
    isWeb: kIsWeb,
  );
  if (!canOpenInApp) {
    await openWithSystem();
    return;
  }

  final segments = resolveVideoProxySegments(
    primarySha256: sha256,
    primaryMimeType: mimeType,
    segmentRefs: segmentRefs,
  );
  if (segments.isEmpty) {
    await openWithSystem();
    return;
  }

  final segmentFiles = <VideoAttachmentPlayerSegment>[];
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final bytes = await loadBytes(segment.sha256);
    if (bytes == null || bytes.isEmpty) continue;

    final tempFile = await _writeTempVideoFile(
      bytes,
      mimeType: segment.mimeType,
      stem: '${segment.sha256}_$i',
    );
    if (tempFile == null) continue;

    segmentFiles.add(
      VideoAttachmentPlayerSegment(
        filePath: tempFile.path,
        sha256: segment.sha256,
        mimeType: segment.mimeType,
      ),
    );
  }

  if (segmentFiles.isEmpty) {
    await openWithSystem();
    return;
  }

  var initialSegmentIndex = 0;
  for (var i = 0; i < segmentFiles.length; i++) {
    if (segmentFiles[i].sha256 == sha256.trim()) {
      initialSegmentIndex = i;
      break;
    }
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (pageContext) => VideoAttachmentPlayerPage(
        segmentFiles: segmentFiles,
        initialSegmentIndex: initialSegmentIndex,
        displayTitle: '',
        onOpenWithSystem: openWithSystem,
      ),
    ),
  );
}

Future<File?> _writeTempVideoFile(
  Uint8List bytes, {
  required String mimeType,
  required String stem,
}) async {
  if (bytes.isEmpty) return null;

  final cleanStem = stem.trim().isEmpty ? 'video_proxy' : stem.trim();
  final extension = _extensionForVideoMimeType(mimeType);
  final dirPath = '${Directory.systemTemp.path}/secondloop_video_proxy_preview';
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final outputPath = '${dir.path}/$cleanStem$extension';
  final file = File(outputPath);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

String _extensionForVideoMimeType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  if (normalized.startsWith('video/quicktime')) return '.mov';
  if (normalized.startsWith('video/webm')) return '.webm';
  return '.mp4';
}
