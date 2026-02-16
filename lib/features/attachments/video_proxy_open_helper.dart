import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'video_attachment_player_page.dart';

typedef LoadAttachmentBytesBySha = Future<Uint8List?> Function(String sha256);
typedef OpenVideoProxyInAppOverride = Future<bool> Function(
  String sha256,
  String mimeType,
);

final class PreparedVideoProxyPlayback {
  const PreparedVideoProxyPlayback({
    required this.segmentFiles,
    required this.initialSegmentIndex,
  });

  final List<VideoAttachmentPlayerSegment> segmentFiles;
  final int initialSegmentIndex;

  bool get hasSegments => segmentFiles.isNotEmpty;
}

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

  final playback = await prepareVideoProxyPlayback(
    primarySha256: sha256,
    primaryMimeType: mimeType,
    loadBytes: loadBytes,
    segmentRefs: segmentRefs,
  );

  if (!playback.hasSegments) {
    await openWithSystem();
    return;
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (pageContext) => VideoAttachmentPlayerPage(
        segmentFiles: playback.segmentFiles,
        initialSegmentIndex: playback.initialSegmentIndex,
        displayTitle: '',
        onOpenWithSystem: openWithSystem,
      ),
    ),
  );
}

Future<PreparedVideoProxyPlayback> prepareVideoProxyPlayback({
  required String primarySha256,
  required String primaryMimeType,
  required LoadAttachmentBytesBySha loadBytes,
  List<({String sha256, String mimeType})>? segmentRefs,
}) async {
  final segments = resolveVideoProxySegments(
    primarySha256: primarySha256,
    primaryMimeType: primaryMimeType,
    segmentRefs: segmentRefs,
  );
  if (segments.isEmpty) {
    return const PreparedVideoProxyPlayback(
      segmentFiles: <VideoAttachmentPlayerSegment>[],
      initialSegmentIndex: 0,
    );
  }

  final segmentFiles = <VideoAttachmentPlayerSegment>[];
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final bytes = await loadBytes(segment.sha256);
    if (bytes == null || bytes.isEmpty) continue;

    final tempFile = await writeTempVideoProxyFile(
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

  var initialSegmentIndex = 0;
  final normalizedPrimarySha = primarySha256.trim();
  for (var i = 0; i < segmentFiles.length; i++) {
    if (segmentFiles[i].sha256 == normalizedPrimarySha) {
      initialSegmentIndex = i;
      break;
    }
  }

  return PreparedVideoProxyPlayback(
    segmentFiles: List<VideoAttachmentPlayerSegment>.unmodifiable(segmentFiles),
    initialSegmentIndex: initialSegmentIndex,
  );
}

Future<File?> writeTempVideoProxyFile(
  Uint8List bytes, {
  required String mimeType,
  required String stem,
}) async {
  if (bytes.isEmpty) return null;

  final cleanStem = stem.trim().isEmpty ? 'video_proxy' : stem.trim();
  final extension = extensionForVideoMimeType(mimeType);
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

String extensionForVideoMimeType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  if (normalized.startsWith('video/x-m4v')) return '.m4v';
  if (normalized.startsWith('video/quicktime')) return '.mov';
  if (normalized.startsWith('video/webm')) return '.webm';
  if (normalized.startsWith('video/x-matroska')) return '.mkv';
  if (normalized.startsWith('video/x-msvideo')) return '.avi';
  if (normalized.startsWith('video/x-ms-wmv')) return '.wmv';
  if (normalized.startsWith('video/x-ms-asf')) return '.asf';
  if (normalized.startsWith('video/x-flv')) return '.flv';
  if (normalized.startsWith('video/mpeg')) return '.mpeg';
  if (normalized.startsWith('video/mp2t')) return '.ts';
  if (normalized.startsWith('video/3gpp2')) return '.3g2';
  if (normalized.startsWith('video/3gpp')) return '.3gp';
  if (normalized.startsWith('video/ogg')) return '.ogv';
  return '.mp4';
}
