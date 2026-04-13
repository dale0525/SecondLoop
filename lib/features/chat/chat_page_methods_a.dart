part of 'chat_page.dart';

const _kCloudDetachedRequestIdPayloadKey = 'secondloop_cloud_request_id';
const _kDetachedTodoIdPrefix = 'todo:_detached_message_link:';
const _kDetachedTodoTitlePrefix = '[detached] ';
const _kMessageCopyCardDivider = '\n\n----------\n\n';
final RegExp _kCloudDetachedRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9:_-]{5,127}$',
);

extension _ChatPageStateMethodsA on _ChatPageState {
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
      if (!_isAtBottom) {
        _setState(() {
          _hasUnseenNewMessages = true;
          _taskPriorityStore?.markDirty();
        });
        unawaited(
            _taskPriorityStore?.refresh(force: true) ?? Future<void>.value());
        return;
      }
      _refresh();
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
    final backend = AppBackendScope.of(context);
    final viewerBackend = maybeKnowledgeViewerBackendFor(backend);
    final knowledgeBackend = maybeKnowledgeBackendFor(backend);
    final pagesBackend = maybeKnowledgePagesBackendFor(backend);
    final hasPagesBackend = pagesBackend != null;
    final hasViewerBackend = viewerBackend != null;
    final hasKnowledgeBackend = knowledgeBackend != null;
    Future<void> openMemoryCard(String documentId) {
      return MemoryDetailPage.openDocumentId(
        context,
        documentId: documentId,
      );
    }

    bool canOpenMemoryCard(String documentId) {
      return canOpenEvidenceMemoryCard(
        documentId,
        hasPagesBackend: hasPagesBackend,
        hasViewerBackend: hasViewerBackend,
      );
    }

    Future<ChatAnswerEvidenceMemoryCard?> correctMemoryCard(
      ChatAnswerEvidenceMemoryCard card,
      String title,
      String summary,
    ) {
      return _correctMemoryFromEvidence(
        card,
        title: title,
        summary: summary,
      );
    }

    bool canMutateMemoryCard(String documentId) {
      return canMutateEvidenceMemoryCard(
        documentId,
        hasPagesBackend: hasPagesBackend,
        hasKnowledgeBackend: hasKnowledgeBackend,
        hasViewerBackend: hasViewerBackend,
      );
    }

    Future<ChatAnswerEvidenceMemoryCard?> refreshMemoryCard(
      ChatAnswerEvidenceMemoryCard card,
    ) {
      return _refreshMemoryFromEvidence(card);
    }

    Future<void> disableMemoryCard(String documentId) {
      return _disableMemoryFromEvidence(documentId);
    }

