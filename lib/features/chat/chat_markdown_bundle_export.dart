import 'dart:io';
import 'dart:typed_data';

import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_draft_send_contract.dart';
import 'chat_markdown_attachment_refs.dart';

final RegExp _kBundleMarkdownImagePattern = RegExp(
  r'!\[[^\]]*\]\((<[^>]+>|[^)\s]+)(?:\s+"[^"]*")?\)',
);

typedef PersistedMarkdownBundleAssetReader = Future<MarkdownBundleAssetData?>
    Function(String attachmentSha256);

final class MarkdownBundleAssetData {
  const MarkdownBundleAssetData({
    required this.bytes,
    required this.mimeType,
    this.filename,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? filename;
}

final class MarkdownBundleExportResult {
  const MarkdownBundleExportResult({
    required this.markdownFile,
    required this.assetDirectory,
    required this.rewrittenMarkdown,
  });

  final File markdownFile;
  final Directory assetDirectory;
  final String rewrittenMarkdown;
}

Future<MarkdownBundleExportResult> exportChatMarkdownBundle({
  required String markdown,
  required String filenameStem,
  required Directory outputDirectory,
  List<AttachmentDraftPayload> draftAttachments =
      const <AttachmentDraftPayload>[],
  PersistedMarkdownBundleAssetReader? readPersistedAttachment,
}) async {
  await outputDirectory.create(recursive: true);
  final assetDirectory =
      Directory('${outputDirectory.path}/$filenameStem.assets');
  await assetDirectory.create(recursive: true);

  final draftByLocalId = {
    for (final draft in draftAttachments) draft.localId: draft,
  };
  final writtenAssetPaths = <String, String>{};

  final rewrittenMarkdown = await _rewriteMarkdownImageSources(
    markdown,
    onResolveAssetPath: (source) async {
      final draftRef = parseDraftMarkdownImageRef(source);
      if (draftRef != null) {
        final draft = draftByLocalId[draftRef.localId];
        if (draft == null) {
          throw StateError('Missing draft attachment: ${draftRef.localId}');
        }
        return _writeAssetIfNeeded(
          assetDirectory: assetDirectory,
          assetKey: 'draft:${draft.localId}',
          assetFilename:
              '${draft.localId}.${_extensionForMimeType(draft.normalizedMimeType)}',
          bytes: draft.bytes,
          writtenAssetPaths: writtenAssetPaths,
        );
      }

      final attachmentRef = parseAttachmentDeepLink(source);
      if (attachmentRef != null) {
        final asset = await readPersistedAttachment?.call(
          attachmentRef.attachmentSha256,
        );
        if (asset == null) {
          throw StateError(
            'Missing persisted attachment: ${attachmentRef.attachmentSha256}',
          );
        }
        return _writeAssetIfNeeded(
          assetDirectory: assetDirectory,
          assetKey: 'attachment:${attachmentRef.attachmentSha256}',
          assetFilename:
              '${attachmentRef.attachmentSha256}.${_extensionForMimeType(asset.mimeType)}',
          bytes: asset.bytes,
          writtenAssetPaths: writtenAssetPaths,
        );
      }

      return null;
    },
  );

  final markdownFile = File('${outputDirectory.path}/$filenameStem.md');
  await markdownFile.writeAsString(rewrittenMarkdown, flush: true);

  return MarkdownBundleExportResult(
    markdownFile: markdownFile,
    assetDirectory: assetDirectory,
    rewrittenMarkdown: rewrittenMarkdown,
  );
}

Future<String> _rewriteMarkdownImageSources(
  String markdown, {
  required Future<String?> Function(String source) onResolveAssetPath,
}) async {
  if (markdown.isEmpty) {
    return markdown;
  }

  final matches =
      _kBundleMarkdownImagePattern.allMatches(markdown).toList(growable: false);
  if (matches.isEmpty) {
    return markdown;
  }

  final buffer = StringBuffer();
  var lastMatchEnd = 0;
  for (final match in matches) {
    buffer.write(markdown.substring(lastMatchEnd, match.start));
    final imageSegment = match.group(0);
    final sourceToken = match.group(1);
    if (imageSegment == null || sourceToken == null) {
      buffer.write(match.group(0) ?? '');
      lastMatchEnd = match.end;
      continue;
    }

    final source = _unwrapMarkdownBundleImageSource(sourceToken);
    final resolvedAssetPath = await onResolveAssetPath(source);
    if (resolvedAssetPath == null) {
      buffer.write(imageSegment);
      lastMatchEnd = match.end;
      continue;
    }

    final wrappedReplacement =
        sourceToken.startsWith('<') && sourceToken.endsWith('>')
            ? '<$resolvedAssetPath>'
            : resolvedAssetPath;
    buffer.write(imageSegment.replaceFirst(sourceToken, wrappedReplacement));
    lastMatchEnd = match.end;
  }

  buffer.write(markdown.substring(lastMatchEnd));
  return buffer.toString();
}

Future<String> _writeAssetIfNeeded({
  required Directory assetDirectory,
  required String assetKey,
  required String assetFilename,
  required Uint8List bytes,
  required Map<String, String> writtenAssetPaths,
}) async {
  final existing = writtenAssetPaths[assetKey];
  if (existing != null) {
    return existing;
  }

  final file = File('${assetDirectory.path}/$assetFilename');
  await file.writeAsBytes(bytes, flush: true);
  final directoryName = assetDirectory.path.split(Platform.pathSeparator).last;
  final relativePath = '$directoryName/$assetFilename';
  writtenAssetPaths[assetKey] = relativePath;
  return relativePath;
}

String _unwrapMarkdownBundleImageSource(String token) {
  final trimmed = token.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('<') && trimmed.endsWith('>')) {
    return trimmed.substring(1, trimmed.length - 1).trim();
  }
  return trimmed;
}

String _extensionForMimeType(String mimeType) {
  switch (mimeType.trim().toLowerCase()) {
    case 'image/png':
      return 'png';
    case 'image/jpeg':
      return 'jpg';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    case 'image/tiff':
      return 'tiff';
    default:
      return 'bin';
  }
}
