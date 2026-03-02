part of 'chat_page.dart';

extension _ChatPageStateMethodsB on _ChatPageState {
  void _showAskAiFailure(String question, {String? message}) {
    final failureMessage = message ?? context.t.chat.askAiFailedTemporary;
    unawaited(AskAiForegroundService.stopIfSupported());

    _setState(() {
      _askError = null;
      _askSub = null;
      _asking = false;
      _stopRequested = false;
      _pendingQuestion = null;
      _streamingAnswer = '';
      _askFailureQuestion = question;
      _askFailureMessage = failureMessage;
      _askFailureCreatedAtMs =
          _askAttemptCreatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
      _askFailureAnchorMessageId = _askAttemptAnchorMessageId;
      _askAttemptCreatedAtMs = null;
      _askAttemptAnchorMessageId = null;
    });
  }

  Future<void> _retryAskAiFailedQuestion() async {
    if (_asking || _sending) return;
    final question = _askFailureQuestion?.trim() ?? '';
    if (question.isEmpty) return;

    _setState(() {
      _askFailureQuestion = null;
      _askFailureMessage = null;
      _askFailureCreatedAtMs = null;
      _askFailureAnchorMessageId = null;
    });

    await _askAi(questionOverride: question);
  }

  String? _latestCommittedMessageId() {
    if (_latestLoadedMessages.isEmpty) return null;

    Message latest = _latestLoadedMessages.first;
    for (var i = 1; i < _latestLoadedMessages.length; i++) {
      final candidate = _latestLoadedMessages[i];
      if (candidate.createdAtMs >= latest.createdAtMs) {
        latest = candidate;
      }
    }
    return latest.id;
  }

  bool _messagesNewestFirst(List<Message> messages) {
    if (messages.length < 2) return _usePagination;
    return messages.first.createdAtMs >= messages.last.createdAtMs;
  }

  List<Message> _messagesWithFailedAskQuestion(List<Message> source) {
    final question = _askFailureQuestion;
    final failureMessage = _askFailureMessage;
    if (question == null || failureMessage == null) return source;

    final failed = Message(
      id: _kFailedAskMessageId,
      conversationId: widget.conversation.id,
      role: 'user',
      content: question,
      createdAtMs:
          _askFailureCreatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      isMemory: false,
    );
    final list = List<Message>.from(source);
    if (list.isEmpty) {
      list.add(failed);
      return list;
    }

    final anchorId = _askFailureAnchorMessageId;
    final newestFirst = _messagesNewestFirst(list);
    if (anchorId == null) {
      if (newestFirst) {
        list.add(failed);
      } else {
        list.insert(0, failed);
      }
      return list;
    }

    final anchorIndex = list.indexWhere((m) => m.id == anchorId);
    if (anchorIndex == -1) {
      if (newestFirst) {
        list.insert(0, failed);
      } else {
        list.add(failed);
      }
      return list;
    }

    final insertAt = newestFirst ? anchorIndex : anchorIndex + 1;
    list.insert(insertAt.clamp(0, list.length).toInt(), failed);
    return list;
  }

  Future<List<Message>> _loadMessages() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    if (_usePagination &&
        _selectedTagFilterIds.isEmpty &&
        _selectedTagExcludeIds.isEmpty) {
      final page = await backend.listMessagesPage(
        sessionKey,
        widget.conversation.id,
        limit: _kMessagePageSize,
      );
      if (mounted) {
        _setState(() {
          _paginatedMessages = page;
          _latestLoadedMessages = page;
          _hasMoreMessages = page.length == _kMessagePageSize;
          _loadingMoreMessages = false;
        });
      } else {
        _latestLoadedMessages = page;
      }
      return page;
    }

    final list = await backend.listMessages(sessionKey, widget.conversation.id);
    final filtered = await _filterMessagesBySelectedTags(sessionKey, list);

    if (_usePagination) {
      if (mounted) {
        _setState(() {
          _paginatedMessages = filtered;
          _latestLoadedMessages = filtered;
          _hasMoreMessages = false;
          _loadingMoreMessages = false;
        });
      } else {
        _latestLoadedMessages = filtered;
      }
      return filtered;
    }

