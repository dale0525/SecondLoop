part of 'attachment_viewer_page.dart';

final RegExp _kLikelyStorageHashFilename = RegExp(r'^[a-f0-9]{24,}\.bin$');

extension _AttachmentViewerPageTitle on _AttachmentViewerPageState {
  String _filenameFromAttachmentPath(Attachment attachment) {
    final raw = attachment.path.trim();
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll('\\', '/');
    final filename = normalized.split('/').last.trim();
    return filename;
  }

  bool _looksLikeGeneratedStorageFilename(
    Attachment attachment,
    String filename,
  ) {
    final normalized = filename.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    final sha = attachment.sha256.trim().toLowerCase();
    if (sha.isNotEmpty && (normalized == sha || normalized == '$sha.bin')) {
      return true;
    }

    if (_kLikelyStorageHashFilename.hasMatch(normalized)) {
      return true;
    }

    return false;
  }

  String _resolveAppBarTitle(
    Attachment attachment, {
    required AttachmentMetadata? metadata,
  }) {
    final filename = metadata?.filenames.isNotEmpty == true
        ? metadata!.filenames.first.trim()
        : '';
    if (filename.isNotEmpty) return filename;

    final title = (metadata?.title ?? '').trim();
    if (title.isNotEmpty) return title;

    final firstUrl = metadata?.sourceUrls.isNotEmpty == true
        ? metadata!.sourceUrls.first.trim()
        : '';
    if (firstUrl.isNotEmpty) return firstUrl;

    final pathFilename = _filenameFromAttachmentPath(attachment);
    if (pathFilename.isNotEmpty &&
        !_looksLikeGeneratedStorageFilename(attachment, pathFilename)) {
      return pathFilename;
    }

    final fallbackStem = attachment.sha256.trim();
    if (fallbackStem.isNotEmpty) {
      return '$fallbackStem${fileExtensionForSystemOpenMimeType(attachment.mimeType)}';
    }

    return 'Attachment';
  }
}
