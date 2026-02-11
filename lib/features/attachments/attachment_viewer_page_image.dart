part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageImage on _AttachmentViewerPageState {
  Widget _buildImageAttachmentDetail(Uint8List bytes) {
    final exifFromBytes = tryReadImageExifMetadata(bytes);

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
      AttachmentExifMetadata? persisted,
      String? placeDisplayName,
      String? annotationCaption,
      Map<String, Object?>? annotationPayload,
    ) {
      final persistedCapturedAtMs = persisted?.capturedAtMs;
      final persistedCapturedAt = persistedCapturedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              persistedCapturedAtMs.toInt(),
              isUtc: true,
            ).toLocal();

      final persistedLatitude = persisted?.latitude;
      final persistedLongitude = persisted?.longitude;
      final hasPersistedLocation = persistedLatitude != null &&
          persistedLongitude != null &&
          !(persistedLatitude == 0.0 && persistedLongitude == 0.0);

      final capturedAt = persistedCapturedAt ?? exifFromBytes?.capturedAt;
      final latitude =
          hasPersistedLocation ? persistedLatitude : exifFromBytes?.latitude;
      final longitude =
          hasPersistedLocation ? persistedLongitude : exifFromBytes?.longitude;
      _maybeScheduleInlinePlaceResolve(
        latitude: latitude,
        longitude: longitude,
      );

      final textContent = resolveAttachmentDetailTextContent(
        annotationPayload,
        annotationCaption: annotationCaption,
      );
      final canRetryRecognition =
          _canRetryAttachmentRecognition && textContent.hasAny;

      final retryButton = canRetryRecognition
          ? IconButton(
              key: const ValueKey('attachment_annotation_retry'),
              tooltip: context.t.common.actions.retry,
              onPressed: _retryingAttachmentRecognition
                  ? null
                  : () => unawaited(_retryAttachmentRecognition()),
              icon: _retryingAttachmentRecognition
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            )
          : null;

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final previewHeight =
                            (constraints.maxWidth * 0.72).clamp(220.0, 560.0);
                        return SizedBox(
                          height: previewHeight,
                          child: Center(
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 4,
                              child: Image.memory(bytes, fit: BoxFit.contain),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  maxWidth: 860,
                ),
                const SizedBox(height: 14),
                buildSection(
                  _buildMetadataCard(
                    context,
                    capturedAt: capturedAt,
                    latitude: latitude,
                    longitude: longitude,
                    placeDisplayName: placeDisplayName,
                  ),
                  maxWidth: 620,
                  alignment: Alignment.centerLeft,
                ),
                const SizedBox(height: 14),
                buildSection(
                  AttachmentTextEditorCard(
                    fieldKeyPrefix: 'attachment_text_full',
                    label: context.t.attachments.content.fullText,
                    showLabel: false,
                    text: textContent.full,
                    markdown: true,
                    emptyText: attachmentDetailEmptyTextLabel(context),
                    trailing: retryButton,
                    onSave: _canEditAttachmentText ? _saveAttachmentFull : null,
                  ),
                  maxWidth: 780,
                  alignment: Alignment.centerRight,
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildWithAnnotationPayload(
      AttachmentExifMetadata? persisted,
      String? placeDisplayName,
      String? annotationCaption,
    ) {
      final payloadFuture = _annotationPayloadFuture;
      if (payloadFuture == null) {
        return buildContent(
          persisted,
          placeDisplayName,
          annotationCaption,
          _annotationPayload,
        );
      }

      return FutureBuilder<Map<String, Object?>?>(
        future: payloadFuture,
        initialData: _annotationPayload,
        builder: (context, payloadSnapshot) {
          return buildContent(
            persisted,
            placeDisplayName,
            annotationCaption,
            payloadSnapshot.data,
          );
        },
      );
    }

    Widget buildWithAnnotation(
      AttachmentExifMetadata? persisted,
      String? placeDisplayName,
    ) {
      final annotationFuture = _annotationCaptionFuture;
      if (annotationFuture == null) {
        return buildWithAnnotationPayload(persisted, placeDisplayName, null);
      }

      return FutureBuilder<String?>(
        future: annotationFuture,
        initialData: _annotationCaption,
        builder: (context, annotationSnapshot) {
          return buildWithAnnotationPayload(
            persisted,
            placeDisplayName,
            annotationSnapshot.data,
          );
        },
      );
    }

    Widget buildWithPlace(AttachmentExifMetadata? persisted) {
      final placeFuture = _placeFuture;
      if (placeFuture == null) {
        return buildWithAnnotation(persisted, null);
      }

      return FutureBuilder<String?>(
        future: placeFuture,
        initialData: _placeDisplayName,
        builder: (context, placeSnapshot) {
          return buildWithAnnotation(persisted, placeSnapshot.data);
        },
      );
    }

    final exifFuture = _exifFuture;
    if (exifFuture == null) {
      return buildWithPlace(null);
    }

    return FutureBuilder<AttachmentExifMetadata?>(
      future: exifFuture,
      builder: (context, metaSnapshot) {
        return buildWithPlace(metaSnapshot.data);
      },
    );
  }
}
