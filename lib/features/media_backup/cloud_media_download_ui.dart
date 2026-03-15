import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'cloud_media_download.dart';

enum CloudMediaDownloadUiError {
  wifiOnlyBlocked,
  signInRequired,
  previewUnavailable,
}

CloudMediaDownloadUiError? cloudMediaDownloadUiErrorFromFailureReason(
  CloudMediaDownloadFailureReason reason,
) {
  switch (reason) {
    case CloudMediaDownloadFailureReason.none:
      return null;
    case CloudMediaDownloadFailureReason.cellularRestricted:
      return CloudMediaDownloadUiError.wifiOnlyBlocked;
    case CloudMediaDownloadFailureReason.authRequired:
      return CloudMediaDownloadUiError.signInRequired;
    case CloudMediaDownloadFailureReason.missingSyncConfig:
    case CloudMediaDownloadFailureReason.networkOffline:
    case CloudMediaDownloadFailureReason.backendMisconfigured:
    case CloudMediaDownloadFailureReason.remoteMissing:
    case CloudMediaDownloadFailureReason.downloadFailed:
      return CloudMediaDownloadUiError.previewUnavailable;
  }
}

CloudMediaDownloadFailureReason? cloudMediaDownloadFailureReasonFromError(
  Object? error,
) {
  if (error is CloudMediaDownloadFailureException) {
    return error.failureReason;
  }

  if (error is! StateError) return null;

  final message = error.message;
  if (message == 'media_download_requires_wifi') {
    return CloudMediaDownloadFailureReason.cellularRestricted;
  }

  const prefix = 'media_download_';
  if (!message.startsWith(prefix)) return null;

  final reasonName = message.substring(prefix.length);
  for (final reason in CloudMediaDownloadFailureReason.values) {
    if (reason.name == reasonName) return reason;
  }

  return null;
}

String cloudMediaDownloadUiMessage(
  BuildContext context,
  CloudMediaDownloadUiError error, {
  required bool isWeb,
  required bool isReadonlyMedia,
}) {
  if (error == CloudMediaDownloadUiError.previewUnavailable &&
      isWeb &&
      isReadonlyMedia) {
    return context.t.app.web.mediaProcessing.title;
  }

  return switch (error) {
    CloudMediaDownloadUiError.wifiOnlyBlocked =>
      context.t.sync.mediaPreview.chatThumbnailsWifiOnlyTitle,
    CloudMediaDownloadUiError.signInRequired =>
      context.t.sync.cloudManagedVault.signInRequired,
    CloudMediaDownloadUiError.previewUnavailable =>
      context.t.attachments.content.previewUnavailable,
  };
}
