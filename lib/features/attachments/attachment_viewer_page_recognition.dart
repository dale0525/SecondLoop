part of 'attachment_viewer_page.dart';

final class _AttachmentRecognitionIssue {
  const _AttachmentRecognitionIssue({
    required this.reason,
    required this.rawError,
  });

  final String reason;
  final String rawError;
}

extension _AttachmentViewerPageRecognition on _AttachmentViewerPageState {
  static const int _annotationJobLookupNowMs = 4102444800000;
  static const int _annotationJobLookupLimit = 500;

  void _startAnnotationJobLoad() {
    if (_loadingAnnotationJob) return;
    _loadingAnnotationJob = true;

    Future<AttachmentAnnotationJob?>.sync(_loadAttachmentAnnotationJob)
        .then((value) {
      if (!mounted) {
        _annotationJob = value;
        return;
      }

      _updateViewerState(() {
        _annotationJob = value;
        _applyAttachmentRecognitionIssueState();
      });
    }).catchError((_) {
      // Best-effort status signal.
    }).whenComplete(() {
      _loadingAnnotationJob = false;
    });
  }

  Future<AttachmentAnnotationJob?> _loadAttachmentAnnotationJob() async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) {
      return null;
    }

    final sessionKey = SessionScope.of(context).sessionKey;
    final jobs = await backendAny.listDueAttachmentAnnotations(
      sessionKey,
      nowMs: _annotationJobLookupNowMs,
      limit: _annotationJobLookupLimit,
    );

    final targetSha = widget.attachment.sha256;
    for (final job in jobs) {
      if (job.attachmentSha256 == targetSha) {
        return job;
      }
    }
    return null;
  }

  String _payloadOcrAutoStatus(Map<String, Object?>? payload) {
    return (payload?['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
  }

  bool _payloadOcrTerminalWithoutText(Map<String, Object?>? payload) {
    final status = _payloadOcrAutoStatus(payload);
    return status == 'ok' || status == 'failed';
  }

  String? _preserveAnnotationCaptionWhileRecognition(String? nextCaption) {
    final normalized = (nextCaption ?? '').trim();
    if (normalized.isNotEmpty) return normalized;
    if (!_awaitingAttachmentRecognitionResult) return null;
    final existing = (_annotationCaption ?? '').trim();
    return existing.isEmpty ? null : existing;
  }

  Map<String, Object?>? _resolveDisplayAnnotationPayload(
    Map<String, Object?>? nextPayload,
  ) {
    final nextTextContent = _resolveIntrinsicTextContentForPayload(nextPayload);
    if (nextTextContent.hasAny) {
      _awaitingAttachmentRecognitionResult = false;
      _preserveRetryFallbackText = false;
      _documentOcrStatusText = null;
      _lastNonEmptyAnnotationPayload = nextPayload;
      return nextPayload;
    }

    final recognitionIssue = _resolveAttachmentRecognitionIssue();
    if (recognitionIssue != null) {
      _awaitingAttachmentRecognitionResult = false;
      _preserveRetryFallbackText = false;
      _documentOcrStatusText = _recognitionIssueMessage(recognitionIssue);
      return _overlayRecognitionIssuePlaceholderPayload(
        nextPayload,
        recognitionIssue,
      );
    }

    if (_awaitingAttachmentRecognitionResult &&
        _payloadOcrTerminalWithoutText(nextPayload)) {
      _awaitingAttachmentRecognitionResult = false;
      final status = _payloadOcrAutoStatus(nextPayload);
      if (status == 'failed') {
        _documentOcrStatusText = context.t.attachments.content.ocrFailed;
      }
    }

    final fallbackPayload =
        _lastNonEmptyAnnotationPayload ?? _annotationPayload;
    final fallbackTextContent =
        _resolveIntrinsicTextContentForPayload(fallbackPayload);
    final shouldPreserveCurrentText = _preserveRetryFallbackText &&
        !nextTextContent.hasAny &&
        fallbackTextContent.hasAny;

    if (shouldPreserveCurrentText) {
      return fallbackPayload;
    }

    return nextPayload;
  }

  _AttachmentRecognitionIssue? _resolveAttachmentRecognitionIssue({
    AttachmentAnnotationJob? job,
  }) {
    final current = job ?? _annotationJob;
    if (current == null) return null;

    final status = current.status.trim().toLowerCase();
    if (status != 'failed') return null;

    final rawError = (current.lastError ?? '').trim();
    if (rawError.isEmpty) return null;

    final reason = detectAudioTranscribeFailureReasonToken(rawError);
    if (reason == null) return null;

    return _AttachmentRecognitionIssue(
      reason: reason,
      rawError: rawError,
    );
  }

  void _applyAttachmentRecognitionIssueState() {
    final issue = _resolveAttachmentRecognitionIssue();
    if (issue == null) return;

    _awaitingAttachmentRecognitionResult = false;
    _preserveRetryFallbackText = false;
    _documentOcrStatusText = _recognitionIssueMessage(issue);

    if (_annotationPayload == null) {
      final placeholder =
          _overlayRecognitionIssuePlaceholderPayload(null, issue);
      _annotationPayload = placeholder;
      _annotationPayloadFuture = Future.value(placeholder);
    }
  }

  Map<String, Object?> _overlayRecognitionIssuePlaceholderPayload(
    Map<String, Object?>? payload,
    _AttachmentRecognitionIssue issue,
  ) {
    final next =
        Map<String, Object?>.from(payload ?? const <String, Object?>{});
    next['ocr_auto_status'] = 'failed';
    next['ocr_engine'] = 'recognition_error';
    next['recognition_failure_reason'] = issue.reason;
    return next;
  }

  Widget _wrapWithRecognitionIssueBanner(Widget child) {
    final issue = _resolveAttachmentRecognitionIssue();
    if (issue == null) return child;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildRecognitionIssueBanner(issue),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildRecognitionIssueBanner(_AttachmentRecognitionIssue issue) {
    final canOpenSettings =
        shouldOpenAudioTranscribeSystemSettings(issue.reason);

    return SlSurface(
      key: const ValueKey('attachment_recognition_issue_banner'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.attachments.content.speechTranscribeIssue.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _recognitionIssueMessage(issue),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canOpenSettings)
                OutlinedButton.icon(
                  onPressed: () => unawaited(_openSpeechRecognitionSettings()),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(
                    context.t.attachments.content.speechTranscribeIssue
                        .openSettings,
                  ),
                ),
              FilledButton.icon(
                onPressed: _retryingAttachmentRecognition
                    ? null
                    : () => unawaited(_retryAttachmentRecognition()),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.t.common.actions.retry),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _recognitionIssueMessage(_AttachmentRecognitionIssue issue) {
    return switch (issue.reason) {
      kAudioTranscribeFailureSpeechPermissionDenied =>
        context.t.attachments.content.speechTranscribeIssue.permissionDenied,
      kAudioTranscribeFailureSpeechPermissionRestricted => context
          .t.attachments.content.speechTranscribeIssue.permissionRestricted,
      kAudioTranscribeFailureSpeechServiceDisabled =>
        context.t.attachments.content.speechTranscribeIssue.serviceDisabled,
      kAudioTranscribeFailureSpeechRuntimeUnavailable =>
        context.t.attachments.content.speechTranscribeIssue.runtimeUnavailable,
      _ => context.t.errors.loadFailed(error: issue.rawError),
    };
  }

  Future<void> _openSpeechRecognitionSettings() async {
    for (final uri in _speechRecognitionSettingsUris()) {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) {
          return;
        }
      } catch (_) {
        // Try the next candidate URI.
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context
              .t.attachments.content.speechTranscribeIssue.openSettingsFailed,
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<Uri> _speechRecognitionSettingsUris() {
    if (kIsWeb) return const <Uri>[];

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return <Uri>[Uri.parse('app-settings:')];
      case TargetPlatform.macOS:
        return <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition',
          ),
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.speech?Dictation',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ];
      case TargetPlatform.windows:
        return <Uri>[
          Uri.parse('ms-settings:privacy-speech'),
          Uri.parse('ms-settings:speech'),
        ];
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const <Uri>[];
    }
  }
}
