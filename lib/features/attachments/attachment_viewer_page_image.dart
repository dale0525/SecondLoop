part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageImage on _AttachmentViewerPageState {
  Future<void> _showFullSizeImagePreview(Uint8List bytes) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          key: const ValueKey('attachment_image_full_preview_dialog'),
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Center(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  key: const ValueKey('attachment_image_full_preview_close'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  tooltip: MaterialLocalizations.of(dialogContext)
                      .closeButtonTooltip,
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageAttachmentDetail(Uint8List bytes) {
    Widget buildSection(
      Widget child, {
      required double maxWidth,
      Alignment alignment = Alignment.center,
    }) {
      return Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
    }

    Widget buildContent(
      String? annotationCaption,
      Map<String, Object?>? annotationPayload,
    ) {
      final textContent = resolveAttachmentDetailTextContent(
        annotationPayload,
        annotationCaption: annotationCaption,
      );
      final canRetryRecognition =
          _canRetryAttachmentRecognition && textContent.hasAny;
      final trailing = canRetryRecognition
          ? IconButton(
              key: const ValueKey('attachment_text_full_regenerate'),
              tooltip: context.t.attachments.content.rerunOcr,
              onPressed: _retryingAttachmentRecognition
                  ? null
                  : () => unawaited(
                        _retryImageRecognitionWithOptionalOcrDialog(
                          annotationPayload,
                        ),
                      ),
              icon: _retryingAttachmentRecognition
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
            )
          : null;
      final recognitionStatus = (() {
        final status = (_documentOcrStatusText ?? '').trim();
        if (status.isNotEmpty) return status;
        if (_awaitingAttachmentRecognitionResult) {
          return context.t.attachments.content.ocrRunning;
        }
        return '';
      })();
      final showRecognitionStatus = recognitionStatus.isNotEmpty;
      final recognitionRunning = _awaitingAttachmentRecognitionResult ||
          _retryingAttachmentRecognition;

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: SingleChildScrollView(
            key: const ValueKey('attachment_image_detail_scroll'),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSection(
                  SlSurface(
                    key: const ValueKey('attachment_image_preview_surface'),
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const ValueKey(
                            'attachment_image_preview_tap_target',
                          ),
                          onTap: () =>
                              unawaited(_showFullSizeImagePreview(bytes)),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final previewHeight =
                                  (constraints.maxWidth * 0.30)
                                      .clamp(120.0, 220.0);
                              return SizedBox(
                                key: const ValueKey(
                                    'attachment_image_preview_box'),
                                height: previewHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceVariant,
                                  ),
                                  child: Center(
                                    child: Image.memory(
                                      bytes,
                                      fit: BoxFit.contain,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  maxWidth: 760,
                ),
                if (showRecognitionStatus) ...[
                  const SizedBox(height: 14),
                  buildSection(
                    SlSurface(
                      key:
                          const ValueKey('attachment_image_recognition_status'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          if (recognitionRunning)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              recognitionStatus,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    maxWidth: 820,
                  ),
                ],
                const SizedBox(height: 14),
                buildSection(
                  AttachmentTextEditorCard(
                    fieldKeyPrefix: 'attachment_text_full',
                    label: context.t.attachments.content.fullText,
                    showLabel: false,
                    text: textContent.full,
                    markdown: true,
                    emptyText: attachmentDetailEmptyTextLabel(context),
                    trailing: trailing,
                    onSave: _canEditAttachmentText ? _saveAttachmentFull : null,
                  ),
                  maxWidth: 820,
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildWithAnnotationPayload(String? annotationCaption) {
      final payloadFuture = _annotationPayloadFuture;
      if (payloadFuture == null) {
        return buildContent(annotationCaption, _annotationPayload);
      }

      return FutureBuilder<Map<String, Object?>?>(
        future: payloadFuture,
        initialData: _annotationPayload,
        builder: (context, payloadSnapshot) {
          return buildContent(
            annotationCaption,
            payloadSnapshot.data,
          );
        },
      );
    }

    final annotationFuture = _annotationCaptionFuture;
    if (annotationFuture == null) {
      return buildWithAnnotationPayload(_annotationCaption);
    }

    return FutureBuilder<String?>(
      future: annotationFuture,
      initialData: _annotationCaption,
      builder: (context, annotationSnapshot) {
        return buildWithAnnotationPayload(annotationSnapshot.data);
      },
    );
  }
}
