part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageErrorText on _AttachmentViewerPageState {
  String _attachmentLoadErrorText(Object? error) {
    if (error is! StateError) {
      return context.t.errors.loadFailed(error: '$error');
    }

    final code = error.message;
    if (code == 'media_download_requires_wifi' ||
        code ==
            'media_download_${CloudMediaDownloadFailureReason.cellularRestricted.name}') {
      return context.t.sync.mediaPreview.chatThumbnailsWifiOnlySubtitle;
    }
    if (code ==
        'media_download_${CloudMediaDownloadFailureReason.authRequired.name}') {
      return context.t.sync.cloudManagedVault.signInRequired;
    }
    if (code.startsWith('media_download_')) {
      return context.t.attachments.content.previewUnavailable;
    }
    return context.t.errors.loadFailed(error: '$error');
  }
}
