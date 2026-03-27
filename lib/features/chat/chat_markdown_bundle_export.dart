import 'dart:io';
import 'dart:typed_data';

import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_draft_send_contract.dart';
import 'chat_markdown_attachment_refs.dart';

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
  final draftByLocalId = {
    for (final draft in draftAttachments) draft.localId: draft,
  };

  var stem = filenameStem;
  var duplicateIndex = 2;
  while (true) {
    final assetDirectory = Directory('${outputDirectory.path}/$stem.assets');
    final markdownFile = File('${outputDirectory.path}/$stem.md');
    final writtenAssetPaths = <String, String>{};
    var reservedAssetDirectory = false;
    var reservedMarkdownFile = false;

    try {
      if (await assetDirectory.exists()) {
        throw FileSystemException('Already exists', assetDirectory.path);
      }
      await assetDirectory.create();
      reservedAssetDirectory = true;
      await markdownFile.create(exclusive: true);
      reservedMarkdownFile = true;

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
              return null;
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

      await markdownFile.writeAsString(rewrittenMarkdown, flush: true);

      return MarkdownBundleExportResult(
        markdownFile: markdownFile,
        assetDirectory: assetDirectory,
        rewrittenMarkdown: rewrittenMarkdown,
      );
    } on FileSystemException {
      if (reservedMarkdownFile && await markdownFile.exists()) {
        await markdownFile.delete();
      }
      if (reservedAssetDirectory && await assetDirectory.exists()) {
        await assetDirectory.delete(recursive: true);
      }
      stem = '$filenameStem-$duplicateIndex';
      duplicateIndex += 1;
      continue;
    } catch (_) {
      if (reservedMarkdownFile && await markdownFile.exists()) {
        await markdownFile.delete();
      }
      if (reservedAssetDirectory && await assetDirectory.exists()) {
        await assetDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }
}

Future<String> _rewriteMarkdownImageSources(
  String markdown, {
  required Future<String?> Function(String source) onResolveAssetPath,
}) async {
  if (markdown.isEmpty) {
    return markdown;
  }

  final matches =
      kMarkdownImageRefPattern.allMatches(markdown).toList(growable: false);
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

    final source = unwrapMarkdownImageSourceToken(sourceToken);
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
  final directoryName = _pathBaseName(assetDirectory.path);
  final relativePath = '$directoryName/$assetFilename';
  writtenAssetPaths[assetKey] = relativePath;
  return relativePath;
}

String _pathBaseName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed.split(RegExp(r'[\\/]')).last;
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