    Future<void> deleteMemoryCard(String documentId) {
      return _deleteMemoryFromEvidence(documentId);
    }

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
          onOpenDirectSource: (target) async {
            await _handleMarkdownInAppLink(target);
          },
          onOpenMemoryCard: openMemoryCard,
          canOpenMemoryCard: canOpenMemoryCard,
          onCorrectMemoryCard: correctMemoryCard,
          canCorrectMemoryCard: canMutateMemoryCard,
          onRefreshMemoryCard: refreshMemoryCard,
          onDisableMemoryCard: disableMemoryCard,
          canDisableMemoryCard: canMutateMemoryCard,
          onDeleteMemoryCard: deleteMemoryCard,
          canDeleteMemoryCard: canMutateMemoryCard,
        );
        if (handledCitation) {
          return;
        }
        await handleChatMarkdownTapLink(
          href,
          handleInApp: _handleMarkdownInAppLink,
        );
      },
      onTapLink: (text, href, title) {
        unawaited(
          handleChatMarkdownTapLink(
            href,
            handleInApp: _handleMarkdownInAppLink,
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

  bool _canOpenKnowledgeHref(String href) {
    if (parseKnowledgeDocumentDeepLink(href) != null) {
      return maybeKnowledgeViewerBackendFor(AppBackendScope.of(context)) !=
          null;
    }
    return true;
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
            createdAtMs: committedMessage.createdAtMs,
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
            final dueA = a.dueAtMs ?? 9223372036854775807;
            final dueB = b.dueAtMs ?? 9223372036854775807;
            if (dueA != dueB) return dueA.compareTo(dueB);
            return b.updatedAtMs.compareTo(a.updatedAtMs);
          });
        return (todo: sorted.first, isSourceEntry: true);
      }

      final sorted = sourceTodos.toList(growable: false)
        ..sort((a, b) {
          final dueA = a.dueAtMs ?? -9223372036854775808;
          final dueB = b.dueAtMs ?? -9223372036854775808;
          if (dueA != dueB) return dueB.compareTo(dueA);
          return b.updatedAtMs.compareTo(a.updatedAtMs);
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
    final settings = await ActionsSettingsStore.load();
    if (!mounted) return;

    final nowLocal = DateTime.now();
    final timeResolution = LocalTimeResolver.resolve(
      trimmed,
      nowLocal,
      locale: locale,
      dayEndMinutes: settings.dayEndMinutes,
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
    _refresh();
  }

  Future<void> _convertMessageTodoToInfo(
      Message message, Todo? linkedTodo) async {
    if (linkedTodo == null) return;
    if (!mounted) return;

    final shouldConvert = await _showDialogFromChat<bool>(
      builder: (context) {
        return AlertDialog(
          title:
              Text(context.t.chat.messageActions.convertTodoToInfoConfirmTitle),
          content:
              Text(context.t.chat.messageActions.convertTodoToInfoConfirmBody),
          actions: [
            SlButton(
              variant: SlButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t.common.actions.cancel),
            ),
            SlButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t.common.fields.confirm),
            ),
          ],
        );
      },
    );
    if (shouldConvert != true || !mounted) return;

    if (linkedTodo.sourceEntryId != message.id) {
      await _undoFollowupLinkForMessage(message, linkedTodo: linkedTodo);
      return;
    }

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final linkedMessageIds = <String>{message.id};
    final sourceTodos = <Todo>[];

    try {
      final todos = await backend.listTodos(sessionKey);
      for (final todo in todos) {
        if (todo.sourceEntryId == message.id) {
          sourceTodos.add(todo);
        }
      }
    } catch (_) {
      // ignore
    }
    if (sourceTodos.isEmpty) {
      sourceTodos.add(linkedTodo);
    }

    for (final sourceTodo in sourceTodos) {
      try {
        final activities = await backend.listTodoActivities(
          sessionKey,
          sourceTodo.id,
        );
        for (final activity in activities) {
          final sourceMessageId = activity.sourceMessageId?.trim();
          if (sourceMessageId == null || sourceMessageId.isEmpty) {
            continue;
          }
          linkedMessageIds.add(sourceMessageId);
        }
      } catch (_) {
        // ignore
      }

      try {
        await backend.upsertTodo(
          sessionKey,
          id: sourceTodo.id,
          title: sourceTodo.title,
          dueAtMs: null,
          status: 'dismissed',
          sourceEntryId: null,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: sourceTodo.lastReviewAtMs,
        );
      } catch (_) {
        return;
      }
    }

    for (final linkedMessageId in linkedMessageIds) {
      try {
        await backend.markSemanticParseJobUndone(
          sessionKey,
          messageId: linkedMessageId,
          nowMs: nowMs,
        );
      } catch (_) {
        // ignore
      }
    }

    if (!mounted) return;
    syncEngine?.notifyLocalMutation();
    _refresh();
  }

  Future<void> _ensureDetachedTodoExistsForMessage(
    Message message, {
    Todo? linkedTodo,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final detachedTodoId = '$_kDetachedTodoIdPrefix${message.id}';
    final linkedTitle = linkedTodo?.title.trim() ?? '';
    final fallbackTitle = _displayTextForMessage(message).trim();
    final title = linkedTitle.isNotEmpty
        ? linkedTitle
        : fallbackTitle.isEmpty
            ? '$_kDetachedTodoTitlePrefix${message.id}'
            : '$_kDetachedTodoTitlePrefix$fallbackTitle';

    await backend.upsertTodo(
      sessionKey,
      id: detachedTodoId,
      title: title.trim(),
      dueAtMs: null,
      status: 'dismissed',
      sourceEntryId: null,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowMs,
    );
  }

  Future<void> _undoFollowupLinkForMessage(
    Message message, {
    Todo? linkedTodo,
  }) async {
    if (!mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final detachedTodoId = '$_kDetachedTodoIdPrefix${message.id}';

    try {
      await _ensureDetachedTodoExistsForMessage(
        message,
        linkedTodo: linkedTodo,
      );
    } catch (_) {
      return;
    }

    try {
      await _moveLinkedTodoActivitiesForMessage(
        messageId: message.id,
        toTodoId: detachedTodoId,
      );
    } catch (_) {
      return;
    }

    SemanticParseJob? latestFollowup;
    try {
      final jobs = await backend.listSemanticParseJobsByMessageIds(
        sessionKey,
        messageIds: <String>[message.id],
      );
      for (final job in jobs) {
        if (job.messageId != message.id) continue;
        if ((job.appliedActionKind ?? '').trim() != 'followup') continue;
        if (job.undoneAtMs != null) continue;
        final appliedTodoId = job.appliedTodoId?.trim();
        if (linkedTodo != null &&
            appliedTodoId != null &&
            appliedTodoId.isNotEmpty &&
            appliedTodoId != linkedTodo.id) {
          continue;
        }
        if (latestFollowup == null ||
            job.updatedAtMs.toInt() > latestFollowup.updatedAtMs.toInt()) {
          latestFollowup = job;
        }
      }
    } catch (_) {
      latestFollowup = null;
    }

    try {
      final todoId = latestFollowup?.appliedTodoId?.trim();
      final prevStatus = latestFollowup?.appliedPrevTodoStatus?.trim();
      if (todoId != null &&
          todoId.isNotEmpty &&
          prevStatus != null &&
          prevStatus.isNotEmpty) {
        await backend.setTodoStatus(
          sessionKey,
          todoId: todoId,
          newStatus: prevStatus,
        );
      }
    } catch (_) {
      // ignore
    }

    try {
      await backend.markSemanticParseJobUndone(
        sessionKey,
        messageId: message.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    syncEngine?.notifyLocalMutation();
    _refresh();
  }

  Future<List<TodoActivity>> _listLinkedTodoActivitiesForMessage({
    required String messageId,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return const <TodoActivity>[];

    final activities = await backend.listTodoActivitiesInRange(
      sessionKey,
      startAtMsInclusive: 0,
      endAtMsExclusive: DateTime.now().toUtc().millisecondsSinceEpoch + 1,
    );
    return activities
        .where((activity) => activity.sourceMessageId == normalizedMessageId)
        .toList(growable: false);
  }

  Future<int> _moveLinkedTodoActivitiesForMessage({
    required String messageId,
    required String toTodoId,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final normalizedTargetTodoId = toTodoId.trim();
    if (normalizedTargetTodoId.isEmpty) return 0;

    final activities = await _listLinkedTodoActivitiesForMessage(
      messageId: messageId,
    );

    var moved = 0;
    for (final activity in activities) {
      if (activity.todoId == normalizedTargetTodoId) continue;
      await backend.moveTodoActivity(
        sessionKey,
        activityId: activity.id,
        toTodoId: normalizedTargetTodoId,
      );
      moved += 1;
    }
    return moved;
  }

  Future<void> _openLinkedTodo(Todo? linkedTodo) async {
    if (linkedTodo == null) return;
    if (!mounted) return;
    await _pushRouteFromChat(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          TodoDetailPage(initialTodo: linkedTodo),
        ),
      ),
    );
  }

  String? _extractCloudDetachedRequestIdFromPayloadJson(String? payloadJson) {
    final raw = payloadJson?.trim() ?? '';
    if (raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final requestId =
          (decoded[_kCloudDetachedRequestIdPayloadKey] ?? '').toString().trim();
      if (!_kCloudDetachedRequestIdPattern.hasMatch(requestId)) {
        return null;
      }
      return requestId;
    } catch (_) {
      return null;
    }
  }

  Uri? _buildCloudDetachedCancelUri(String gatewayBaseUrl, String requestId) {
    final base = gatewayBaseUrl.trim();
    final normalizedRequestId = requestId.trim();
    if (base.isEmpty || normalizedRequestId.isEmpty) return null;

    final normalizedBase = base.replaceFirst(RegExp(r'/+$'), '');
    try {
      return Uri.parse(
        '$normalizedBase/v1/chat/jobs/$normalizedRequestId/cancel',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _cancelCloudDetachedChatJob({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) async {
    if (!_kCloudDetachedRequestIdPattern.hasMatch(requestId.trim())) {
      return;
    }
    final uri = _buildCloudDetachedCancelUri(gatewayBaseUrl, requestId);
    if (uri == null) return;

    final token = idToken.trim();
    if (token.isEmpty) return;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 6));
      await resp.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _bestEffortCancelCloudMediaJobsForMessage({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String messageId,
  }) async {
    final cloudScope = CloudAuthScope.maybeOf(context);
    final gatewayBaseUrl = (cloudScope?.gatewayConfig.baseUrl ?? '').trim();
    if (gatewayBaseUrl.isEmpty) return;

    final idToken = await readCloudCapabilityIdToken(
      cloudScope?.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );
    if ((idToken ?? '').trim().isEmpty) return;

    if (backend is! NativeAppBackend) return;

    List<Attachment> attachments;
    try {
      attachments = await backend.listMessageAttachments(
        sessionKey,
        messageId,
      );
    } catch (_) {
      return;
    }

    if (attachments.isEmpty) return;

    final requestIds = <String>{};
    for (final attachment in attachments) {
      try {
        final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
          sessionKey,
          sha256: attachment.sha256,
        );
        final requestId =
            _extractCloudDetachedRequestIdFromPayloadJson(payloadJson);
        if (requestId == null) continue;
        requestIds.add(requestId);
      } catch (_) {
        // ignore per-attachment parse failures
      }
    }

    if (requestIds.isEmpty) return;

    for (final requestId in requestIds) {
      try {
        await _cancelCloudDetachedChatJob(
          gatewayBaseUrl: gatewayBaseUrl,
          idToken: idToken!,
          requestId: requestId,
        );
      } catch (_) {
        // best-effort only
      }
    }
  }

  Future<void> _deleteMessage(
    Message message, {
    ({Todo todo, bool isSourceEntry})? linkedTodoInfo,
  }) async {
    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;

      if (message.id == _kFailedAskMessageId) {
        final confirmed = await showSlDeleteConfirmDialog(
          context,
          title: t.chat.deleteMessageDialog.title,
          message: t.chat.deleteMessageDialog.message,
          confirmButtonKey: const ValueKey('chat_delete_message_confirm'),
        );
        if (!mounted) return;
        if (!confirmed) return;

        _setState(() {
          _askFailureQuestion = null;
          _askFailureMessage = null;
          _askFailureCreatedAtMs = null;
          _askFailureAnchorMessageId = null;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(t.chat.messageDeleted),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      var resolvedLinkedTodoInfo = linkedTodoInfo;
      if (resolvedLinkedTodoInfo == null) {
        resolvedLinkedTodoInfo = await _resolveLinkedTodoInfo(message);
        if (!mounted) return;
      }

      final targetTodo = resolvedLinkedTodoInfo?.todo;
      final isSourceEntry = resolvedLinkedTodoInfo?.isSourceEntry == true;
      if (targetTodo != null && isSourceEntry) {
        final confirmed = await showSlDeleteConfirmDialog(
          context,
          title: t.actions.todoDelete.dialog.title,
          message: t.actions.todoDelete.dialog.message,
          confirmLabel: t.actions.todoDelete.dialog.confirm,
          confirmButtonKey: const ValueKey('chat_delete_todo_confirm'),
        );
        if (!mounted) return;
        if (!confirmed) return;

        final linkedTodos = await backend.listTodos(sessionKey);
        final todoIds = linkedTodos
            .where((todo) => todo.sourceEntryId == message.id)
            .map((todo) => todo.id)
            .toSet();
        if (todoIds.isEmpty) {
          todoIds.add(targetTodo.id);
        }

        for (final todoId in todoIds) {
          await backend.deleteTodo(sessionKey, todoId: todoId);
        }
        if (!mounted) return;
        syncEngine?.notifyLocalMutation();
        _refresh();
        messenger.showSnackBar(
          SnackBar(
            content: Text(t.chat.messageDeleted),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      final confirmed = await showSlDeleteConfirmDialog(
        context,
        title: t.chat.deleteMessageDialog.title,
        message: t.chat.deleteMessageDialog.message,
        confirmButtonKey: const ValueKey('chat_delete_message_confirm'),
      );
      if (!mounted) return;
      if (!confirmed) return;

      await _bestEffortCancelCloudMediaJobsForMessage(
        backend: backend,
        sessionKey: sessionKey,
        messageId: message.id,
      );
      await backend.purgeMessageAttachments(sessionKey, message.id);
      try {
        await backend.markSemanticParseJobCanceled(
          sessionKey,
          messageId: message.id,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        // ignore
      }
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(t.chat.messageDeleted),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(t.chat.deleteFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
