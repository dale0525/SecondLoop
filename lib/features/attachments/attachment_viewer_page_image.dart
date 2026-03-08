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

  Widget _buildImageAttachmentDetail(
    Uint8List bytes, {
    List<AttachmentDetailAction> actions = const <AttachmentDetailAction>[],
  }) {
    Widget buildContent(
      String? annotationCaption,
      Map<String, Object?>? annotationPayload,
    ) {
      final textContent = resolveAttachmentDetailTextContent(
        annotationPayload,
        annotationCaption: annotationCaption,
        mimeTypeOverride: widget.attachment.mimeType,
      );
      final summaryText = textContent.summary.trim();
      final canRetryRecognition = _canRetryAttachmentRecognition;
      final extraAction = canRetryRecognition
          ? AttachmentTextEditorCardAction(
              id: 'regenerate',
              icon: Icons.auto_awesome_rounded,
              label: context.t.attachments.content.rerunOcr,
              tooltip: context.t.attachments.content.rerunOcr,
              buttonKey: const ValueKey('attachment_text_full_regenerate'),
              onPressed: _retryingAttachmentRecognition
                  ? null
                  : () => _retryImageRecognitionWithOptionalOcrDialog(
                        annotationPayload,
                      ),
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

      final preview = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SlSurface(
            key: const ValueKey('attachment_image_preview_surface'),
            padding: const EdgeInsets.all(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey(
                    'attachment_image_preview_tap_target',
                  ),
                  onTap: () => unawaited(_showFullSizeImagePreview(bytes)),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final colorScheme = Theme.of(context).colorScheme;
                      final previewHeight = _imagePreviewHeightForWidth(
                        constraints.maxWidth,
                      );
                      return SizedBox(
                        key: const ValueKey('attachment_image_preview_box'),
                        height: previewHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    colorScheme.surfaceVariant
                                        .withOpacity(0.92),
                                    colorScheme.surface.withOpacity(0.98),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    bytes,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.zoom_in_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (showRecognitionStatus) ...[
            const SizedBox(height: 14),
            SlSurface(
              key: const ValueKey('attachment_image_recognition_status'),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          ],
        ],
      );

      final metadataItems = <AttachmentDetailMetadataItem>[
        AttachmentDetailMetadataItem(
          label: context.t.attachments.metadata.format,
          value: widget.attachment.mimeType,
        ),
        AttachmentDetailMetadataItem(
          label: context.t.attachments.metadata.size,
          value: formatAttachmentByteSize(widget.attachment.byteLen.toInt()),
        ),
        if (_metadata?.filenames.isNotEmpty == true)
          AttachmentDetailMetadataItem(
            label: context.t.attachments.workspace.metadata.filename,
            value: _metadata!.filenames.first.trim(),
          ),
        if (_metadata?.sourceUrls.isNotEmpty == true)
          AttachmentDetailMetadataItem(
            label: context.t.attachments.workspace.metadata.source,
            value: _metadata!.sourceUrls.first.trim(),
          ),
      ];

      final contentChildren = <Widget>[];
      if (summaryText.isNotEmpty) {
        contentChildren.add(
          AttachmentTextEditorCard(
            fieldKeyPrefix: 'attachment_text_summary',
            label: context.t.attachments.content.summary,
            text: summaryText,
            emptyText: attachmentDetailEmptyTextLabel(context),
            onSave: _canEditAttachmentText
                ? (value) => _saveAttachmentText(summary: value)
                : null,
          ),
        );
        contentChildren.add(const SizedBox(height: 14));
      }
      contentChildren.add(
        AttachmentTextEditorCard(
          fieldKeyPrefix: 'attachment_text_full',
          label: context.t.attachments.content.fullText,
          text: textContent.full,
          markdown: true,
          emptyText: attachmentDetailEmptyTextLabel(context),
          extraAction: extraAction,
          onSave: _canEditAttachmentText ? _saveAttachmentFull : null,
        ),
      );

      final workspaceActions = <AttachmentDetailAction>[
        if (canRetryRecognition)
          AttachmentDetailAction(
            label: context.t.attachments.content.rerunOcr,
            icon: Icons.auto_awesome_rounded,
            onPressed: _retryingAttachmentRecognition
                ? null
                : () => _retryImageRecognitionWithOptionalOcrDialog(
                      annotationPayload,
                    ),
          ),
      ];

      return KeyedSubtree(
        key: const ValueKey('attachment_image_detail_scroll'),
        child: AttachmentDetailWorkspace(
          title: _resolveAppBarTitle(widget.attachment, metadata: _metadata),
          typeLabel: context.t.attachments.workspace.types.image,
          metrics: [
            AttachmentDetailMetric(
              label: context.t.attachments.workspace.metrics.type,
              value: widget.attachment.mimeType,
            ),
            AttachmentDetailMetric(
              label: context.t.attachments.metadata.size,
              value:
                  formatAttachmentByteSize(widget.attachment.byteLen.toInt()),
            ),
          ],
          preview: preview,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: contentChildren,
          ),
          metadataItems: metadataItems,
          actions: [...actions, ...workspaceActions],
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

double _imagePreviewHeightForWidth(double width) {
  final safeWidth = width.isFinite && width > 0 ? width : 360;
  return (safeWidth * 0.82).clamp(280.0, 560.0).toDouble();
}
