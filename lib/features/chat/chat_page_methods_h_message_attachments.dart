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

  double _estimateAttachmentRowWidth(
    List<Attachment> items, {
    double spacing = 8,
  }) {
    var sum = 0.0;
    for (var i = 0; i < items.length; i++) {
      sum += _estimateAttachmentPreviewWidth(items[i]);
      if (i != items.length - 1) sum += spacing;
    }
    return sum;
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
}
