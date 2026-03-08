part of 'chat_page.dart';

extension _ChatPageStateMessageItemBuilder on _ChatPageState {
  IndexedWidgetBuilder _buildMessageListItemBuilder({
    required List<Message> messages,
    required int extraCount,
    required bool hasPendingAssistant,
    required String pendingAssistantText,
    required String? pendingFailureMessage,
    required String? pendingQuestion,
    required AttachmentsBackend? attachmentsBackend,
    required Uint8List sessionKey,
    required Map<String, SemanticParseJob> jobsByMessageId,
    required Map<String, _TodoMessageBadgeMeta> linkedTodoBadgeByMessageId,
    required Map<String, AttachmentAnnotationJob> annotationJobsBySha256,
    required bool attachmentAnnotationEnabled,
    required bool attachmentAnnotationCanRunNow,
    required bool audioTranscribeEnabled,
    required bool audioTranscribeCanRunNow,
    required ColorScheme colorScheme,
    required SlTokens tokens,
    required bool isDesktopPlatform,
  }) {
    return (context, index) {
      Message? messageAt(int targetIndex) {
        if (_usePagination) {
          if (targetIndex < extraCount) {
            var extraIndex = targetIndex;
            if (hasPendingAssistant) {
              if (extraIndex == 0) {
                return Message(
                  id: 'pending_assistant',
                  conversationId: widget.conversation.id,
                  role: 'assistant',
                  content: '',
                  createdAtMs: 0,
                  isMemory: false,
                );
              }
              extraIndex -= 1;
            }
            if (pendingQuestion != null && extraIndex == 0) {
              return Message(
                id: 'pending_user',
                conversationId: widget.conversation.id,
                role: 'user',
                content: pendingQuestion,
                createdAtMs: 0,
                isMemory: false,
              );
            }
            return null;
          }
          final messageIndex = targetIndex - extraCount;
          if (messageIndex < 0 || messageIndex >= messages.length) {
            return null;
          }
          return messages[messageIndex];
        }

        if (targetIndex < messages.length) {
          return messages[targetIndex];
        }

        var extraIndex = targetIndex - messages.length;
        if (pendingQuestion != null) {
          if (extraIndex == 0) {
            return Message(
              id: 'pending_user',
              conversationId: widget.conversation.id,
              role: 'user',
              content: pendingQuestion,
              createdAtMs: 0,
              isMemory: false,
            );
          }
          extraIndex -= 1;
        }
        if (_asking && !_stopRequested && extraIndex == 0) {
          return Message(
            id: 'pending_assistant',
            conversationId: widget.conversation.id,
            role: 'assistant',
            content: '',
            createdAtMs: 0,
            isMemory: false,
          );
        }
        return null;
      }

      Message? msg;
      String? textOverride;
      if (_usePagination) {
        if (index < extraCount) {
          var extraIndex = index;
          if (hasPendingAssistant) {
            if (extraIndex == 0) {
              msg = Message(
                id: 'pending_assistant',
                conversationId: widget.conversation.id,
                role: 'assistant',
                content: '',
                createdAtMs: 0,
                isMemory: false,
              );
              textOverride = pendingAssistantText;
            }
            extraIndex -= 1;
          }
          if (msg == null && pendingQuestion != null && extraIndex == 0) {
            msg = Message(
              id: 'pending_user',
              conversationId: widget.conversation.id,
              role: 'user',
              content: pendingQuestion,
              createdAtMs: 0,
              isMemory: false,
            );
          }
        } else {
          msg = messages[index - extraCount];
        }
      } else {
        if (index < messages.length) {
          msg = messages[index];
        } else {
          var extraIndex = index - messages.length;
          if (pendingQuestion != null) {
            if (extraIndex == 0) {
              msg = Message(
                id: 'pending_user',
                conversationId: widget.conversation.id,
                role: 'user',
                content: pendingQuestion,
                createdAtMs: 0,
                isMemory: false,
              );
            }
            extraIndex -= 1;
          }
          if (msg == null && hasPendingAssistant && extraIndex == 0) {
            msg = Message(
              id: 'pending_assistant',
              conversationId: widget.conversation.id,
              role: 'assistant',
              content: '',
              createdAtMs: 0,
              isMemory: false,
            );
            textOverride = pendingAssistantText;
          }
        }
      }

      final stableMsg = msg;
      if (stableMsg == null) {
        return const SizedBox.shrink();
      }

      final itemCount = messages.length + extraCount;
      final dividerState = _resolveMessageDividerState(
        index: index,
        stableMsg: stableMsg,
        itemCount: itemCount,
        messageAt: messageAt,
      );
      final dayLocal = dividerState.dayLocal;
      final showDateDivider = dividerState.showDateDivider;
      final showTimeDivider = dividerState.showTimeDivider;
      final interleavedDivider = _buildInterleavedMessageDivider(
        context: context,
        stableMsg: stableMsg,
        dayLocal: dayLocal,
        showDateDivider: showDateDivider,
        showTimeDivider: showTimeDivider,
      );

      final isUser = stableMsg.role == 'user';
      final bubbleShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isUser
              ? colorScheme.primary.withOpacity(
                  Theme.of(context).brightness == Brightness.dark ? 0.28 : 0.22,
                )
              : tokens.borderSubtle,
        ),
      );
      final bubbleColor =
          isUser ? colorScheme.primaryContainer : tokens.surface2;

