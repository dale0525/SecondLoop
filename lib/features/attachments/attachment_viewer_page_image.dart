part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageImage on _AttachmentViewerPageState {
  Widget _buildImageAttachmentDetail(Uint8List bytes) {
    final exifFromBytes = tryReadImageExifMetadata(bytes);

    String resolveImageOcrText(Map<String, Object?>? payload) {
      if (payload == null) return '';

      String read(String key) {
        return (payload[key] ?? '').toString().trim();
      }

      final ocrText = read('ocr_text');
      if (ocrText.isNotEmpty) return ocrText;

      final full = read('ocr_text_full');
      if (full.isNotEmpty) return full;

      return read('ocr_text_excerpt');
    }

    Widget buildImageOcrCard(String ocrText) {
      return SlSurface(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t.attachments.content.ocrTitle,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(
              ocrText,
              key: const ValueKey('attachment_annotation_ocr_text'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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

      final caption = (annotationCaption ?? '').trim();
      final hasAnnotation = caption.isNotEmpty;
      final ocrText = resolveImageOcrText(annotationPayload);
      final hasOcrText = ocrText.isNotEmpty;
      final showOcrText = hasOcrText && ocrText != caption;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: SingleChildScrollView(
            key: const ValueKey('attachment_image_detail_scroll'),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const SizedBox(height: 12),
                _buildMetadataCard(
                  context,
                  byteLen: widget.attachment.byteLen.toInt(),
                  capturedAt: capturedAt,
                  latitude: latitude,
                  longitude: longitude,
                  placeDisplayName: placeDisplayName,
                ),
                if (hasAnnotation) const SizedBox(height: 12),
                if (hasAnnotation)
                  _buildAnnotationCard(
                    context,
                    captionLong: caption,
                  ),
                if (showOcrText) const SizedBox(height: 12),
                if (showOcrText) buildImageOcrCard(ocrText),
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
