part of 'chat_page.dart';

extension _ChatPageStateMethodsB on _ChatPageState {
  void _showAskAiFailure(String question, {String? message}) {
    final failureMessage = message ?? context.t.chat.askAiFailedTemporary;

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
    if (_usePagination) {
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
    _latestLoadedMessages = list;
    return list;
  }

  Future<void> _loadOlderMessages() async {
    if (!_usePagination) return;
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

  Future<int> _loadReviewQueueCount() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final settings = await ActionsSettingsStore.load();

    final nowLocal = DateTime.now();
    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return 0;
    }

    var pendingCount = 0;
    for (final todo in todos) {
      final nextMs = todo.nextReviewAtMs;
      final stage = todo.reviewStage;
      if (nextMs == null || stage == null) continue;

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
          await backend.upsertTodo(
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
        } catch (_) {
          return 0;
        }
      }

      if (todo.dueAtMs != null) continue;
      if (todo.status == 'done' || todo.status == 'dismissed') continue;
      pendingCount += 1;
    }

    return pendingCount;
  }

  Future<_TodoAgendaSummary> _loadTodoAgendaSummary() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return const _TodoAgendaSummary.empty();
    }

    final nowLocal = DateTime.now();
    final due = <({Todo todo, DateTime dueLocal})>[];
    final upcoming = <({Todo todo, DateTime dueLocal})>[];
    for (final todo in todos) {
      final dueMs = todo.dueAtMs;
      if (dueMs == null) continue;
      if (todo.status == 'done' || todo.status == 'dismissed') continue;

      final dueLocal =
          DateTime.fromMillisecondsSinceEpoch(dueMs, isUtc: true).toLocal();
      final isOverdue = dueLocal.isBefore(nowLocal);
      final isToday = _isSameLocalDate(dueLocal, nowLocal);
      if (isOverdue || isToday) {
        due.add((todo: todo, dueLocal: dueLocal));
        continue;
      }

      // Upcoming preview: only show future todos that haven't started yet.
      if (todo.status == 'open') {
        upcoming.add((todo: todo, dueLocal: dueLocal));
      }
    }

    due.sort((a, b) => a.dueLocal.compareTo(b.dueLocal));
    upcoming.sort((a, b) => a.dueLocal.compareTo(b.dueLocal));
    if (due.isEmpty && upcoming.isEmpty) {
      return const _TodoAgendaSummary.empty();
    }

    final overdueCount = due.where((e) => e.dueLocal.isBefore(nowLocal)).length;
    const duePreviewLimit = 2;
    const upcomingPreviewLimit = 2;
    final previewTodos = <Todo>[
      ...due.take(duePreviewLimit).map((e) => e.todo),
      ...upcoming.take(upcomingPreviewLimit).map((e) => e.todo),
    ];

    return _TodoAgendaSummary(
      dueCount: due.length,
      overdueCount: overdueCount,
      upcomingCount: upcoming.length,
      previewTodos: previewTodos.toList(growable: false),
    );
  }

  Future<List<TodoThreadMatch>> _resolveTodoSemanticMatchesForSendFlow(
    AppBackend backend,
    Uint8List sessionKey, {
    required String query,
    required int topK,
    bool requireCloud = false,
  }) async {
    Future<List<TodoThreadMatch>> resolveSemanticMatches() async {
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

      final cloudAvailable =
          subscriptionStatus == SubscriptionStatus.entitled &&
              cloudIdToken != null &&
              cloudIdToken.trim().isNotEmpty &&
              cloudGatewayConfig.baseUrl.trim().isNotEmpty;

      if (cloudAvailable) {
        if (requireCloud && !_cloudEmbeddingsConsented) {
          return const <TodoThreadMatch>[];
        }

        // Avoid prompting for consent during send flow.
        if (_cloudEmbeddingsConsented) {
          return backend.searchSimilarTodoThreadsCloudGateway(
            sessionKey,
            query,
            topK: topK,
            gatewayBaseUrl: cloudGatewayConfig.baseUrl,
            idToken: cloudIdToken,
            modelName: _kCloudEmbeddingsModelName,
          );
        }
        return backend.searchSimilarTodoThreads(sessionKey, query, topK: topK);
      }

      if (requireCloud) return const <TodoThreadMatch>[];

      if (_cloudEmbeddingsConsented &&
          subscriptionStatus != SubscriptionStatus.notEntitled) {
        return const <TodoThreadMatch>[];
      }

      try {
        return await backend.searchSimilarTodoThreadsBrok(
          sessionKey,
          query,
          topK: topK,
        );
      } catch (_) {
        return backend.searchSimilarTodoThreads(sessionKey, query, topK: topK);
      }
    }

    try {
      return await resolveSemanticMatches();
    } catch (_) {
      return const <TodoThreadMatch>[];
    }
  }

  Future<List<TodoLinkCandidate>> _rankTodoCandidatesWithSemanticMatches(
    AppBackend backend,
    Uint8List sessionKey, {
    required String query,
    required List<TodoLinkTarget> targets,
    required DateTime nowLocal,
    required int limit,
  }) async {
    final ranked =
        rankTodoCandidates(query, targets, nowLocal: nowLocal, limit: limit);

    List<TodoThreadMatch> semantic = const <TodoThreadMatch>[];
    try {
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

      final cloudAvailable =
          subscriptionStatus == SubscriptionStatus.entitled &&
              cloudIdToken != null &&
              cloudIdToken.trim().isNotEmpty &&
              cloudGatewayConfig.baseUrl.trim().isNotEmpty;

      if (cloudAvailable) {
        final allowCloudEmbeddings =
            _cloudEmbeddingsConsented || await _ensureEmbeddingsDataConsent();
        if (allowCloudEmbeddings) {
          semantic = await backend.searchSimilarTodoThreadsCloudGateway(
            sessionKey,
            query,
            topK: limit,
            gatewayBaseUrl: cloudGatewayConfig.baseUrl,
            idToken: cloudIdToken,
            modelName: _kCloudEmbeddingsModelName,
          );
        } else {
          semantic = await backend.searchSimilarTodoThreads(
            sessionKey,
            query,
            topK: limit,
          );
        }
      } else {
        if (_cloudEmbeddingsConsented &&
            subscriptionStatus != SubscriptionStatus.notEntitled) {
          semantic = const <TodoThreadMatch>[];
        } else {
          try {
            semantic = await backend.searchSimilarTodoThreadsBrok(
              sessionKey,
              query,
              topK: limit,
            );
          } catch (_) {
            semantic = await backend.searchSimilarTodoThreads(
              sessionKey,
              query,
              topK: limit,
            );
          }
        }
      }
    } catch (_) {
      semantic = const <TodoThreadMatch>[];
    }
    if (semantic.isEmpty) return ranked;

    final targetsById = <String, TodoLinkTarget>{};
    for (final t in targets) {
      targetsById[t.id] = t;
    }

    final scoreByTodoId = <String, int>{};
    for (final c in ranked) {
      scoreByTodoId[c.target.id] = c.score;
    }

    for (var i = 0; i < semantic.length && i < limit; i++) {
      final match = semantic[i];
      final target = targetsById[match.todoId];
      if (target == null) continue;

      final boost = _semanticBoost(i, match.distance);
      if (boost <= 0) continue;

      final existing = scoreByTodoId[target.id];
      final base = existing ?? _dueBoost(target.dueLocal, nowLocal);
      scoreByTodoId[target.id] = base + boost;
    }

    final merged = <TodoLinkCandidate>[];
    scoreByTodoId.forEach((id, score) {
      final target = targetsById[id];
      if (target == null) return;
      merged.add(TodoLinkCandidate(target: target, score: score));
    });
    merged.sort((a, b) => b.score.compareTo(a.score));
    if (merged.length <= limit) return merged;
    return merged.sublist(0, limit);
  }

  void _refresh() {
    _setState(() {
      if (_usePagination) {
        _loadingMoreMessages = false;
        _hasMoreMessages = true;
      }
      _messagesFuture = _loadMessages();
      _reviewCountFuture = _loadReviewQueueCount();
      _agendaFuture = _loadTodoAgendaSummary();
      _attachmentsFuturesByMessageId.clear();
      _attachmentEnrichmentFuturesBySha256.clear();
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_asking) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _setState(() => _sending = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final sentAsUrlAttachment = await _trySendTextAsUrlAttachment(text);
      Message? sentMessage;

      if (!sentAsUrlAttachment) {
        sentMessage = await backend.insertMessage(
          sessionKey,
          widget.conversation.id,
          role: 'user',
          content: text,
        );
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
      _controller.clear();
      if (_isDesktopPlatform) {
        _inputFocusNode.requestFocus();
      }

      if (sentMessage != null) {
        _messageAutoActionsQueue ??= MessageAutoActionsQueue(
          backend: backend,
          sessionKey: sessionKey,
          handler: _handleMessageAutoActions,
        );
        _messageAutoActionsQueue!.enqueue(
          message: sentMessage,
          rawText: text,
          createdAtMs: sentMessage.createdAtMs,
        );
      }
    } finally {
      if (mounted) _setState(() => _sending = false);
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
    if (_isDesktopPlatform) {
      return _pickAndSendAttachmentFromFile();
    }
    return _pickAndSendImageFromGallery();
  }

  Future<void> _openAttachmentSheet() async {
    if (_sending) return;
    if (_asking) return;
    if (!_supportsImageUpload) return;

    if (_isDesktopPlatform) {
      await _pickAndSendAttachmentFromFile();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
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
                    unawaited(_captureAndSendPhoto());
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _captureAndSendPhoto() async {
    if (_sending) return;
    if (_asking) return;
    if (!_supportsCamera) return;

    _setState(() => _sending = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        requestFullMetadata: true,
      );
      if (picked == null) return;
      if (!mounted) return;

      final lang = Localizations.localeOf(context).toLanguageTag();
      final backendAny = AppBackendScope.of(context);
      final backend = backendAny is NativeAppBackend ? backendAny : null;
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);

      final platformExif =
          await PlatformExifReader.tryReadImageMetadataFromPath(picked.path);
      final hasValidExifLocation = platformExif != null &&
          platformExif.hasLocation &&
          !(platformExif.latitude == 0.0 && platformExif.longitude == 0.0) &&
          !(platformExif.latitude?.isNaN ?? false) &&
          !(platformExif.longitude?.isNaN ?? false);

      final Future<PlatformLocation?>? locationFuture = hasValidExifLocation
          ? null
          : PlatformLocationReader.tryGetCurrentLocation();
      PlatformExifMetadata? platformExifToSend = platformExif;
      if (!hasValidExifLocation) {
        // Many camera implementations don't embed GPS EXIF when saving to an
        // app-scoped file. We request location now (may prompt permission),
        // but we don't block sending. Location will be backfilled later.
      }
      final rawBytes = await picked.readAsBytes();
      final inferredMimeType = _inferImageMimeTypeFromPath(picked.path);
      int? fallbackCapturedAtMs;
      try {
        fallbackCapturedAtMs =
            (await picked.lastModified()).toUtc().millisecondsSinceEpoch;
      } catch (_) {}
      final sent = await _sendImageAttachment(
        rawBytes,
        inferredMimeType,
        fallbackCapturedAtMs: fallbackCapturedAtMs,
        platformExif: platformExifToSend,
      );

      if (locationFuture != null && sent != null && backend != null) {
        unawaited(
          deferAttachmentLocationUpsert(
            locationFuture: locationFuture,
            capturedAtMs: sent.capturedAtMs,
            upsert: ({
              required int? capturedAtMs,
              required double latitude,
              required double longitude,
            }) async {
              await backend.upsertAttachmentExifMetadata(
                sessionKey,
                sha256: sent.sha256,
                capturedAtMs: capturedAtMs,
                latitude: latitude,
                longitude: longitude,
              );
              unawaited(
                _maybeEnqueueAttachmentPlaceEnrichment(
                  backend,
                  sessionKey,
                  sent.sha256,
                  lang: lang,
                ),
              );
              syncEngine?.notifyLocalMutation();
              if (!mounted) return;
              _refresh();
            },
          ),
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
      if (mounted) _setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImageFromGallery() async {
    if (_sending) return;
    if (_asking) return;
    if (!_supportsCamera) return;

    _setState(() => _sending = true);
    try {
      await AndroidMediaLocationPermission.requestIfNeeded();
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: true,
      );
      if (picked == null) return;

      final platformExif =
          await PlatformExifReader.tryReadImageMetadataFromPath(picked.path);
      final rawBytes = await picked.readAsBytes();
      final inferredMimeType = _inferImageMimeTypeFromPath(picked.path);
      int? fallbackCapturedAtMs;
      try {
        fallbackCapturedAtMs =
            (await picked.lastModified()).toUtc().millisecondsSinceEpoch;
      } catch (_) {}
      await _sendImageAttachment(
        rawBytes,
        inferredMimeType,
        fallbackCapturedAtMs: fallbackCapturedAtMs,
        platformExif: platformExif,
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
      if (mounted) _setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendAttachmentFromFile() async {
    if (_sending) return;
    if (_asking) return;
    if (!_isDesktopPlatform) return;

    _setState(() => _sending = true);
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

      await _sendDesktopFilePayloads(payloads);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.photoFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) _setState(() => _sending = false);
    }
  }

  Future<({String sha256, int? capturedAtMs})?> _sendImageAttachment(
    Uint8List rawBytes,
    String inferredMimeType, {
    int? fallbackCapturedAtMs,
    PlatformExifMetadata? platformExif,
  }) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return null;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final lang = Localizations.localeOf(context).toLanguageTag();

    final compressed =
        await compressImageForStorage(rawBytes, mimeType: inferredMimeType);
    final rawExif = tryReadImageExifMetadata(rawBytes);
    final storedExif = tryReadImageExifMetadata(compressed.bytes);
    final capturedAtMs = platformExif?.capturedAtMsUtc ??
        rawExif?.capturedAt?.toUtc().millisecondsSinceEpoch ??
        storedExif?.capturedAt?.toUtc().millisecondsSinceEpoch ??
        fallbackCapturedAtMs;

    (double, double)? pickLatLon(ImageExifMetadata? meta) {
      final lat = meta?.latitude;
      final lon = meta?.longitude;
      if (lat == null || lon == null) return null;
      if (lat == 0.0 && lon == 0.0) return null;
      if (lat.isNaN || lon.isNaN) return null;
      return (lat, lon);
    }

    final latLon = pickLatLon(platformExif?.toImageExifMetadata()) ??
        pickLatLon(rawExif) ??
        pickLatLon(storedExif);
    final latitude = latLon?.$1;
    final longitude = latLon?.$2;

    final attachment = await backend.insertAttachment(
      sessionKey,
      bytes: compressed.bytes,
      mimeType: compressed.mimeType,
    );
    if (capturedAtMs != null || latitude != null || longitude != null) {
      await backend.upsertAttachmentExifMetadata(
        sessionKey,
        sha256: attachment.sha256,
        capturedAtMs: capturedAtMs,
        latitude: latitude,
        longitude: longitude,
      );
    }
    if (latitude != null && longitude != null) {
      unawaited(
        _maybeEnqueueAttachmentPlaceEnrichment(
          backend,
          sessionKey,
          attachment.sha256,
          lang: lang,
        ),
      );
    }
    unawaited(_maybeEnqueueCloudMediaBackup(
      backend,
      sessionKey,
      attachment.sha256,
    ));
    final message = await backend.insertMessage(
      sessionKey,
      widget.conversation.id,
      role: 'user',
      content: '',
    );
    await backend.linkAttachmentToMessage(
      sessionKey,
      message.id,
      attachmentSha256: attachment.sha256,
    );
    unawaited(
      _maybeEnqueueAttachmentAnnotationEnrichment(
        backend,
        sessionKey,
        attachment.sha256,
        lang: lang,
      ),
    );

    syncEngine?.notifyLocalMutation();
    if (!mounted) {
      return (sha256: attachment.sha256, capturedAtMs: capturedAtMs);
    }
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

    return (sha256: attachment.sha256, capturedAtMs: capturedAtMs);
  }
}
