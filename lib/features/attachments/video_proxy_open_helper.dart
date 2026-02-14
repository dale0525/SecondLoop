import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'video_attachment_player_page.dart';

typedef LoadAttachmentBytesBySha = Future<Uint8List?> Function(String sha256);
typedef OpenVideoProxyInAppOverride = Future<bool> Function(
  String sha256,
  String mimeType,
);

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

  final bytes = await loadBytes(sha256);
  if (bytes == null || bytes.isEmpty) {
    await openWithSystem();
    return;
  }

  final tempFile = await _writeTempVideoFile(
    bytes,
    mimeType: mimeType,
    stem: sha256,
  );
  if (tempFile == null) {
    await openWithSystem();
    return;
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (pageContext) => VideoAttachmentPlayerPage(
        filePath: tempFile.path,
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
