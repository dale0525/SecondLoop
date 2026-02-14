part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageErrorText on _AttachmentViewerPageState {
  String _attachmentLoadErrorText(Object? error) {
    final reason = cloudMediaDownloadFailureReasonFromError(error);
    if (reason == null) {
      return context.t.errors.loadFailed(error: '$error');
    }

    return switch (cloudMediaDownloadUiErrorFromFailureReason(reason)) {
      CloudMediaDownloadUiError.wifiOnlyBlocked =>
        context.t.sync.mediaPreview.chatThumbnailsWifiOnlySubtitle,
      CloudMediaDownloadUiError.signInRequired =>
        context.t.sync.cloudManagedVault.signInRequired,
      CloudMediaDownloadUiError.previewUnavailable ||
      null =>
        context.t.attachments.content.previewUnavailable,
    };
  }
}
