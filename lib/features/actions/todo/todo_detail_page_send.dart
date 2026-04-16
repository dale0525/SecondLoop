part of 'todo_detail_page.dart';

extension _TodoDetailPageStateSend on _TodoDetailPageState {
  Future<void> _appendNote() async {
    if (_sendingNote) return;
    final text = _noteController.text.trim();
    final pending = List<AttachmentDraftPayload>.from(_pendingAttachments);
    if (text.isEmpty && pending.isEmpty) return;

    if (pending.isEmpty && text.isNotEmpty) {
      final sentAsUrlAttachment = await _tryAppendTextAsUrlAttachment(text);
      if (sentAsUrlAttachment) {
        return;
      }
      if (!mounted) return;
    }

    _setState(() => _sendingNote = true);

    try {
      final backendAny = AppBackendScope.of(context);
      final syncEngine = SyncEngineScope.maybeOf(context);
      final sessionKey = SessionScope.of(context).sessionKey;

      if (backendAny is! NativeAppBackend) {
        if (pending.isNotEmpty) {
          throw Exception('native_backend_required');
        }
        final createdActivity = await backendAny.appendTodoNote(
          sessionKey,
          todoId: _todo.id,
          content: text,
        );
        if (!mounted) return;
        _setState(() {
          _pendingAttachments.clear();
          _noteController.clear();
        });
        _refreshActivities();
        syncEngine?.notifyLocalMutation();
        if (_isDesktopPlatform && createdActivity.id.isNotEmpty) {
          _noteInputFocusNode.requestFocus();
        }
        return;
      }

      final backend = backendAny;
      final attachmentsBackend = backend as AttachmentsBackend;
      const coordinator = AttachmentDraftSendCoordinator();
      TodoActivity? createdActivity;

      final result = await coordinator.send(
        text: text,
        drafts: pending,
        createUserMessage: (noteContent) async {
          final activity = await backend.appendTodoNote(
            sessionKey,
            todoId: _todo.id,
            content: noteContent,
          );
          createdActivity ??= activity;
          final sourceMessageId = activity.sourceMessageId?.trim() ?? '';
          if (sourceMessageId.isNotEmpty) {
            try {
              final existing = await backend.getMessageById(
                sessionKey,
                sourceMessageId,
              );
              if (existing != null) return existing;
            } catch (_) {
              // ignore
            }
            return Message(
              id: sourceMessageId,
              conversationId: 'todo_${_todo.id}',
              role: 'user',
              content: noteContent,
              createdAtMs:
                  platformIntFromInt(DateTime.now().millisecondsSinceEpoch),
              isMemory: false,
            );
          }
          return Message(
            id: 'todo_activity_${activity.id}',
            conversationId: 'todo_${_todo.id}',
            role: 'user',
            content: noteContent,
            createdAtMs:
                platformIntFromInt(DateTime.now().millisecondsSinceEpoch),
            isMemory: false,
          );
        },
        ingestAttachment: (draft) =>
            _ingestPendingAttachmentDraft(backend, sessionKey, draft),
        linkAttachmentToMessage: (_, attachmentSha256) async {
          final activity = createdActivity;
          if (activity == null) {
            throw StateError('todo_activity_not_created');
          }

          final sourceMessageId = activity.sourceMessageId?.trim() ?? '';
          if (sourceMessageId.isNotEmpty) {
            await attachmentsBackend.linkAttachmentToMessage(
              sessionKey,
              sourceMessageId,
              attachmentSha256: attachmentSha256,
            );
          }
          await backend.linkAttachmentToTodoActivity(
            sessionKey,
            activityId: activity.id,
            attachmentSha256: attachmentSha256,
          );
        },
        onAttachmentLinked: (attachmentSha256, draft) async {
          try {
            final urlFromManifest = readUrlFromManifestDraft(draft);
            unawaited(
              runDraftAttachmentPostLinkEnrichment(
                backend: backend,
                sessionKey: sessionKey,
                attachmentSha256: attachmentSha256,
                draft: draft,
                lang: Localizations.localeOf(context).toLanguageTag(),
                beforeEnqueueImageAnnotation: () =>
                    bestEffortWarmCloudCapabilityAuth(
                  CloudAuthScope.maybeOf(context)?.controller,
                ),
                beforeEnqueueAudioTranscribe: () =>
                    bestEffortWarmCloudCapabilityAuth(
                  CloudAuthScope.maybeOf(context)?.controller,
                ),
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

      if (!mounted) return;
      final failedDrafts = dedupeAttachmentDraftPayloads(
        result.failedItems
            .map((failed) => failed.payload)
            .toList(growable: false),
      );

      _setState(() {
        _pendingAttachments
          ..clear()
          ..addAll(failedDrafts);
        if (createdActivity != null) {
          _noteController.clear();
        }
      });

      if (createdActivity != null) {
        _refreshActivities();
        syncEngine?.notifyLocalMutation();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        _setState(() => _sendingNote = false);
      } else {
        _sendingNote = false;
      }
    }
  }
}
