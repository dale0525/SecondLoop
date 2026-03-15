part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageErrorText on _AttachmentViewerPageState {
  String _attachmentLoadErrorText(Object? error) {
    final reason = cloudMediaDownloadFailureReasonFromError(error);
    if (reason == null) {
      return context.t.errors.loadFailed(error: '$error');
    }

    final uiError = cloudMediaDownloadUiErrorFromFailureReason(reason);
    if (uiError == null) {
      return context.t.attachments.content.previewUnavailable;
    }
    if (uiError == CloudMediaDownloadUiError.previewUnavailable &&
        (widget.isWebOverride ?? kIsWeb) &&
        needsAppProcessingInWeb(widget.attachment.mimeType)) {
      return cloudMediaDownloadUiMessage(
        uiError,
        isWeb: true,
        isReadonlyMedia: true,
      );
    }

    return switch (uiError) {
      CloudMediaDownloadUiError.wifiOnlyBlocked =>
        context.t.sync.mediaPreview.chatThumbnailsWifiOnlySubtitle,
      CloudMediaDownloadUiError.signInRequired =>
        context.t.sync.cloudManagedVault.signInRequired,
      CloudMediaDownloadUiError.previewUnavailable =>
        context.t.attachments.content.previewUnavailable,
    };
  }
}