      final isPending = _isTransientPendingMessageId(stableMsg.id);
      final isPendingAssistant = stableMsg.id == 'pending_assistant';
      final showAskAiWaitingIndicator = isPendingAssistant &&
          pendingFailureMessage == null &&
          _asking &&
          !_stopRequested &&
          _streamingAnswer.isEmpty;
      final showAskAiTypingIndicator = isPendingAssistant &&
          pendingFailureMessage == null &&
          _asking &&
          !_stopRequested &&
          _streamingAnswer.isNotEmpty;
      final showHoverMenu = !isPending && _hoveredMessageId == stableMsg.id;
      final supportsAttachments = attachmentsBackend != null && !isPending;
      final attachmentsLoadedForEdit = !supportsAttachments ||
          _attachmentLinkingMessageIds.contains(stableMsg.id) ||
          _attachmentsCacheByMessageId.containsKey(stableMsg.id);

      if (supportsAttachments && !attachmentsLoadedForEdit) {
        unawaited(
          _loadMessageAttachmentsForUi(
            messageId: stableMsg.id,
            attachmentsBackend: attachmentsBackend,
            sessionKey: sessionKey,
          ),
        );
      }

      final editableRole = stableMsg.role == 'user' ||
          (stableMsg.role == 'assistant' && !stableMsg.isMemory);
      final canEditMessage = editableRole &&
          stableMsg.id != _kFailedAskMessageId &&
          !isPending &&
          (!supportsAttachments ||
              (attachmentsLoadedForEdit &&
                  !_messageHasAttachmentInCache(stableMsg.id)));

      final rawText = textOverride ?? stableMsg.content;
      final assistantActions = (!isPending && stableMsg.role == 'assistant')
          ? parseAssistantMessageActions(rawText)
          : null;
      final rawDisplayText = assistantActions?.displayText ?? rawText;
      final displayText = _isPhotoPlaceholderText(context, rawDisplayText)
          ? ''
          : rawDisplayText;
      final actionSuggestions = assistantActions?.suggestions?.suggestions ??
          const <ActionSuggestion>[];
      final todoBadgeMeta = _todoMessageBadgeMetaForMessage(
          message: stableMsg,
          jobsByMessageId: jobsByMessageId,
          linkedTodoBadgeByMessageId: linkedTodoBadgeByMessageId,
          displayText: displayText);

      final shouldCollapse = !isPending &&
          _shouldCollapseMessage(displayText) &&
          actionSuggestions.isEmpty;
      final isFailedPendingUser =
          stableMsg.id == _kFailedAskMessageId && pendingFailureMessage != null;
      final hoverActionCount = 1 +
          (canEditMessage ? 1 : 0) +
          (stableMsg.id != _kFailedAskMessageId ? 1 : 0);
      final hoverMenuWidth =
          (hoverActionCount * 32.0) + ((hoverActionCount - 1) * 6.0);

