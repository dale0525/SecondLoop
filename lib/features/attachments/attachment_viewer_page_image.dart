part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageImage on _AttachmentViewerPageState {
  Widget _buildImageAttachmentDetail(Uint8List bytes) {
    final exifFromBytes = tryReadImageExifMetadata(bytes);

    Widget buildContent(
      AttachmentExifMetadata? persisted,
      String? placeDisplayName,
      String? annotationCaption,
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

      final hasAnnotation = (annotationCaption ?? '').trim().isNotEmpty;
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
                    captionLong: annotationCaption!,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildWithAnnotation(
      AttachmentExifMetadata? persisted,
      String? placeDisplayName,
    ) {
      final annotationFuture = _annotationCaptionFuture;
      if (annotationFuture == null) {
        return buildContent(persisted, placeDisplayName, null);
      }

      return FutureBuilder<String?>(
        future: annotationFuture,
        initialData: _annotationCaption,
        builder: (context, annotationSnapshot) {
          return buildContent(
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
