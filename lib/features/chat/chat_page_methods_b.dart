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

  List<Message> _normalizeMessagesForList(List<Message> messages) {
    if (!_usePagination || messages.length < 2) return messages;
    final newestFirst = messages.first.createdAtMs >= messages.last.createdAtMs;
    if (newestFirst) return messages;
    return messages.reversed.toList(growable: false);
  }

  String _messageSupplementCacheKeyFor(List<Message> messages) {
    final key = StringBuffer(widget.conversation.id);
    for (final message in messages) {
      if (message.id.startsWith('pending_')) continue;
      key
        ..write('|')
        ..write(message.id)
        ..write('@')
        ..write(message.createdAtMs);
    }
    return key.toString();
  }

  Future<_ChatMessageSupplementData> _loadChatMessageSupplementData({
    required AppBackend backend,
    required Uint8List sessionKey,
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) {
      return (
        semanticJobs: const <SemanticParseJob>[],
        linkedTodoBadges: const <String, _TodoMessageBadgeMeta>{},
        existingTodoIds: const <String>{},
        annotationJobs: const <AttachmentAnnotationJob>[],
        attachmentAnnotationEnabled: false,
        attachmentAnnotationCanRunNow: false,
        audioTranscribeEnabled: false,
        audioTranscribeCanRunNow: false,
      );
    }

    final ids = messages
        .map((m) => m.id)
        .where((id) => !id.startsWith('pending_'))
        .toList(growable: false);

    final semanticJobsFuture = Future<List<SemanticParseJob>>.sync(() async {
      if (ids.isEmpty) return const <SemanticParseJob>[];

      final prefs = await SharedPreferences.getInstance();
      final semanticParseConsented =
          prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false;
      if (!semanticParseConsented) return const <SemanticParseJob>[];

      return backend.listSemanticParseJobsByMessageIds(
        sessionKey,
        messageIds: ids,
      );
    }).catchError((_) => const <SemanticParseJob>[]);

    final nativeBackend = backend is NativeAppBackend ? backend : null;
    final annotationJobsFuture = Future<List<AttachmentAnnotationJob>>.sync(() {
      if (nativeBackend == null) return const <AttachmentAnnotationJob>[];

      return nativeBackend.listDueAttachmentAnnotations(
        sessionKey,
        nowMs: kPlatformSafeJsInt,
        limit: 500,
      );
    }).catchError((_) => const <AttachmentAnnotationJob>[]);

    final linkedTodoBadgeFuture = _loadLinkedTodoBadgesForMessages(
      backend: backend,
      sessionKey: sessionKey,
      messages: messages,
    );

    final semanticJobs = await semanticJobsFuture;
    final annotationJobs = await annotationJobsFuture;
    final linkedTodoBadgeData = await linkedTodoBadgeFuture;
    final annotationUi = nativeBackend == null || annotationJobs.isEmpty
        ? (enabled: false, canRunNow: false)
        : await _loadAttachmentAnnotationUiState(
            nativeBackend,
            sessionKey,
          ).catchError((_) => (enabled: false, canRunNow: false));
    final audioUi = nativeBackend == null || annotationJobs.isEmpty
        ? (enabled: false, canRunNow: false)
        : await _loadAudioTranscribeUiState(
            nativeBackend,
            sessionKey,
          ).catchError((_) => (enabled: false, canRunNow: false));

    return (
      semanticJobs: semanticJobs,
      linkedTodoBadges: linkedTodoBadgeData.badges,
      existingTodoIds: linkedTodoBadgeData.existingTodoIds,
      annotationJobs: annotationJobs,
      attachmentAnnotationEnabled: annotationUi.enabled,
      attachmentAnnotationCanRunNow: annotationUi.canRunNow,
      audioTranscribeEnabled: audioUi.enabled,
      audioTranscribeCanRunNow: audioUi.canRunNow,
    );
  }

  Future<_ChatMessageSupplementData> _cachedChatMessageSupplementDataFuture({
    required AppBackend backend,
    required Uint8List sessionKey,
    required List<Message> messages,
  }) {
    final cacheKey = _messageSupplementCacheKeyFor(messages);
    final cachedFuture = _messageSupplementFuture;
    if (cachedFuture != null && _messageSupplementCacheKey == cacheKey) {
      return cachedFuture;
    }

    final future = _loadChatMessageSupplementData(
      backend: backend,
      sessionKey: sessionKey,
      messages: messages,
    );
    _messageSupplementCacheKey = cacheKey;
    _messageSupplementFuture = future;
    return future;
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
      createdAtMs: platformIntFromInt(
        _askFailureCreatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      ),
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
      final page = await _withChatLoadStage(
        'chat.listMessagesPage.initial',
        () => backend.listMessagesPage(
          sessionKey,
          widget.conversation.id,
          limit: _kMessagePageSize,
        ),
      );
      final normalizedPage = _normalizeMessagesForList(page);
      if (mounted) {
        _setState(() {
          _paginatedMessages = normalizedPage;
          _latestLoadedMessages = normalizedPage;
          _hasMoreMessages = page.length == _kMessagePageSize;
          _loadingMoreMessages = false;
        });
        unawaited(_syncSecretaryMemory(sessionKey, normalizedPage));
      } else {
        _latestLoadedMessages = normalizedPage;
      }
      return normalizedPage;
    }

    final list = await _withChatLoadStage(
      'chat.listMessages.initial',
      () => backend.listMessages(sessionKey, widget.conversation.id),
    );
    final filtered = await _filterMessagesBySelectedTags(sessionKey, list);
    final normalizedFiltered = _normalizeMessagesForList(filtered);

    if (_usePagination) {
      if (mounted) {
        _setState(() {
          _paginatedMessages = normalizedFiltered;
          _latestLoadedMessages = normalizedFiltered;
          _hasMoreMessages = false;
          _loadingMoreMessages = false;
        });
        unawaited(_syncSecretaryMemory(sessionKey, normalizedFiltered));
      } else {
        _latestLoadedMessages = normalizedFiltered;
      }
      return normalizedFiltered;
    }

    _latestLoadedMessages = normalizedFiltered;
    if (mounted) {
      unawaited(_syncSecretaryMemory(sessionKey, normalizedFiltered));
    }
    return normalizedFiltered;
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
        beforeCreatedAtMs: platformIntToInt(oldest.createdAtMs),
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

  Future<TaskPriorityAiService?> _resolveTaskPriorityAiService() async {
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
      final cloudUid = cloudAuthScope?.controller.uid;
      final idToken = await readCloudCapabilityIdToken(
        cloudAuthScope?.controller,
        mode: CloudCapabilityAuthMode.background,
      );
      final route = await resolveTaskPriorityAiRoute(
        backend,
        Uint8List.fromList(sessionKey),
        cloudIdToken: idToken,
        cloudGatewayBaseUrl: gatewayConfig.baseUrl,
        subscriptionStatus: subscriptionStatus,
      );
      if (route == AskAiRouteKind.needsSetup) return null;
      final cacheScopeKey = await resolveTaskPriorityAiCacheScopeKey(
        backend,
        Uint8List.fromList(sessionKey),
        route: route,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        modelName: gatewayConfig.modelName,
        localeTag: localeTag,
        cloudUid: cloudUid,
      );
      return BackendTaskPriorityAiService(
        backend: backend,
        sessionKey: sessionKey,
        route: route,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        idToken: (idToken ?? '').trim(),
        modelName: gatewayConfig.modelName,
        localeTag: localeTag,
        cacheScopeKeyOverride: cacheScopeKey,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveTaskPriorityAiCacheScopeKey() async {
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey =
          Uint8List.fromList(SessionScope.of(context).sessionKey);
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
      final cloudUid = cloudAuthScope?.controller.uid;
      if (subscriptionStatus == SubscriptionStatus.entitled &&
          gatewayConfig.baseUrl.trim().isNotEmpty &&
          (cloudUid?.trim().isNotEmpty ?? false)) {
        final cloudScope = await resolveTaskPriorityAiCacheScopeKey(
          backend,
          sessionKey,
          route: AskAiRouteKind.cloudGateway,
          gatewayBaseUrl: gatewayConfig.baseUrl,
          modelName: gatewayConfig.modelName,
          localeTag: localeTag,
          cloudUid: cloudUid,
        );
        if (cloudScope != null) return cloudScope;
      }
      return resolveTaskPriorityAiCacheScopeKey(
        backend,
        sessionKey,
        route: AskAiRouteKind.byok,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        modelName: gatewayConfig.modelName,
        localeTag: localeTag,
        cloudUid: cloudUid,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<TodoThreadMatch>> _resolveTodoSemanticMatchesForSendFlow(
    AppBackend backend,
    Uint8List sessionKey, {
    required String query,
    required int topK,
    bool requireCloud = false,
  }) async {
    final route = await _resolveTodoSemanticRouteForSendFlow(
      backend,
      sessionKey,
    );
    if (route != EmbeddingsSourceRouteKind.local) {
      final remoteMatches = await _searchRemoteTodoSemanticMatches(
        backend,
        sessionKey,
        query: query,
        topK: topK,
        requireCloud: requireCloud,
      );
      if (remoteMatches.isNotEmpty) return remoteMatches;

      return _searchLocalTodoSemanticMatches(
        backend,
        sessionKey,
        query: query,
        topK: topK,
      );
    }

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

  Future<EmbeddingsSourceRouteKind> _resolveTodoSemanticRouteForSendFlow(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    final subscriptionScope = SubscriptionScope.maybeOf(context);
    final cloudAuthScope = CloudAuthScope.maybeOf(context);

    final prefs = await SharedPreferences.getInstance();
    final preference = switch (
        (prefs.getString('embeddings_source_preference_v1') ?? '').trim()) {
      'cloud' => EmbeddingsSourcePreference.cloud,
      'byok' => EmbeddingsSourcePreference.byok,
      'local' => EmbeddingsSourcePreference.local,
      _ => EmbeddingsSourcePreference.auto,
    };
    final cloudEmbeddingsSelected =
        prefs.getBool(_kEmbeddingsDataConsentPrefsKey) ??
            _cloudEmbeddingsConsented;

    final subscriptionStatus =
        subscriptionScope?.status ?? SubscriptionStatus.unknown;
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

    final cloudIdToken = await readCloudCapabilityIdToken(
      cloudAuthScope?.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );

    final cloudAvailable = subscriptionStatus == SubscriptionStatus.entitled &&
        cloudIdToken != null &&
        cloudIdToken.trim().isNotEmpty &&
        cloudGatewayConfig.baseUrl.trim().isNotEmpty;

    var hasByokProfile = false;
    try {
      final profiles = await backend.listEmbeddingProfiles(sessionKey);
      hasByokProfile = profiles.any((p) => p.isActive);
    } catch (_) {
      hasByokProfile = false;
    }

    return resolveEmbeddingsSourceRoute(
      preference,
      cloudEmbeddingsSelected: cloudEmbeddingsSelected,
      cloudAvailable: cloudAvailable,
      hasByokProfile: hasByokProfile,
    );
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

    final cloudIdToken = await readCloudCapabilityIdToken(
      cloudAuthScope?.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );

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

  void _refresh({bool refreshTaskPriority = false}) {
    _setState(() {
      if (_usePagination) {
        _loadingMoreMessages = false;
        _hasMoreMessages = true;
      }
      _messagesFuture = _loadMessages();
      _messageSupplementFuture = null;
      _messageSupplementCacheKey = '';
      _attachmentsFuturesByMessageId.clear();
      _attachmentEnrichmentFuturesBySha256.clear();
    });
    if (!refreshTaskPriority) return;
    _refreshTaskPriorityNow();
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
      _attachmentSendFeedbackStage =
          draftsSnapshot.isEmpty ? null : AttachmentProcessingStage.preparing;
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
          ingestAttachment: (draft) => _ingestComposerDraftAttachment(
            nativeBackend,
            sessionKey,
            draft,
            onStage: (stage) {
              if (!mounted) return;
              _setState(() => _attachmentSendFeedbackStage = stage);
            },
          ),
          linkAttachmentToMessage: (messageId, attachmentSha256) =>
              nativeBackend.linkAttachmentToMessage(
            sessionKey,
            messageId,
            attachmentSha256: attachmentSha256,
          ),
          onAttachmentLinked: (attachmentSha256, draft) =>
              _handleLinkedDraftAttachment(
            nativeBackend,
            sessionKey,
            attachmentSha256,
            draft,
          ),
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
          createdAtMs: platformIntToInt(committedMessage.createdAtMs),
        );
        unawaited(_persistSecretaryMemoryProposalForMessage(committedMessage));
      }
    } catch (e) {
      if (!mounted) return;
      _scaffoldMessengerKey.currentState?.showSnackBar(
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
          _attachmentSendFeedbackStage = null;
        });
      }
    }
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
      final inferredMimeType = inferImageMimeTypeFromPath(picked.path);
      final pickedFilename = (() {
        final byName = picked.name.trim();
        if (byName.isNotEmpty) return byName;
        final normalizedPath = picked.path.trim().replaceAll('\\', '/');
        if (normalizedPath.isEmpty) return '';
        return normalizedPath.split('/').last.trim();
      })();
      _appendComposerAttachmentDrafts(
        <AttachmentDraftPayload>[
          buildImageAttachmentDraftPayload(
            localId: _nextComposerAttachmentDraftLocalId(),
            rawBytes: rawBytes,
            inferredMimeType: inferredMimeType,
            filename: pickedFilename,
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      _scaffoldMessengerKey.currentState?.showSnackBar(
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
      _scaffoldMessengerKey.currentState?.showSnackBar(
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

Future<T> _withChatLoadStage<T>(
  String stage,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(_ChatLoadStageError(stage, error), stackTrace);
  }
}

final class _ChatLoadStageError implements Exception {
  const _ChatLoadStageError(this.stage, this.cause);

  final String stage;
  final Object cause;

  @override
  String toString() => '$stage: $cause';
}
