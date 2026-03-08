part of 'chat_page.dart';

extension _ChatPageStateMethodsBAttachments on _ChatPageState {
  bool _looksLikeHttpUrlText(String raw) {
    return looksLikeHttpUrlText(raw);
  }

  String? _readUrlFromManifestDraft(AttachmentDraftPayload draft) {
    return readUrlFromManifestDraft(draft);
  }

  Future<void> _consumePendingSharedUrlDrafts() async {
    if (!mounted) return;
    if (!_supportsCamera) return;
    if (widget.conversation.id != 'loop_home') return;

    final urls = await ShareDraftInbox.consumePendingUrls();
    if (urls.isEmpty) return;

    final drafts = <AttachmentDraftPayload>[];
    for (final url in urls) {
      final normalized = url.trim();
      if (!_looksLikeHttpUrlText(normalized)) continue;
      drafts.add(
        buildUrlManifestDraftPayload(
          localId: _nextComposerAttachmentDraftLocalId(),
          url: normalized,
        ),
      );
    }
    if (drafts.isEmpty || !mounted) return;
    _appendComposerAttachmentDrafts(drafts);
  }

  Future<bool> _trySendTextAsUrlAttachment(String text) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return false;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);

    final sent = await trySendUrlManifestAttachment(
      text: text,
      backend: backend,
      sessionKey: sessionKey,
      linkCreatedAttachment: (attachmentSha256, normalizedUrl) async {
        final message = await backend.insertMessage(
          sessionKey,
          widget.conversation.id,
          role: 'user',
          content: normalizedUrl,
        );
        await backend.linkAttachmentToMessage(
          sessionKey,
          message.id,
          attachmentSha256: attachmentSha256,
        );
      },
    );
    if (!sent) return false;

    syncEngine?.notifyLocalMutation();
    if (!mounted) return true;
    _refreshAfterAttachmentMutation();
    return true;
  }

  String _nextComposerAttachmentDraftLocalId() {
    _composerAttachmentDraftSeq += 1;
    return 'chat_draft_$_composerAttachmentDraftSeq';
  }

  void _removeComposerAttachmentDraft(String localId) {
    if (_composerDraftAttachments.isEmpty) return;
    _setState(() {
      _composerDraftAttachments = _composerDraftAttachments
          .where((draft) => draft.localId != localId)
          .toList(growable: false);
      _failedComposerDraftLocalIds.remove(localId);
    });
  }

  void _appendComposerAttachmentDrafts(List<AttachmentDraftPayload> drafts) {
    if (drafts.isEmpty) return;
    final merged = dedupeAttachmentDraftPayloads(
      <AttachmentDraftPayload>[..._composerDraftAttachments, ...drafts],
    );
    final incomingIds = drafts.map((draft) => draft.localId).toSet();
    _setState(() {
      _composerDraftAttachments = merged;
      _failedComposerDraftLocalIds
          .removeWhere((localId) => incomingIds.contains(localId));
    });
  }

  Future<void> _addDesktopFilePayloadsToComposerDraft(
    List<({String filename, Uint8List bytes})> payloads,
  ) async {
    final drafts = buildDesktopAttachmentDraftPayloads(
      payloads,
      nextLocalId: _nextComposerAttachmentDraftLocalId,
    );
    _appendComposerAttachmentDrafts(drafts);
  }

  Future<void> _addDroppedDesktopFilesToComposerDraft(
    List<XFile> droppedFiles,
  ) async {
    if (_isComposerBusy) return;
    if (!_isDesktopPlatform) return;
    if (droppedFiles.isEmpty) return;

    _setState(() {
      _attachingMedia = true;
      _desktopDropActive = false;
    });
    try {
      final payloads = <({String filename, Uint8List bytes})>[];
      for (final dropped in droppedFiles) {
        final bytes = await dropped.readAsBytes();
        if (bytes.isEmpty) continue;
        final filename = dropped.name.trim().isEmpty
            ? 'attachment.bin'
            : dropped.name.trim();
        payloads.add((filename: filename, bytes: bytes));
      }
      if (payloads.isEmpty) {
        throw Exception('drop payload contains no readable files');
      }
      await _addDesktopFilePayloadsToComposerDraft(payloads);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.photoFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        _setState(() {
          _attachingMedia = false;
        });
      }
    }
  }

  Future<String> _ingestComposerDraftAttachment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    AttachmentDraftPayload draft,
  ) async {
    final normalizedMimeType = draft.normalizedMimeType;
    if (normalizedMimeType.toLowerCase().startsWith('image/')) {
      final lang = Localizations.localeOf(context).toLanguageTag();
      final ingested = await ingestImageAttachmentBytes(
        backend: backend,
        sessionKey: sessionKey,
        rawBytes: draft.bytes,
        inferredMimeType: normalizedMimeType,
        lang: lang,
        onBackupCandidate: (attachmentSha256) async {
          try {
            await _maybeEnqueueCloudMediaBackup(
              backend,
              sessionKey,
              attachmentSha256,
            );
          } catch (_) {}
        },
      );
      return ingested.attachmentSha256;
    }

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final ingestOptions = await resolveFileAttachmentIngestOptions(
      sessionKey: sessionKey,
      mimeType: normalizedMimeType,
      subscriptionStatus: subscriptionStatus,
    );

    return ingestFileAttachmentBytes(
      backend: backend,
      sessionKey: sessionKey,
      rawBytes: draft.bytes,
      mimeType: normalizedMimeType,
      options: ingestOptions,
      onBackupCandidate: (backupSha) async {
        try {
          await _maybeEnqueueCloudMediaBackup(backend, sessionKey, backupSha);
        } catch (_) {}
      },
    );
  }

  Future<void> _enqueueDraftAttachmentPostLinkEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256,
    AttachmentDraftPayload draft,
  ) async {
    await runDraftAttachmentPostLinkEnrichment(
      backend: backend,
      sessionKey: sessionKey,
      attachmentSha256: attachmentSha256,
      draft: draft,
      lang: Localizations.localeOf(context).toLanguageTag(),
      beforeEnqueueImageAnnotation: () => bestEffortWarmCloudCapabilityAuth(
        CloudAuthScope.maybeOf(context)?.controller,
      ),
      beforeEnqueueAudioTranscribe: () => bestEffortWarmCloudCapabilityAuth(
        CloudAuthScope.maybeOf(context)?.controller,
      ),
    );
  }

  void _refreshAfterAttachmentMutation() {
    _refresh();
    if (!_usePagination) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }
}