      final hoverMenuSlot = _hoverActionsEnabled && !isPending
          ? Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
              ),
              child: SizedBox(
                width: hoverMenuWidth,
                height: 32,
                child: showHoverMenu
                    ? Row(
                        mainAxisAlignment: isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (canEditMessage) ...[
                            SlIconButton(
                              key: ValueKey('message_edit_${stableMsg.id}'),
                              icon: Icons.edit_rounded,
                              onPressed: () => _editMessage(stableMsg),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (stableMsg.id != _kFailedAskMessageId) ...[
                            SlIconButton(
                              key: ValueKey('message_tags_${stableMsg.id}'),
                              icon: Icons.sell_outlined,
                              tooltip: context.t.chat.tagPicker.tagActionLabel,
                              onPressed: () =>
                                  unawaited(_openMessageTagPicker(stableMsg)),
                            ),
                            const SizedBox(width: 6),
                          ],
                          SlIconButton(
                            key: ValueKey('message_delete_${stableMsg.id}'),
                            icon: Icons.delete_outline_rounded,
                            color: colorScheme.error,
                            overlayBaseColor: colorScheme.error,
                            borderColor: colorScheme.error.withOpacity(
                              Theme.of(context).brightness == Brightness.dark
                                  ? 0.32
                                  : 0.22,
                            ),
                            onPressed: () => _deleteMessage(stableMsg),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            )
          : const SizedBox.shrink();
      final retryFailedAskSlot = isFailedPendingUser
          ? Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                key: const ValueKey('chat_ask_ai_retry_pending_user'),
                tooltip: context.t.common.actions.retry,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  Icons.error_rounded,
                  color: colorScheme.error,
                  size: 20,
                ),
                onPressed: (_asking || _sending)
                    ? null
                    : () => unawaited(_retryAskAiFailedQuestion()),
              ),
            )
          : const SizedBox.shrink();

      final hasContentAboveAttachments = displayText.trim().isNotEmpty ||
          shouldCollapse ||
          actionSuggestions.isNotEmpty ||
          !stableMsg.isMemory;
      final hasKnownAttachments = _messageHasAttachmentInCache(stableMsg.id);
      final mayHaveAttachments = supportsAttachments &&
          (hasKnownAttachments || !attachmentsLoadedForEdit);
      final shouldEnableBubbleTap = !isPending &&
          ((shouldCollapse && !isDesktopPlatform) ||
              todoBadgeMeta != null ||
              mayHaveAttachments);
      final bubble = ConstrainedBox(
        key: ValueKey('message_bubble_${stableMsg.id}'),
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: bubbleColor,
          shape: bubbleShape,
          child: Listener(
            onPointerDown: isPending
                ? null
                : (event) {
                    final kind = event.kind;
                    final isPointerKind = kind == PointerDeviceKind.mouse ||
                        kind == PointerDeviceKind.trackpad;
                    if (!isPointerKind) return;
                    if (event.buttons & kSecondaryMouseButton == 0) {
                      return;
                    }
                    unawaited(
                      _showMessageContextMenu(
                        stableMsg,
                        event.position,
                      ),
                    );
                  },
            child: InkWell(
              onTap: !shouldEnableBubbleTap
                  ? null
                  : () => unawaited(
                        () async {
                          final openedDetail =
                              await _openMessageBubblePrimaryDetail(
                            message: stableMsg,
                            todoBadgeMeta: todoBadgeMeta,
                            attachmentsBackend:
                                mayHaveAttachments ? attachmentsBackend : null,
                            sessionKey: sessionKey,
                          );
                          if (openedDetail) return;
                          if (shouldCollapse && !isDesktopPlatform) {
                            await _openMessageViewer(displayText);
                          }
                        }(),
                      ),
              onLongPress: isDesktopPlatform
                  ? null
                  : () => _showMessageActions(stableMsg),
              canRequestFocus: isDesktopPlatform,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.zero,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!stableMsg.isMemory)
                            Padding(
                              key: ValueKey(
                                'message_ask_ai_badge_${stableMsg.id}',
                              ),
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 14,
                                    color: colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    context.t.common.actions.askAi,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: colorScheme.secondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          if (todoBadgeMeta != null)
                            _buildTodoTypeBadge(
                                message: stableMsg,
                                meta: todoBadgeMeta,
                                colorScheme: colorScheme),
                          if (shouldCollapse)
                            SizedBox(
                              height: _kCollapsedMessageHeight,
                              child: ClipRect(
                                child: Stack(
                                  children: [
                                    ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context)
                                          .copyWith(
                                        scrollbars: false,
                                        overscroll: false,
                                      ),
                                      child: SingleChildScrollView(
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        child: _buildMessageMarkdown(
                                          displayText,
                                          isDesktopPlatform: isDesktopPlatform,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      height: 32,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              bubbleColor.withOpacity(0),
                                              bubbleColor,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            isPendingAssistant && pendingFailureMessage == null
                                ? (showAskAiWaitingIndicator
                                    ? Padding(
                                        padding: const EdgeInsets.only(
                                          top: 2,
                                        ),
                                        child: SlTypingIndicator(
                                          key: const ValueKey(
                                              'ask_ai_waiting_indicator'),
                                          dotSize: 7,
                                          dotSpacing: 5,
                                          color: colorScheme.onSurfaceVariant
                                              .withOpacity(
                                            Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? 0.72
                                                : 0.6,
                                          ),
                                        ),
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (displayText.trim().isNotEmpty)
                                            _buildMessageMarkdown(
                                              displayText,
                                              isDesktopPlatform:
                                                  isDesktopPlatform,
                                            ),
                                          if (showAskAiTypingIndicator)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: SlTypingIndicator(
                                                key: const ValueKey(
                                                    'ask_ai_typing_indicator'),
                                                dotSize: 4,
                                                dotSpacing: 3,
                                                color: colorScheme
                                                    .onSurfaceVariant
                                                    .withOpacity(
                                                  Theme.of(context)
                                                              .brightness ==
                                                          Brightness.dark
                                                      ? 0.62
                                                      : 0.5,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ))
                                : (displayText.trim().isEmpty
                                    ? const SizedBox.shrink()
                                    : _buildMessageMarkdown(
                                        displayText,
                                        isDesktopPlatform: isDesktopPlatform,
                                      )),
                          if (todoBadgeMeta != null)
                            _buildRelatedTodoRootQuote(
                                message: stableMsg,
                                meta: todoBadgeMeta,
                                colorScheme: colorScheme),
                          if (shouldCollapse)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: ValueKey(
                                  'message_view_full_${stableMsg.id}',
                                ),
                                onPressed: () => unawaited(
                                  _openMessageViewer(displayText),
                                ),
                                child: Text(context.t.chat.viewFull),
                              ),
                            ),
                          if (actionSuggestions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (var i = 0;
                                      i < actionSuggestions.length;
                                      i++)
                                    SlButton(
                                      variant: SlButtonVariant.outline,
                                      onPressed: () =>
                                          _handleAssistantSuggestion(
                                        stableMsg,
                                        actionSuggestions[i],
                                        i,
                                      ),
                                      icon: Icon(
                                        actionSuggestions[i].type == 'event'
                                            ? Icons.event_rounded
                                            : Icons
                                                .check_circle_outline_rounded,
                                        size: 18,
                                      ),
                                      child: Text(
                                        actionSuggestions[i]
                                                    .whenText
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true
                                            ? '${actionSuggestions[i].title} (${actionSuggestions[i].whenText})'
                                            : actionSuggestions[i].title,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (supportsAttachments)
                            _buildMessageAttachmentSection(
                              context: context,
                              message: stableMsg,
                              isUser: isUser,
                              colorScheme: colorScheme,
                              hasContentAboveAttachments:
                                  hasContentAboveAttachments,
                              attachmentsBackend: attachmentsBackend,
                              sessionKey: sessionKey,
                              annotationJobsBySha256: annotationJobsBySha256,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      return Padding(
        key: ValueKey('chat_message_row_${stableMsg.id}'),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (interleavedDivider != null) interleavedDivider,
            MouseRegion(
              onEnter: isPending
                  ? null
                  : (_) => _setState(
                        () {
                          _hoverActionsEnabled = true;
                          _hoveredMessageId = stableMsg.id;
                        },
                      ),
              onExit: isPending
                  ? null
                  : (_) => _setState(() {
                        if (_hoveredMessageId == stableMsg.id) {
                          _hoveredMessageId = null;
                        }
                      }),
              child: Row(
                mainAxisAlignment:
                    isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (isUser) hoverMenuSlot,
                  if (isUser) retryFailedAskSlot,
                  Flexible(child: bubble),
                  if (!isUser) hoverMenuSlot,
                ],
              ),
            ),
            if (isFailedPendingUser)
              Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(44, 2, 4, 0),
                    child: Text(
                      pendingFailureMessage,
                      key: const ValueKey('chat_ask_ai_error_pending_user'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.error.withOpacity(
                              Theme.of(context).brightness == Brightness.dark
                                  ? 0.92
                                  : 0.9,
                            ),
                            height: 1.3,
                          ),
                    ),
                  ),
                ),
              ),
            if (supportsAttachments && annotationJobsBySha256.isNotEmpty)
              FutureBuilder<List<Attachment>>(
                initialData: _attachmentsCacheByMessageId[stableMsg.id],
                future: _loadMessageAttachmentsForUi(
                  messageId: stableMsg.id,
                  attachmentsBackend: attachmentsBackend,
                  sessionKey: sessionKey,
                ),
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <Attachment>[];
                  if (items.isEmpty) return const SizedBox.shrink();

                  Attachment? targetAttachment;
                  AttachmentAnnotationJob? targetJob;
                  for (final a in items) {
                    final job = annotationJobsBySha256[a.sha256];
                    if (job != null) {
                      targetAttachment = a;
                      targetJob = job;
                      break;
                    }
                  }
                  final attachment = targetAttachment;
                  final job = targetJob;
                  if (attachment == null || job == null) {
                    return const SizedBox.shrink();
                  }

                  Future<void> retry() async {
                    final backendAny = AppBackendScope.of(context);
                    if (backendAny is! NativeAppBackend) return;
                    final syncEngine = SyncEngineScope.maybeOf(context);

                    final lang = job.lang.trim().isNotEmpty
                        ? job.lang.trim()
                        : Localizations.localeOf(context).toLanguageTag();

                    try {
                      final nowMs = DateTime.now().millisecondsSinceEpoch;
                      if (isAudioTranscribeCandidateMimeType(
                        attachment.mimeType,
                      )) {
                        await maybeEnqueueAudioTranscribe(
                          backend: backendAny,
                          sessionKey: sessionKey,
                          attachmentSha256: attachment.sha256,
                          mimeType: attachment.mimeType,
                          lang: lang,
                          respectFeatureToggle: false,
                          nowMs: nowMs,
                          beforeEnqueue: () =>
                              bestEffortWarmCloudCapabilityAuth(
                            CloudAuthScope.maybeOf(context)?.controller,
                          ),
                        );
                      } else {
                        await bestEffortWarmCloudCapabilityAuth(
                          CloudAuthScope.maybeOf(context)?.controller,
                        );
                        await backendAny.enqueueAttachmentAnnotation(
                          sessionKey,
                          attachmentSha256: attachment.sha256,
                          lang: lang,
                          nowMs: nowMs,
                        );
                      }
                      syncEngine?.notifyExternalChange();
                    } catch (_) {
                      // ignore
                    }
                  }

                  final jobUiState = resolveAttachmentAnnotationJobUiState(
                    mimeType: attachment.mimeType,
                    t: context.t,
                    isZhLocale: Localizations.localeOf(context)
                        .languageCode
                        .toLowerCase()
                        .startsWith('zh'),
                    annotationEnabled: attachmentAnnotationEnabled,
                    annotationCanRunNow: attachmentAnnotationCanRunNow,
                    audioTranscribeEnabled: audioTranscribeEnabled,
                    audioTranscribeCanRunNow: audioTranscribeCanRunNow,
                  );

                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: AttachmentAnnotationJobStatusRow(
                      job: job,
                      annotateEnabled: jobUiState.enabled,
                      canAnnotateNow: jobUiState.canRunNow,
                      mimeType: attachment.mimeType,
                      setupRequiredLabel: jobUiState.setupRequiredLabel,
                      onOpenSetup: () async {
                        await _pushRouteFromChat(
                          MaterialPageRoute(
                            builder: (context) => Scaffold(
                              appBar: AppBar(
                                title: Text(context.t.settings.title),
                              ),
                              body: const SettingsPage(),
                            ),
                          ),
                        );
                      },
                      onOpenLocalCapabilityDownload: () async {
                        await _pushRouteFromChat(
                          MaterialPageRoute(
                            builder: (_) => const AiSettingsPage(
                              focusSection:
                                  AiSettingsSection.mediaUnderstanding,
                              highlightFocus: true,
                              focusMediaLocalCapabilityCard: true,
                            ),
                          ),
                        );
                      },
                      onRetry: job.status == 'failed' ? retry : null,
                      onInstallSpeechPack: job.status == 'failed'
                          ? () async {
                              await _openWindowsSpeechLanguagePackSettings();
                            }
                          : null,
                    ),
                  );
                },
              ),
            if (isUser &&
                !isPending &&
                jobsByMessageId.containsKey(stableMsg.id))
              Align(
                alignment: Alignment.centerRight,
                child: SemanticParseJobStatusRow(
                  message: stableMsg,
                  job: jobsByMessageId[stableMsg.id]!,
                ),
              ),
          ],
        ),
      );
    };
  }
}
