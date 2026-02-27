part of 'chat_page.dart';

extension _ChatPageStateMethodsHMessageAttachments on _ChatPageState {
  double _estimateAttachmentPreviewWidth(Attachment attachment) {
    final normalizedMime = attachment.mimeType.trim().toLowerCase();
    final usesThumbnail = normalizedMime.startsWith('image/') ||
        normalizedMime == kSecondLoopVideoManifestMimeType;
    if (usesThumbnail) {
      // 180px preview + 1px border on each side.
      return 180 + 2;
    }
    // AttachmentCard uses maxWidth=220 with the same SlSurface border.
    return 220 + 2;
  }

  bool _messageHasAttachmentInCache(String messageId) {
    if (_attachmentLinkingMessageIds.contains(messageId)) {
      return true;
    }

    final cached = _attachmentsCacheByMessageId[messageId];
    return cached != null && cached.isNotEmpty;
  }

  Future<List<Attachment>> _loadMessageAttachmentsForUi({
    required String messageId,
    required AttachmentsBackend attachmentsBackend,
    required Uint8List sessionKey,
  }) {
    final existingFuture = _attachmentsFuturesByMessageId[messageId];
    if (existingFuture != null) return existingFuture;

    late final Future<List<Attachment>> future;
    future = attachmentsBackend
        .listMessageAttachments(
      sessionKey,
      messageId,
    )
        .then((items) {
      if (items.isEmpty && _attachmentLinkingMessageIds.contains(messageId)) {
        return _attachmentsCacheByMessageId[messageId] ?? const <Attachment>[];
      }
      _attachmentsCacheByMessageId[messageId] = items;
      return items;
    }).catchError((_) {
      if (identical(_attachmentsFuturesByMessageId[messageId], future)) {
        _attachmentsFuturesByMessageId.remove(messageId);
      }
      return const <Attachment>[];
    });

    _attachmentsFuturesByMessageId[messageId] = future;
    return future;
  }

  Future<List<Attachment>> _loadMessageAttachmentsForEditCheck(
    String messageId,
  ) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! AttachmentsBackend) {
      return const <Attachment>[];
    }
    final backend = backendAny as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    return _loadMessageAttachmentsForUi(
      messageId: messageId,
      attachmentsBackend: backend,
      sessionKey: sessionKey,
    );
  }

  Future<bool> _messageHasAttachment(String messageId) async {
    if (_messageHasAttachmentInCache(messageId)) {
      return true;
    }
    final items = await _loadMessageAttachmentsForEditCheck(messageId);
    return items.isNotEmpty;
  }

  Future<bool> _canEditMessage(Message message) async {
    if (_isTransientPendingMessage(message)) return false;
    if (message.role != 'user' || message.id == _kFailedAskMessageId) {
      return false;
    }
    final hasAttachment = await _messageHasAttachment(message.id);
    return !hasAttachment;
  }

  Widget _buildMessageAttachmentSection({
    required BuildContext context,
    required Message message,
    required bool isUser,
    required ColorScheme colorScheme,
    required bool hasContentAboveAttachments,
    required AttachmentsBackend attachmentsBackend,
    required Uint8List sessionKey,
    required Map<String, AttachmentAnnotationJob> annotationJobsBySha256,
  }) {
    return FutureBuilder(
      initialData: _attachmentsCacheByMessageId[message.id],
      future: _loadMessageAttachmentsForUi(
        messageId: message.id,
        attachmentsBackend: attachmentsBackend,
        sessionKey: sessionKey,
      ),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Attachment>[];
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: EdgeInsets.only(
            top: hasContentAboveAttachments ? 8 : 0,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 8.0;
              Widget buildAttachmentTile(
                Attachment attachment,
              ) {
                final normalizedMime = attachment.mimeType.trim().toLowerCase();
                final useVisualThumbnail =
                    normalizedMime.startsWith('image/') ||
                        normalizedMime == kSecondLoopVideoManifestMimeType;
                if (useVisualThumbnail) {
                  return ChatImageAttachmentThumbnail(
                    key: ValueKey(
                      'chat_attachment_image_${attachment.sha256}',
                    ),
                    attachment: attachment,
                    attachmentsBackend: attachmentsBackend,
                    onTap: () => unawaited(_openAttachmentDetail(attachment)),
                  );
                }
                return AttachmentCard(
                  attachment: attachment,
                  annotationJob: annotationJobsBySha256[attachment.sha256],
                  onTap: () => unawaited(_openAttachmentDetail(attachment)),
                );
              }

              final targetColumns = constraints.maxWidth >= 520 ? 2 : 1;
              final gridTileMaxWidth = targetColumns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - spacing) / 2;
              final singleTileMaxWidth =
                  _estimateAttachmentPreviewWidth(items.first)
                      .clamp(0.0, constraints.maxWidth)
                      .toDouble();

              Widget attachmentsLayout;
              if (items.length > 1) {
                attachmentsLayout = Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final attachment in items)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: gridTileMaxWidth,
                        ),
                        child: buildAttachmentTile(attachment),
                      ),
                  ],
                );
              } else {
                attachmentsLayout = ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: singleTileMaxWidth),
                  child: buildAttachmentTile(items.first),
                );
              }

              Attachment? firstImage;
              for (final a in items) {
                if (a.mimeType.startsWith('image/')) {
                  firstImage = a;
                  break;
                }
              }

              final imageSha256 = firstImage?.sha256;
              final double? enrichmentWidth = firstImage == null
                  ? null
                  : _estimateAttachmentPreviewWidth(firstImage)
                      .clamp(0.0, constraints.maxWidth)
                      .toDouble();

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    key: ValueKey('chat_message_attachments_${message.id}'),
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: attachmentsLayout,
                  ),
                  if (imageSha256 != null && enrichmentWidth != null)
                    FutureBuilder(
                      initialData:
                          _attachmentEnrichmentCacheBySha256[imageSha256],
                      future: _attachmentEnrichmentFuturesBySha256.putIfAbsent(
                        imageSha256,
                        () => _loadAttachmentEnrichment(
                          attachmentsBackend,
                          sessionKey,
                          imageSha256,
                        ).then((value) {
                          _attachmentEnrichmentCacheBySha256[imageSha256] =
                              value;
                          return value;
                        }),
                      ),
                      builder: (context, snapshot) {
                        final enrichment = snapshot.data;
                        final place = enrichment?.placeDisplayName?.trim();
                        final caption = enrichment?.captionLong?.trim();

                        final hasPlace = place != null && place.isNotEmpty;
                        final hasCaption =
                            caption != null && caption.isNotEmpty;
                        if (!hasPlace && !hasCaption) {
                          return const SizedBox.shrink();
                        }

                        final textStyle =
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isUser
                                      ? colorScheme.onPrimaryContainer
                                          .withOpacity(0.78)
                                      : colorScheme.onSurfaceVariant
                                          .withOpacity(0.86),
                                );

                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: enrichmentWidth,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasPlace)
                                  Text(
                                    place,
                                    key: ValueKey(
                                      'chat_image_enrichment_location_$imageSha256',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyle,
                                  ),
                                if (hasPlace && hasCaption)
                                  const SizedBox(height: 2),
                                if (hasCaption)
                                  Text(
                                    caption,
                                    key: ValueKey(
                                      'chat_image_enrichment_caption_$imageSha256',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyle,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
