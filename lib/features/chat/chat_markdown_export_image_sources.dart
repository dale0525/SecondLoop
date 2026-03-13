import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_draft_send_contract.dart';
import 'chat_markdown_attachment_refs.dart';

final RegExp _kMarkdownExportImagePattern = RegExp(
  r'!\[[^\]]*\]\((<[^>]+>|[^)\s]+)(?:\s+"[^"]*")?\)',
);

const int _kMaxInlinedImageBytes = 8 * 1024 * 1024;
const Duration _kRemoteImageTimeout = Duration(seconds: 8);

class ChatMarkdownExportImageData {
  const ChatMarkdownExportImageData({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

Future<String> inlineMarkdownImageSourcesAsDataUrls(
  String markdown, {
  List<AttachmentDraftPayload> draftAttachments =
      const <AttachmentDraftPayload>[],
  Future<ChatMarkdownExportImageData?> Function(String attachmentSha256)?
      readPersistedAttachment,
  HttpClient Function()? httpClientFactory,
}) async {
  if (markdown.isEmpty) {
    return markdown;
  }

  final matches =
      _kMarkdownExportImagePattern.allMatches(markdown).toList(growable: false);
  if (matches.isEmpty) {
    return markdown;
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in matches) {
    buffer.write(markdown.substring(cursor, match.start));
    final imageSegment = match.group(0);
    final sourceToken = match.group(1);

    if (imageSegment == null || sourceToken == null) {
      buffer.write(markdown.substring(match.start, match.end));
      cursor = match.end;
      continue;
    }

    final source = unwrapMarkdownImageSourceToken(sourceToken);
    final dataUrl = await resolveMarkdownImageSourceAsDataUrl(
      source,
      draftAttachments: draftAttachments,
      readPersistedAttachment: readPersistedAttachment,
      httpClientFactory: httpClientFactory,
    );
    if (dataUrl == null) {
      buffer.write(imageSegment);
      cursor = match.end;
      continue;
    }

    final replacementSource =
        sourceToken.startsWith('<') ? '<$dataUrl>' : dataUrl;
    buffer.write(imageSegment.replaceFirst(sourceToken, replacementSource));
    cursor = match.end;
  }

  buffer.write(markdown.substring(cursor));
  return buffer.toString();
}

Future<String?> resolveMarkdownImageSourceAsDataUrl(
  String source, {
  List<AttachmentDraftPayload> draftAttachments =
      const <AttachmentDraftPayload>[],
  Future<ChatMarkdownExportImageData?> Function(String attachmentSha256)?
      readPersistedAttachment,
  HttpClient Function()? httpClientFactory,
}) async {
  final trimmed = source.trim();
  if (trimmed.isEmpty || trimmed.startsWith('data:')) {
    return trimmed.isEmpty ? null : trimmed;
  }

  final draftRef = parseDraftMarkdownImageRef(trimmed);
  if (draftRef != null) {
    final payload = draftAttachments.cast<AttachmentDraftPayload?>().firstWhere(
          (candidate) => candidate?.localId == draftRef.localId,
          orElse: () => null,
        );
    if (payload != null && payload.bytes.isNotEmpty) {
      return _buildDataUrl(
        bytes: payload.bytes,
        mimeType: _normalizedImageMimeType(
          preferredMimeType: payload.mimeType,
          sourcePath: payload.filename,
          bytes: payload.bytes,
        ),
      );
    }
    return null;
  }

  final attachmentRef = parseAttachmentDeepLink(trimmed);
  if (attachmentRef != null && readPersistedAttachment != null) {
    final resolved =
        await readPersistedAttachment(attachmentRef.attachmentSha256);
    if (resolved != null && resolved.bytes.isNotEmpty) {
      return _buildDataUrl(
        bytes: resolved.bytes,
        mimeType: _normalizedImageMimeType(
          preferredMimeType: resolved.mimeType,
          sourcePath: attachmentRef.attachmentSha256,
          bytes: resolved.bytes,
        ),
      );
    }
    return null;
  }

  if (_looksLikeWindowsAbsolutePath(trimmed)) {
    return _readLocalImageAsDataUrl(trimmed);
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return _readLocalImageAsDataUrl(trimmed);
  }

  if (uri.hasScheme) {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _downloadImageAsDataUrl(uri, httpClientFactory: httpClientFactory);
    }
    if (uri.scheme == 'file') {
      return _readLocalImageAsDataUrl(uri.toFilePath());
    }
    return null;
  }

  return _readLocalImageAsDataUrl(trimmed);
}

String _buildDataUrl({required List<int> bytes, required String mimeType}) {
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

bool _looksLikeWindowsAbsolutePath(String value) {
  if (value.length >= 3) {
    final first = value.codeUnitAt(0);
    final isLetter =
        (first >= 65 && first <= 90) || (first >= 97 && first <= 122);
    if (isLetter && value.codeUnitAt(1) == 58) {
      final separator = value.codeUnitAt(2);
      if (separator == 92 || separator == 47) {
        return true;
      }
    }
  }
  return value.startsWith(r'\\');
}

Future<String?> _downloadImageAsDataUrl(
  Uri uri, {
  HttpClient Function()? httpClientFactory,
}) async {
  HttpClient? client;

  try {
    client = (httpClientFactory ?? HttpClient.new)()
      ..connectionTimeout = _kRemoteImageTimeout;
    final request = await client.getUrl(uri).timeout(_kRemoteImageTimeout);
    request.followRedirects = true;
    request.maxRedirects = 4;
    request.headers
        .set(HttpHeaders.userAgentHeader, 'SecondLoopMarkdownExporter/1.0');

    final response = await request.close().timeout(_kRemoteImageTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final bytes = await _readHttpResponseBytes(response);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final mimeType = _normalizedImageMimeType(
      preferredMimeType: response.headers.contentType?.mimeType,
      sourcePath: uri.path,
      bytes: bytes,
    );
    return _buildDataUrl(bytes: bytes, mimeType: mimeType);
  } catch (_) {
    return null;
  } finally {
    client?.close(force: true);
  }
}

Future<List<int>?> _readHttpResponseBytes(HttpClientResponse response) async {
  final builder = BytesBuilder(copy: false);
  var totalBytes = 0;

  await for (final chunk in response) {
    totalBytes += chunk.length;
    if (totalBytes > _kMaxInlinedImageBytes) {
      return null;
    }
    builder.add(chunk);
  }

  return builder.takeBytes();
}

Future<String?> _readLocalImageAsDataUrl(String path) async {
  if (path.trim().isEmpty) {
    return null;
  }

  try {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }

    final length = await file.length();
    if (length <= 0 || length > _kMaxInlinedImageBytes) {
      return null;
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }

    final mimeType = _normalizedImageMimeType(
      preferredMimeType: null,
      sourcePath: file.path,
      bytes: bytes,
    );
    return _buildDataUrl(bytes: bytes, mimeType: mimeType);
  } catch (_) {
    return null;
  }
}

String _normalizedImageMimeType({
  required String? preferredMimeType,
  required String sourcePath,
  required List<int> bytes,
}) {
  if (preferredMimeType != null && preferredMimeType.startsWith('image/')) {
    return preferredMimeType;
  }

  final lowerPath = sourcePath.toLowerCase();
  if (lowerPath.endsWith('.png')) return 'image/png';
  if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lowerPath.endsWith('.gif')) return 'image/gif';
  if (lowerPath.endsWith('.webp')) return 'image/webp';
  if (lowerPath.endsWith('.bmp')) return 'image/bmp';
  if (lowerPath.endsWith('.svg')) return 'image/svg+xml';

  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6) {
    final header = ascii.decode(bytes.take(6).toList(), allowInvalid: true);
    if (header == 'GIF87a' || header == 'GIF89a') {
      return 'image/gif';
    }
  }

  final probeLength = math.min(400, bytes.length);
  final probeText = utf8
      .decode(bytes.sublist(0, probeLength), allowMalformed: true)
      .toLowerCase();
  if (probeText.contains('<svg')) {
    return 'image/svg+xml';
  }

  return 'application/octet-stream';
}
