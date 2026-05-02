part of 'chat_page.dart';

const _kCloudDetachedRequestIdPayloadKey = 'secondloop_cloud_request_id';
const _kDetachedTodoIdPrefix = 'todo:_detached_message_link:';
const _kDetachedTodoTitlePrefix = '[detached] ';
const _kMessageCopyCardDivider = '\n\n----------\n\n';
final RegExp _kCloudDetachedRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9:_-]{5,127}$',
);

extension _ChatPageStateMethodsA on _ChatPageState {
  Future<void> _showUnsupportedSecondLoopLink(String href) async {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          context.t.errors.loadFailed(error: 'unsupported_secondloop_link'),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _attachSyncEngine() {
    final engine = SyncEngineScope.maybeOf(context);
    if (identical(engine, _syncEngine)) return;

    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }

    _syncEngine = engine;
    if (engine == null) {
      _syncListener = null;
      return;
    }

    void onSyncChange() {
      if (!mounted) return;
      final forceUiRefresh = engine.forceUiRefreshForCurrentChange;
      _scheduleTaskPrioritySyncRefresh();
      if (!forceUiRefresh && !_isAtBottom) {
        _setState(() {
          _hasUnseenNewMessages = true;
        });
        return;
      }
      _refresh(resetChatState: forceUiRefresh);
    }

    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  Future<void> _showMessageActions(Message message) async {
    if (_isTransientPendingMessage(message)) return;
    final isFailedAskMessage = message.id == _kFailedAskMessageId;
    if (isFailedAskMessage) {
      final action = await _showModalBottomSheetFromChat<_MessageAction>(
        builder: (context) {
          final tokens = SlTokens.of(context);
          final colorScheme = Theme.of(context).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SlSurface(
                key: const ValueKey('message_actions_sheet'),
                color: tokens.surface2,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  key: const ValueKey('message_action_delete'),
                  leading: const Icon(Icons.delete_outline_rounded),
                  iconColor: colorScheme.error,
                  textColor: colorScheme.error,
                  title: Text(context.t.common.actions.delete),
                  onTap: () => Navigator.of(context).pop(_MessageAction.delete),
                ),
              ),
            ),
          );
        },
      );
      if (!mounted) return;
      if (action == _MessageAction.delete) {
        await _deleteMessage(message);
      }
      return;
    }

    final canEdit = await _canEditMessage(message);
    final displayText = _displayTextForMessage(message).trim();
    if (!mounted) return;

    ({Todo todo, bool isSourceEntry})? linkedTodo;
    final linkedTodoFuture = _resolveLinkedTodoInfo(message).then((value) {
      linkedTodo = value;
      return value;
    });

    final action = await _showModalBottomSheetFromChat<_MessageAction>(
      isScrollControlled: true,
      builder: (context) {
        final tokens = SlTokens.of(context);
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SlSurface(
              key: const ValueKey('message_actions_sheet'),
              color: tokens.surface2,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: FutureBuilder<({Todo todo, bool isSourceEntry})?>(
                future: linkedTodoFuture,
                builder: (context, snapshot) {
                  final resolvedTodo =
                      snapshot.connectionState == ConnectionState.done
                          ? snapshot.data
                          : null;
                  final isLinkedNonSource =
                      resolvedTodo != null && !resolvedTodo.isSourceEntry;
                  final canConvertToTodo =
                      snapshot.connectionState == ConnectionState.done &&
                          displayText.isNotEmpty &&
                          (resolvedTodo == null || isLinkedNonSource);

                  final showLinkTodo = resolvedTodo == null ||
                      resolvedTodo.isSourceEntry == false;
                  final linkTodoTitle = resolvedTodo == null
                      ? context.t.actions.todoNoteLink.action
                      : context.t.chat.messageActions.linkOtherTodo;

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          key: const ValueKey('message_action_copy'),
                          leading: const Icon(Icons.copy_all_rounded),
                          title: Text(context.t.common.actions.copy),
                          onTap: () =>
                              Navigator.of(context).pop(_MessageAction.copy),
                        ),
                        if (snapshot.connectionState ==
                            ConnectionState.done) ...[
                          if (canConvertToTodo)
                            ListTile(
                              key:
                                  const ValueKey('message_action_convert_todo'),
                              leading: const Icon(Icons.task_alt_rounded),
                              title: Text(
                                  context.t.chat.messageActions.convertToTodo),
                              onTap: () => Navigator.of(context)
                                  .pop(_MessageAction.convertTodo),
                            ),
                          if (resolvedTodo != null) ...[
                            ListTile(
                              key: const ValueKey('message_action_open_todo'),
                              leading: const Icon(Icons.chevron_right_rounded),
                              title:
                                  Text(context.t.chat.messageActions.openTodo),
                              onTap: () => Navigator.of(context)
                                  .pop(_MessageAction.openTodo),
                            ),
                            ListTile(
                              key: const ValueKey(
                                  'message_action_convert_to_info'),
                              leading: const Icon(Icons.undo_rounded),
                              title: Text(context
                                  .t.chat.messageActions.convertTodoToInfo),
                              onTap: () => Navigator.of(context)
                                  .pop(_MessageAction.convertTodoToInfo),
                            ),
                          ],
                        ],
                        if (canEdit)
                          ListTile(
                            key: const ValueKey('message_action_edit'),
                            leading: const Icon(Icons.edit_rounded),
                            title: Text(context.t.common.actions.edit),
                            onTap: () =>
                                Navigator.of(context).pop(_MessageAction.edit),
                          ),
                        ListTile(
                          key: const ValueKey('message_action_tags'),
                          leading: const Icon(Icons.sell_outlined),
                          title: Text(
                            context.t.chat.tagPicker.tagActionLabel,
                          ),
                          onTap: () =>
                              Navigator.of(context).pop(_MessageAction.tags),
                        ),
                        if (showLinkTodo)
                          ListTile(
                            key: const ValueKey('message_action_link_todo'),
                            leading: const Icon(Icons.link_rounded),
                            title: Text(linkTodoTitle),
                            onTap: () => Navigator.of(context)
                                .pop(_MessageAction.linkTodo),
                          ),
                        ListTile(
                          key: const ValueKey('message_action_delete'),
                          leading: const Icon(Icons.delete_outline_rounded),
                          iconColor: colorScheme.error,
                          textColor: colorScheme.error,
                          title: Text(context.t.common.actions.delete),
                          onTap: () =>
                              Navigator.of(context).pop(_MessageAction.delete),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    switch (action) {
      case _MessageAction.copy:
        await _copyMessageToClipboard(message);
        break;
      case _MessageAction.convertTodo:
        await _convertMessageToTodo(message);
        break;
      case _MessageAction.convertTodoToInfo:
        await _convertMessageTodoToInfo(message, linkedTodo?.todo);
        break;
      case _MessageAction.openTodo:
        await _openLinkedTodo(linkedTodo?.todo);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.tags:
        await _openMessageTagPicker(message);
        break;
      case _MessageAction.linkTodo:
        await _linkMessageToTodo(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message, linkedTodoInfo: linkedTodo);
        break;
      case null:
        break;
    }
  }

  String _displayTextForMessage(Message message) {
    final raw = message.content;
    final actions =
        message.role == 'assistant' ? parseAssistantMessageActions(raw) : null;
    final text = (actions?.displayText ?? raw).trim();
    if (text == 'Photo' || text == '照片') return '';
    return text;
  }

  bool _isPhotoPlaceholderText(BuildContext context, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final localized = context.t.chat.photoMessage.trim();
    if (localized.isNotEmpty && trimmed == localized) return true;
    return trimmed == 'Photo' || trimmed == '照片';
  }

  Future<String> _resolveCopyTextForMessage(Message message) async {
    final displayText = _displayTextForMessage(message).trim();
    if (displayText.isNotEmpty) {
      return displayText;
    }
    final detailText = await _buildMessageDetailCopyText(message);
    return detailText.trim();
  }

  Future<String> _buildMessageDetailCopyText(Message message) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! AttachmentsBackend) return '';
    final attachmentsBackend = backendAny as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;

    List<Attachment> attachments;
    try {
      attachments = await _loadMessageAttachmentsForUi(
        messageId: message.id,
        attachmentsBackend: attachmentsBackend,
        sessionKey: sessionKey,
      );
    } catch (_) {
      return '';
    }
    if (attachments.isEmpty) return '';

    final blocks = <String>[];
    for (final attachment in attachments) {
      final block = await _buildAttachmentDetailCopyBlock(
        attachment: attachment,
        attachmentsBackend: attachmentsBackend,
        backendAny: backendAny,
        sessionKey: sessionKey,
      );
      if (block.isNotEmpty) {
        blocks.add(block);
      }
    }
    return blocks.join(_kMessageCopyCardDivider);
  }

  Future<String> _buildAttachmentDetailCopyBlock({
    required Attachment attachment,
    required AttachmentsBackend attachmentsBackend,
    required AppBackend backendAny,
    required Uint8List sessionKey,
  }) async {
    String placeDisplayName = '';
    try {
      placeDisplayName =
          (await attachmentsBackend.readAttachmentPlaceDisplayName(
                    sessionKey,
                    sha256: attachment.sha256,
                  ) ??
                  '')
              .trim();
    } catch (_) {
      placeDisplayName = '';
    }

    String annotationCaption = '';
    try {
      annotationCaption =
          (await attachmentsBackend.readAttachmentAnnotationCaptionLong(
                    sessionKey,
                    sha256: attachment.sha256,
                  ) ??
                  '')
              .trim();
    } catch (_) {
      annotationCaption = '';
    }

    Map<String, Object?>? payload;
    if (backendAny is NativeAppBackend) {
      try {
        final payloadJson =
            await backendAny.readAttachmentAnnotationPayloadJson(
          sessionKey,
          sha256: attachment.sha256,
        );
        final raw = payloadJson?.trim();
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            payload = decoded.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            );
          }
        }
      } catch (_) {
        payload = null;
      }
    }

    final textContent = resolveAttachmentDetailTextContent(
      payload,
      annotationCaption: annotationCaption,
      mimeTypeOverride: attachment.mimeType,
    );

    final blockParts = <String>[];
    if (placeDisplayName.isNotEmpty) {
      blockParts.add(placeDisplayName);
    }

    final summary = textContent.summary.trim();
    final full = textContent.full.trim();
    if (summary.isNotEmpty) {
      blockParts.add(summary);
    }
    if (full.isNotEmpty && full != summary) {
      blockParts.add(full);
    }

    return blockParts.join('\n\n');
  }

  Future<void> _copyMessageToClipboard(Message message) async {
    final copyText = await _resolveCopyTextForMessage(message);
    try {
      await Clipboard.setData(
        ClipboardData(text: copyText),
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(context.t.actions.history.actions.copied),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pasteIntoChatInput() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text;
    if (text == null || text.isEmpty) return;

    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final normalizedStart = start < end ? start : end;
    final normalizedEnd = start < end ? end : start;
    _controller.value = value.copyWith(
      text: value.text.replaceRange(normalizedStart, normalizedEnd, text),
      selection: TextSelection.collapsed(offset: normalizedStart + text.length),
      composing: TextRange.empty,
    );
  }

  bool _shouldCollapseMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.runes.length >= _kLongMessageRuneThreshold) return true;
    final lineCount = '\n'.allMatches(trimmed).length + 1;
    if (lineCount >= _kLongMessageLineThreshold) return true;
    return false;
  }

  Widget _buildMessageMarkdown(
    String content, {
    required bool isDesktopPlatform,
    String? citationsJson,
  }) {
    final citationController = ChatAnswerCitationController(
      parseChatAnswerEvidence(citationsJson),
    );
    final markdown = buildChatMarkdownPreviewBody(
      context,
      text: content,
      selectable: false,
      citationLabelResolver: citationController.chipLabelForHref,
      onTapRichLink: (href) async {
        final handledCitation = await citationController.handleCitationTap(
          context,
          href: href,
          onOpenDirectSource: _handleMarkdownInAppLink,
        );
        if (handledCitation) {
          return;
        }
        await handleChatMarkdownTapLink(
          href,
          handleInApp: _handleMarkdownInAppLink,
          handleUnsupportedSecondLoopLink: _showUnsupportedSecondLoopLink,
        );
      },
      onTapLink: (text, href, title) {
        unawaited(
          handleChatMarkdownTapLink(
            href,
            handleInApp: _handleMarkdownInAppLink,
            handleUnsupportedSecondLoopLink: _showUnsupportedSecondLoopLink,
          ),
        );
      },
    );

    final preview = ChatMarkdownPreviewPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: markdown,
    );

    if (!isDesktopPlatform) return preview;

    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) =>
          const SizedBox.shrink(),
      child: preview,
    );
  }

  Future<void> _openMessageViewer(
    Message message,
    String content,
  ) async {
    await _pushRouteFromChat(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          MessageViewerPage(
            content: content,
            messageId: message.id,
            citationsJson: message.citationsJson,
          ),
        ),
      ),
    );
  }

  Future<void> _openMarkdownEditor() async {
    if (_isComposerBusy) return;

    final result = await openChatMarkdownEditor(
      context,
      initialText: _controller.text,
      allowPlainMode: true,
      routePusher: (route) => _pushRouteFromChat(route),
    );
    if (!mounted || result == null) return;

    final updatedText = result.text;
    if (result.shouldSwitchToSimpleInput) {
      _controller.value = _controller.value.copyWith(
        text: updatedText,
        selection: TextSelection.collapsed(offset: updatedText.length),
        composing: TextRange.empty,
      );
      if (_isDesktopPlatform) {
        _inputFocusNode.requestFocus();
      }
      return;
    }

    if (result.draftAttachments.isNotEmpty) {
      final backendAny = AppBackendScope.of(context);
      if (backendAny is! NativeAppBackend) {
        if (!mounted) return;
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              context.t.chat.photoFailed(
                error: 'native_backend_required_for_markdown_image_paste',
              ),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      final backend = backendAny;
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      Message? sentMessage;

      _setState(() {
        _sending = true;
        _showAttachmentSendFeedback = true;
        _attachmentSendFeedbackStage = AttachmentProcessingStage.preparing;
      });

      try {
        final submission = await sendMarkdownEditorMessage(
          markdown: result.text,
          draftAttachments: result.draftAttachments,
          ingestAttachment: (draft) => _ingestComposerDraftAttachment(
            backend,
            sessionKey,
            draft,
            onStage: (stage) {
              if (!mounted) return;
              _setState(() => _attachmentSendFeedbackStage = stage);
            },
          ),
          createMessage: (content) async {
            final created = await backend.insertMessage(
              sessionKey,
              widget.conversation.id,
              role: 'user',
              content: content,
            );
            sentMessage = created;
            return created;
          },
          linkAttachmentToMessage: (messageId, attachmentSha256) =>
              backend.linkAttachmentToMessage(
            sessionKey,
            messageId,
            attachmentSha256: attachmentSha256,
          ),
        );

        final draftsByLocalId = {
          for (final draft in result.draftAttachments) draft.localId: draft,
        };
        for (final entry in submission.ingestedAttachmentShaByLocalId.entries) {
          final draft = draftsByLocalId[entry.key];
          if (draft == null) continue;
          await _handleLinkedDraftAttachment(
            backend,
            sessionKey,
            entry.value,
            draft,
          );
        }

        syncEngine?.notifyLocalMutation();
        if (mounted) {
          _refresh();
          _controller.clear();
          if (_isDesktopPlatform) {
            _inputFocusNode.requestFocus();
          }
        }

        if (sentMessage != null && submission.markdown.trim().isNotEmpty) {
          final committedMessage = sentMessage!;
          _messageAutoActionsQueue ??= MessageAutoActionsQueue(
            backend: backend,
            sessionKey: sessionKey,
            handler: _handleMessageAutoActions,
          );
          _messageAutoActionsQueue!.enqueue(
            message: committedMessage,
            rawText: submission.markdown,
            createdAtMs: platformIntToInt(committedMessage.createdAtMs),
          );
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
      return;
    }

    _controller.value = _controller.value.copyWith(
      text: updatedText,
      selection: TextSelection.collapsed(offset: updatedText.length),
      composing: TextRange.empty,
    );
    await _send();
  }

  Future<void> _showMessageContextMenu(
    Message message,
    Offset globalPosition,
  ) async {
    if (_isTransientPendingMessage(message)) return;
    final isFailedAskMessage = message.id == _kFailedAskMessageId;
    if (isFailedAskMessage) {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final action = await _showMenuFromChat<_MessageAction>(
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_delete'),
            value: _MessageAction.delete,
            child: Text(context.t.common.actions.delete),
          ),
        ],
      );
      if (!mounted) return;
      if (action == _MessageAction.delete) {
        await _deleteMessage(message);
      }
      return;
    }

    final canEdit = await _canEditMessage(message);
    final linkedTodo = await _resolveLinkedTodoInfo(message);
    final canConvertToTodo =
        _displayTextForMessage(message).trim().isNotEmpty &&
            (linkedTodo == null || !linkedTodo.isSourceEntry);
    if (!mounted) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await _showMenuFromChat<_MessageAction>(
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<_MessageAction>(
          key: const ValueKey('message_context_copy'),
          value: _MessageAction.copy,
          child: Text(context.t.common.actions.copy),
        ),
        if (canConvertToTodo)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_convert_todo'),
            value: _MessageAction.convertTodo,
            child: Text(context.t.chat.messageActions.convertToTodo),
          ),
        if (linkedTodo != null)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_open_todo'),
            value: _MessageAction.openTodo,
            child: Text(context.t.chat.messageActions.openTodo),
          ),
        if (linkedTodo != null)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_convert_to_info'),
            value: _MessageAction.convertTodoToInfo,
            child: Text(context.t.chat.messageActions.convertTodoToInfo),
          ),
        if (canEdit)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_edit'),
            value: _MessageAction.edit,
            child: Text(context.t.common.actions.edit),
          ),
        PopupMenuItem<_MessageAction>(
          key: const ValueKey('message_context_tags'),
          value: _MessageAction.tags,
          child: Text(
            context.t.chat.tagPicker.tagActionLabel,
          ),
        ),
        if (linkedTodo == null)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_link_todo'),
            value: _MessageAction.linkTodo,
            child: Text(context.t.actions.todoNoteLink.action),
          )
        else if (!linkedTodo.isSourceEntry)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_link_todo'),
            value: _MessageAction.linkTodo,
            child: Text(context.t.chat.messageActions.linkOtherTodo),
          ),
        PopupMenuItem<_MessageAction>(
          key: const ValueKey('message_context_delete'),
          value: _MessageAction.delete,
          child: Text(context.t.common.actions.delete),
        ),
      ],
    );
    if (!mounted) return;

    switch (action) {
      case _MessageAction.copy:
        await _copyMessageToClipboard(message);
        break;
      case _MessageAction.convertTodo:
        await _convertMessageToTodo(message);
        break;
      case _MessageAction.convertTodoToInfo:
        await _convertMessageTodoToInfo(message, linkedTodo?.todo);
        break;
      case _MessageAction.openTodo:
        await _openLinkedTodo(linkedTodo?.todo);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.tags:
        await _openMessageTagPicker(message);
        break;
      case _MessageAction.linkTodo:
        await _linkMessageToTodo(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message, linkedTodoInfo: linkedTodo);
        break;
      case null:
        break;
    }
  }

  Future<({Todo todo, bool isSourceEntry})?> _resolveLinkedTodoInfo(
    Message message,
  ) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return null;
    }

    final todosById = <String, Todo>{};
    final sourceTodos = <Todo>[];
    for (final todo in todos) {
      todosById[todo.id] = todo;
      if (todo.sourceEntryId == message.id) {
        sourceTodos.add(todo);
      }
    }

    if (sourceTodos.isNotEmpty) {
      final active = sourceTodos
          .where((todo) => todo.status != 'done' && todo.status != 'dismissed')
          .toList(growable: false);

      if (active.isNotEmpty) {
        final sorted = active.toList(growable: false)
          ..sort((a, b) {
            final dueCompare = compareNullablePlatformIntAsc(
              a.dueAtMs,
              b.dueAtMs,
            );
            if (dueCompare != 0) return dueCompare;
            return comparePlatformInt(b.updatedAtMs, a.updatedAtMs);
          });
        return (todo: sorted.first, isSourceEntry: true);
      }

      final sorted = sourceTodos.toList(growable: false)
        ..sort((a, b) {
          final dueCompare = compareNullablePlatformIntDesc(
            a.dueAtMs,
            b.dueAtMs,
            nullsLast: false,
          );
          if (dueCompare != 0) return dueCompare;
          return comparePlatformInt(b.updatedAtMs, a.updatedAtMs);
        });
      return (todo: sorted.first, isSourceEntry: true);
    }

    int? undoneFollowupCutoffMs;
    try {
      final jobs = await backend.listSemanticParseJobsByMessageIds(
        sessionKey,
        messageIds: <String>[message.id],
      );
      for (final job in jobs) {
        if (job.messageId != message.id) continue;
        if ((job.appliedActionKind ?? '').trim() != 'followup') continue;
        final undoneAtMs = job.undoneAtMs?.toInt();
        if (undoneAtMs == null) continue;
        if (undoneFollowupCutoffMs == null ||
            undoneAtMs > undoneFollowupCutoffMs) {
          undoneFollowupCutoffMs = undoneAtMs;
        }
      }
    } catch (_) {
      undoneFollowupCutoffMs = null;
    }

    try {
      final activities = await backend.listTodoActivitiesInRange(
        sessionKey,
        startAtMsInclusive: 0,
        endAtMsExclusive: DateTime.now().toUtc().millisecondsSinceEpoch + 1,
      );
      for (final activity in activities) {
        if (activity.sourceMessageId != message.id) continue;
        if (undoneFollowupCutoffMs != null &&
            activity.activityType == 'status_change' &&
            activity.createdAtMs.toInt() <= undoneFollowupCutoffMs) {
          continue;
        }
        final todo = todosById[activity.todoId];
        if (todo == null || todo.status == 'dismissed') continue;
        return (todo: todo, isSourceEntry: false);
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  Future<void> _convertMessageToTodo(Message message) async {
    if (!mounted) return;

    final rawText = _displayTextForMessage(message);
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final linkedTodoInfo = await _resolveLinkedTodoInfo(message);
    if (!mounted) return;
    final todoId = 'todo:${message.id}';

    final locale = Localizations.localeOf(context);
    final firstDayOfWeekIndex =
        MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final settings = await ActionsSettingsStore.load();
    if (!mounted) return;

    final nowLocal = DateTime.now();
    final timeResolution = LocalTimeResolver.resolve(
      trimmed,
      nowLocal,
      locale: locale,
      dayEndMinutes: settings.dayEndMinutes,
      morningMinutes: settings.morningMinutes,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    );

    DateTime? dueAtLocal;
    var convertWithoutDue = false;
    final candidates = timeResolution?.candidates ?? const <DueCandidate>[];
    if (candidates.isNotEmpty) {
      dueAtLocal = candidates.first.dueAtLocal;
    } else {
      final initialLocal = DateTime(
        nowLocal.year,
        nowLocal.month,
        nowLocal.day,
        settings.dayEndTime.hour,
        settings.dayEndTime.minute,
      );
      dueAtLocal = await showSlDateTimePickerDialog(
        context,
        initialLocal: initialLocal,
        firstDate: DateTime(nowLocal.year - 1),
        lastDate: DateTime(nowLocal.year + 3),
        title: context.t.actions.calendar.pickCustom,
        surfaceKey: ValueKey('message_convert_todo_due_picker_${message.id}'),
        noDueActionLabel: context.t.common.actions.notNow,
        noDueActionKey: ValueKey('message_convert_todo_no_due_${message.id}'),
        onNoDueAction: () => convertWithoutDue = true,
      );
    }

    if ((dueAtLocal == null && !convertWithoutDue) || !mounted) return;

    final dueAtMs = dueAtLocal?.toUtc().millisecondsSinceEpoch;
    var status = 'open';
    int? reviewStage;
    int? nextReviewAtMs;
    if (dueAtMs == null) {
      final nextLocal = ReviewBackoff.initialNextReviewAt(
        DateTime.now(),
        settings,
      );
      status = 'inbox';
      reviewStage = 0;
      nextReviewAtMs = nextLocal.toUtc().millisecondsSinceEpoch;
    }

    try {
      await createTodoWithFollowup(
        backend,
        sessionKey,
        id: todoId,
        title: trimmed,
        dueAtMs: dueAtMs,
        status: status,
        sourceEntryId: message.id,
        reviewStage: reviewStage,
        nextReviewAtMs: nextReviewAtMs,
        lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      if (linkedTodoInfo != null && !linkedTodoInfo.isSourceEntry) {
        await _moveLinkedTodoActivitiesForMessage(
          messageId: message.id,
          toTodoId: todoId,
        );
      }
    } catch (_) {
      return;
    }

    if (!mounted) return;
    syncEngine?.notifyLocalMutation();
    _refresh(refreshTaskPriority: true);
  }
}
