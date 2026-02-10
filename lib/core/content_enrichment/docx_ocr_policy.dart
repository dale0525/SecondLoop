import 'dart:typed_data';

import 'package:archive/archive.dart';

const kDocxMimeType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

final class DocxOcrImageCandidate {
  const DocxOcrImageCandidate({
    required this.bytes,
    required this.mimeType,
    required this.name,
  });

  final Uint8List bytes;
  final String mimeType;
  final String name;
}

bool isDocxMimeType(String mimeType) {
  return mimeType.trim().toLowerCase() == kDocxMimeType;
}

bool shouldAttemptDocxOcr(
  Map<String, Object?> payload, {
  int? nowMs,
  int runningStaleMs = 3 * 60 * 1000,
  int failureCooldownMs = 2 * 60 * 1000,
}) {
  final mime = (payload['mime_type'] ?? '').toString().trim().toLowerCase();
  if (!isDocxMimeType(mime)) return false;

  final existingEngine = (payload['ocr_engine'] ?? '').toString().trim();
  if (existingEngine.isNotEmpty) return false;

  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final status =
      (payload['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
  if (status == 'running') {
    final runningSince = _asMillis(payload['ocr_auto_running_ms']);
    if (runningSince > 0 && (now - runningSince) < runningStaleMs) {
      return false;
    }
  }

  final lastFailureMs = _asMillis(payload['ocr_auto_last_failure_ms']);
  if (lastFailureMs > 0 && (now - lastFailureMs) < failureCooldownMs) {
    return false;
  }

  return true;
}

DocxOcrImageCandidate? extractDocxPrimaryImage(List<int> docxBytes) {
  if (docxBytes.isEmpty) return null;

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(docxBytes, verify: false);
  } catch (_) {
    return null;
  }

  DocxOcrImageCandidate? best;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name.trim();
    if (!name.toLowerCase().startsWith('word/media/')) continue;

    final mimeType = _mimeFromPath(name);
    if (mimeType == null) continue;
    final bytes = file.readBytes();
    if (bytes == null || bytes.isEmpty) continue;

    final candidate = DocxOcrImageCandidate(
      bytes: bytes,
      mimeType: mimeType,
      name: name,
    );
    if (best == null || candidate.bytes.length > best.bytes.length) {
      best = candidate;
    }
  }

  return best;
}

Uint8List? docxBytesFromArchiveExtract(List<int> archiveBytes) {
  if (archiveBytes.isEmpty) return null;
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(archiveBytes, verify: false);
  } catch (_) {
    return null;
  }

  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name.trim().toLowerCase();
    if (!name.startsWith('word/media/')) continue;
    final bytes = file.readBytes();
    if (bytes == null || bytes.isEmpty) continue;
    return bytes;
  }
  return null;
}

List<int> docxBytesToZipContainer(List<int> sourceBytes) {
  final archive = Archive();
  archive.addFile(
    ArchiveFile(
      'word/media/source.bin',
      sourceBytes.length,
      List<int>.from(sourceBytes),
    ),
  );
  return ZipEncoder().encode(archive);
}

String? _mimeFromPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot <= 0 || dot >= path.length - 1) return null;

  switch (path.substring(dot + 1).toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'gif':
      return 'image/gif';
    case 'tif':
    case 'tiff':
      return 'image/tiff';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    default:
      return null;
  }
}

int _asMillis(Object? raw) {
  if (raw is int) return raw > 0 ? raw : 0;
  if (raw is num) {
    final value = raw.toInt();
    return value > 0 ? value : 0;
  }
  if (raw is String) {
    final value = int.tryParse(raw.trim()) ?? 0;
    return value > 0 ? value : 0;
  }
  return 0;
}