    _latestLoadedMessages = filtered;
    return filtered;
  }

  Future<void> _loadOlderMessages() async {
    if (!_usePagination) return;
    if (_selectedTagFilterIds.isNotEmpty || _selectedTagExcludeIds.isNotEmpty) {
      return;
    }
    if (_loadingMoreMessages || !_hasMoreMessages) return;
    if (_paginatedMessages.isEmpty) return;

    final oldest = _paginatedMessages.last;
    _setState(() => _loadingMoreMessages = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final page = await backend.listMessagesPage(
        sessionKey,
        widget.conversation.id,
        beforeCreatedAtMs: oldest.createdAtMs,
        beforeId: oldest.id,
        limit: _kMessagePageSize,
      );
      if (!mounted) return;

      _setState(() {
        if (page.isEmpty) {
          _hasMoreMessages = false;
        } else {
          final existingIds =
              _paginatedMessages.map((message) => message.id).toSet();
          final deduped = page
              .where((message) => !existingIds.contains(message.id))
              .toList(growable: false);
          _paginatedMessages = <Message>[..._paginatedMessages, ...deduped];
          _latestLoadedMessages = _paginatedMessages;
          _hasMoreMessages = page.length == _kMessagePageSize;
        }
        _loadingMoreMessages = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setState(() => _loadingMoreMessages = false);
    }
  }

  Future<void> _jumpToLatest() async {
    if (_hasUnseenNewMessages) {
      _refresh();
      final future = _messagesFuture;
      if (future != null) {
        try {
          await future;
        } catch (_) {
          // ignore
        }
      }
    }

    if (!mounted) return;
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );

    if (!mounted) return;
    _setState(() {
      _hasUnseenNewMessages = false;
      _isAtBottom = true;
    });
  }

  Future<TaskHubSummary> _loadTaskHubSummary() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    late final ActionsSettings settings;
    try {
      settings = await ActionsSettingsStore.load();
    } catch (_) {
      settings = const ActionsSettings(
        morningTime: TimeOfDay(hour: 8, minute: 0),
        dayEndTime: TimeOfDay(hour: 21, minute: 0),
        weeklyReviewTime: TimeOfDay(hour: 21, minute: 0),
      );
    }

    final nowLocal = DateTime.now();
    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return const TaskHubSummary.empty();
    }

    final normalizedTodos = <Todo>[];
    var didMutate = false;

    for (final todo in todos) {
      final nextMs = todo.nextReviewAtMs;
      final stage = todo.reviewStage;
      if (nextMs == null || stage == null) {
        normalizedTodos.add(todo);
        continue;
      }

      final scheduledLocal =
          DateTime.fromMillisecondsSinceEpoch(nextMs, isUtc: true).toLocal();
      final rolled = ReviewBackoff.rollForwardUntilDueOrFuture(
        stage: stage,
        scheduledAtLocal: scheduledLocal,
        nowLocal: nowLocal,
        settings: settings,
      );
      if (rolled.stage != stage || rolled.nextReviewAtLocal != scheduledLocal) {
        try {
          final updated = await backend.upsertTodo(
            sessionKey,
            id: todo.id,
            title: todo.title,
            dueAtMs: todo.dueAtMs,
            status: todo.status,
            sourceEntryId: todo.sourceEntryId,
            reviewStage: rolled.stage,
            nextReviewAtMs:
                rolled.nextReviewAtLocal.toUtc().millisecondsSinceEpoch,
            lastReviewAtMs: todo.lastReviewAtMs,
          );
          normalizedTodos.add(updated);
          didMutate = true;
          continue;
        } catch (_) {
          normalizedTodos.add(todo);
          continue;
        }
      }

      normalizedTodos.add(todo);
    }

    if (didMutate) {
      syncEngine?.notifyLocalMutation();
    }

    return TaskHubSummary.fromTodos(
      normalizedTodos,
      nowLocal: nowLocal,
      scheduledPreviewLimit: 4,
      unscheduledPreviewLimit: 4,
    );
  }

  Future<List<TodoThreadMatch>> _resolveTodoSemanticMatchesForSendFlow(
    AppBackend backend,
    Uint8List sessionKey, {
    required String query,
    required int topK,
    bool requireCloud = false,
  }) async {
    final localMatches = await _searchLocalTodoSemanticMatches(
      backend,
      sessionKey,
      query: query,
      topK: topK,
    );
    if (_isVeryHighConfidenceTodoSemanticMatch(localMatches)) {
      return localMatches;
    }

    final remoteMatches = await _searchRemoteTodoSemanticMatches(
      backend,
      sessionKey,
      query: query,
      topK: topK,
      requireCloud: requireCloud,
    );
    if (remoteMatches.isNotEmpty) return remoteMatches;
    return localMatches;
  }

  Future<List<TodoThreadMatch>> _searchLocalTodoSemanticMatches(
    AppBackend backend,
    Uint8List sessionKey, {
    required String query,
    required int topK,
  }) async {
    try {
      return await backend.searchSimilarTodoThreads(
        sessionKey,
        query,
        topK: topK,
      );
    } catch (_) {
      return const <TodoThreadMatch>[];
    }
  }

  Future<List<TodoThreadMatch>> _searchRemoteTodoSemanticMatches(
    AppBackend backend,
    Uint8List sessionKey, {
    required String query,
    required int topK,
    bool requireCloud = false,
  }) async {
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

    String? cloudIdToken;
    try {
      cloudIdToken = await cloudAuthScope?.controller.getIdToken();
    } catch (_) {
      cloudIdToken = null;
    }

    final cloudAvailable = subscriptionStatus == SubscriptionStatus.entitled &&
        cloudIdToken != null &&
        cloudIdToken.trim().isNotEmpty &&
        cloudGatewayConfig.baseUrl.trim().isNotEmpty;

    if (cloudAvailable) {
      if (!_cloudEmbeddingsConsented) {
        return const <TodoThreadMatch>[];
      }
      try {
        return await backend.searchSimilarTodoThreadsCloudGateway(
          sessionKey,
          query,
          topK: topK,
          gatewayBaseUrl: cloudGatewayConfig.baseUrl,
          idToken: cloudIdToken,
          modelName: _kCloudEmbeddingsModelName,
        );
      } catch (_) {
        return const <TodoThreadMatch>[];
      }
    }

    if (requireCloud) return const <TodoThreadMatch>[];

    try {
      return await backend.searchSimilarTodoThreadsBrok(
        sessionKey,
        query,
        topK: topK,
      );
    } catch (_) {
      return const <TodoThreadMatch>[];
    }
  }

  void _refresh() {
    _setState(() {
      if (_usePagination) {
        _loadingMoreMessages = false;
        _hasMoreMessages = true;
      }
      _messagesFuture = _loadMessages();
      _taskHubSummaryFuture = _loadTaskHubSummary();
      _attachmentsFuturesByMessageId.clear();
      _attachmentEnrichmentFuturesBySha256.clear();
    });
  }

  Future<void> _send() async {
    if (_isComposerBusy) return;

    final text = _controller.text.trim();
    final draftsSnapshot =
        List<AttachmentDraftPayload>.from(_composerDraftAttachments);
    if (text.isEmpty && draftsSnapshot.isEmpty) return;

    _setState(() {
      _sending = true;
      _showAttachmentSendFeedback = draftsSnapshot.isNotEmpty;
    });
    try {
      final backendAny = AppBackendScope.of(context);
      final backend = backendAny;
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      Message? sentMessage;
      SendDraftResult? draftResult;
      var sentAsUrlAttachment = false;

      if (draftsSnapshot.isEmpty && text.isNotEmpty) {
        sentAsUrlAttachment = await _trySendTextAsUrlAttachment(text);
      }

      if (!sentAsUrlAttachment && draftsSnapshot.isNotEmpty) {
        if (backendAny is! NativeAppBackend) {
          throw StateError('native_backend_required_for_attachment_drafts');
        }
        final nativeBackend = backendAny;
        const coordinator = AttachmentDraftSendCoordinator();
        draftResult = await coordinator.send(
          text: text,
          drafts: draftsSnapshot,
          createUserMessage: (content) async {
            final created = await backend.insertMessage(
              sessionKey,
              widget.conversation.id,
              role: 'user',
              content: content,
            );
            sentMessage ??= created;
            return created;
          },
          ingestAttachment: (draft) =>
              _ingestComposerDraftAttachment(nativeBackend, sessionKey, draft),
          linkAttachmentToMessage: (messageId, attachmentSha256) =>
              nativeBackend.linkAttachmentToMessage(
            sessionKey,
            messageId,
            attachmentSha256: attachmentSha256,
          ),
          onAttachmentLinked: (attachmentSha256, draft) async {
            try {
              final urlFromManifest = _readUrlFromManifestDraft(draft);
              unawaited(
                _enqueueDraftAttachmentPostLinkEnrichment(
                  nativeBackend,
                  sessionKey,
                  attachmentSha256,
                  draft,
                ).catchError((_) {}),
              );
              unawaited(
                const RustAttachmentMetadataStore()
                    .upsert(
                      sessionKey,
                      attachmentSha256: attachmentSha256,
                      title: urlFromManifest,
                      filenames: [draft.normalizedFilename],
                      sourceUrls: urlFromManifest == null
                          ? const <String>[]
                          : <String>[urlFromManifest],
                    )
                    .catchError((_) {}),
              );
            } catch (_) {}
          },
        );
      } else if (!sentAsUrlAttachment) {
        sentMessage = await backend.insertMessage(
          sessionKey,
          widget.conversation.id,
          role: 'user',
          content: text,
        );
      }

      if (draftResult != null && mounted) {
        final failedDrafts = dedupeAttachmentDraftPayloads(
          draftResult.failedItems
              .map((failed) => failed.payload)
              .toList(growable: false),
        );
        _setState(() {
          _composerDraftAttachments = failedDrafts;
          _failedComposerDraftLocalIds =
              failedDrafts.map((draft) => draft.localId).toSet();
        });
      } else if (draftsSnapshot.isNotEmpty && mounted) {
        _setState(() {
          _composerDraftAttachments = <AttachmentDraftPayload>[];
          _failedComposerDraftLocalIds = <String>{};
        });
      }

      final didMutate = !sentAsUrlAttachment &&
          (sentMessage != null ||
              (draftResult != null &&
                  (draftResult.messageId != null ||
                      draftResult.linkedAttachmentShas.isNotEmpty)));
      if (didMutate) {
        syncEngine?.notifyLocalMutation();
        if (mounted) {
          _refresh();
          if (_usePagination) {
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
      }

      if (!mounted) return;
      final shouldClearComposer = sentAsUrlAttachment ||
          sentMessage != null ||
          (draftResult?.messageId != null);
      if (shouldClearComposer) {
        _controller.clear();
        if (_isDesktopPlatform) {
          _inputFocusNode.requestFocus();
        }
      }

      if (sentMessage != null && text.isNotEmpty) {
        final committedMessage = sentMessage!;
        _messageAutoActionsQueue ??= MessageAutoActionsQueue(
          backend: backend,
          sessionKey: sessionKey,
          handler: _handleMessageAutoActions,
        );
        _messageAutoActionsQueue!.enqueue(
          message: committedMessage,
          rawText: text,
          createdAtMs: committedMessage.createdAtMs,
        );
      }
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
          _sending = false;
          _showAttachmentSendFeedback = false;
        });
      }
    }
  }

  String _inferImageMimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  Future<void> _maybeEnqueueCloudMediaBackup(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256,
  ) async {
    final store = SyncConfigStore();
    final backendType = await store.readBackendType();
    if (backendType != SyncBackendType.managedVault &&
        backendType != SyncBackendType.webdav) {
      return;
    }

    final enabled = await store.readCloudMediaBackupEnabled();
    if (!enabled) return;

    await backend.enqueueCloudMediaBackup(
      sessionKey,
      attachmentSha256: attachmentSha256,
      desiredVariant: 'original',
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _maybeEnqueueAttachmentPlaceEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String lang,
  }) async {
    try {
      await backend.enqueueAttachmentPlace(
        sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _maybeEnqueueAttachmentAnnotationEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String lang,
  }) async {
    MediaAnnotationConfig? config;
    try {
      config = await const RustMediaAnnotationConfigStore().read(sessionKey);
    } catch (_) {
      config = null;
    }
    if (config == null || !config.annotateEnabled) return;

    try {
      await backend.enqueueAttachmentAnnotation(
        sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (mounted) {
        _setState(() {});
      }
    } catch (_) {
      return;
    }
  }

  Future<_AttachmentEnrichment> _loadAttachmentEnrichment(
    AttachmentsBackend backend,
    Uint8List sessionKey,
    String attachmentSha256,
  ) async {
    final placeFuture = backend
        .readAttachmentPlaceDisplayName(
          sessionKey,
          sha256: attachmentSha256,
        )
        .catchError((_) => null);
    final captionFuture = backend
        .readAttachmentAnnotationCaptionLong(
          sessionKey,
          sha256: attachmentSha256,
        )
        .catchError((_) => null);
    return _AttachmentEnrichment(
      placeDisplayName: await placeFuture,
      captionLong: await captionFuture,
    );
  }

  Future<void> _pickAndSendMedia() async {
    return _pickAndSendAttachmentFromFile();
  }

  Future<void> _openAttachmentSheet() async {
    if (_sending) return;
    if (_asking) return;
    if (_recordingAudio) return;
    if (!_supportsImageUpload && !_supportsAudioRecording) return;

    if (_isDesktopPlatform) {
      await _pickAndSendAttachmentFromFile();
      return;
    }

    await _showModalBottomSheetFromChat<void>(
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('chat_attach_pick_media'),
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(context.t.chat.attachPickMedia),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_pickAndSendMedia());
                },
              ),
              if (_supportsCamera)
                ListTile(
                  key: const ValueKey('chat_attach_take_photo'),
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: Text(context.t.chat.attachTakePhoto),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_captureAndAttachPhoto());
                  },
                ),
              if (_supportsAudioRecording)
                ListTile(
                  key: const ValueKey('chat_attach_record_audio'),
                  leading: const Icon(Icons.mic_rounded),
                  title: Text(context.t.chat.attachRecordAudio),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_recordAndAttachAudioFromSheet());
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _captureAndAttachPhoto() async {
    if (_isComposerBusy) return;
    if (!_supportsCamera) return;

    _setState(() {
      _attachingMedia = true;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        requestFullMetadata: true,
      );
      if (picked == null) return;
      final rawBytes = await picked.readAsBytes();
      if (rawBytes.isEmpty) {
        throw Exception('camera_photo_bytes_empty');
      }
      final inferredMimeType = _inferImageMimeTypeFromPath(picked.path);
      final pickedFilename = (() {
        final byName = picked.name.trim();
        if (byName.isNotEmpty) return byName;
        final normalizedPath = picked.path.trim().replaceAll('\\', '/');
        if (normalizedPath.isEmpty) return '';
        return normalizedPath.split('/').last.trim();
      })();
      final resolvedFilename =
          pickedFilename.trim().isEmpty ? 'photo.jpg' : pickedFilename.trim();

      _appendComposerAttachmentDrafts(
        <AttachmentDraftPayload>[
          AttachmentDraftPayload(
            localId: _nextComposerAttachmentDraftLocalId(),
            filename: resolvedFilename,
            mimeType: inferredMimeType,
            bytes: rawBytes,
          ),
        ],
      );
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

  Future<void> _pickAndSendAttachmentFromFile() async {
    if (_isComposerBusy) return;

    _setState(() {
      _attachingMedia = true;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final payloads = <({String filename, Uint8List bytes})>[];
      for (final file in picked.files) {
        var bytes = file.bytes;
        final path = file.path?.trim();
        if ((bytes == null || bytes.isEmpty) &&
            path != null &&
            path.isNotEmpty) {
          bytes = await XFile(path).readAsBytes();
        }
        if (bytes == null || bytes.isEmpty) continue;
        payloads.add((filename: file.name, bytes: bytes));
      }
      if (payloads.isEmpty) {
        throw Exception('file_picker returned no readable file data');
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
}
