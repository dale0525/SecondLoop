part of 'chat_page.dart';

extension _ChatPageStateBuild on _ChatPageState {
  Widget _build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = SlTokens.of(context);
    final isDesktopPlatform = _isDesktopPlatform;
    final useCompactComposer = !isDesktopPlatform;
    final title = widget.conversation.id == 'main_stream'
        ? context.t.chat.mainStreamTitle
        : widget.conversation.title;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<bool>(
            initialValue: _thisThreadOnly,
            onSelected: (value) => _setState(() => _thisThreadOnly = value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: false,
                child: Text(context.t.chat.focus.allMemories),
              ),
              PopupMenuItem(
                value: true,
                child: Text(context.t.chat.focus.thisThread),
              ),
            ],
            tooltip: context.t.chat.focus.tooltip,
            child: const SlIconButtonFrame(
              key: ValueKey('chat_filter_menu'),
              icon: Icons.filter_alt_rounded,
            ),
          ),
          if (!isDesktopPlatform)
            IconButton(
              key: const ValueKey('chat_open_settings'),
              tooltip: context.t.app.tabs.settings,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: Text(context.t.settings.title)),
                      body: const SettingsPage(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<_TodoAgendaSummary>(
            future: _agendaFuture,
            builder: (context, snapshot) {
              final summary = snapshot.data ?? const _TodoAgendaSummary.empty();
              return TodoAgendaBanner(
                dueCount: summary.dueCount,
                overdueCount: summary.overdueCount,
                upcomingCount: summary.upcomingCount,
                previewTodos: summary.previewTodos,
                collapseSignal: _todoAgendaBannerCollapseSignal,
                onViewAll: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TodoAgendaPage(),
                    ),
                  );
                  if (!mounted) return;
                  _collapseTodoAgendaBanner();
                  _refresh();
                },
              );
            },
          ),
          FutureBuilder<int>(
            future: _reviewCountFuture,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return ReviewQueueBanner(
                count: count,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ReviewQueuePage(),
                    ),
                  );
                  if (!mounted) return;
                  _refresh();
                },
              );
            },
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder(
                      future: _messagesFuture,
                      builder: (context, snapshot) {
                        final isLoading =
                            snapshot.connectionState != ConnectionState.done;
                        final loadedMessages = _usePagination
                            ? _paginatedMessages
                            : snapshot.data ?? const <Message>[];
                        final messages =
                            _messagesWithFailedAskQuestion(loadedMessages);
                        final pendingQuestion = _pendingQuestion;
                        final pendingFailureMessage = _askFailureMessage;
                        final hasPendingAssistant = _asking && !_stopRequested;
                        final pendingAssistantText =
                            _streamingAnswer.isEmpty ? '…' : _streamingAnswer;
                        final extraCount = (hasPendingAssistant ? 1 : 0) +
                            (pendingQuestion == null ? 0 : 1);
                        if (messages.isEmpty && extraCount == 0) {
                          if (isLoading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                context.t.errors
                                    .loadFailed(error: '${snapshot.error}'),
                              ),
                            );
                          }
                          return Center(
                            child: Text(context.t.chat.noMessagesYet),
                          );
                        }

                        final messageIndexById = <String, int>{};
                        for (var i = 0; i < messages.length; i++) {
                          messageIndexById[messages[i].id] = i;
                        }

                        final backend = AppBackendScope.of(context);
                        final sessionKey = SessionScope.of(context).sessionKey;
                        final attachmentsBackend = backend is AttachmentsBackend
                            ? backend as AttachmentsBackend
                            : null;
                        final semanticJobsFuture =
                            Future<List<SemanticParseJob>>.sync(() {
                          if (messages.isEmpty) {
                            return const <SemanticParseJob>[];
                          }
                          final ids = messages
                              .map((m) => m.id)
                              .where((id) => !id.startsWith('pending_'))
                              .toList(growable: false);
                          return backend.listSemanticParseJobsByMessageIds(
                            sessionKey,
                            messageIds: ids,
                          );
                        }).catchError((_) => const <SemanticParseJob>[]);

                        final nativeBackend =
                            backend is NativeAppBackend ? backend : null;
                        final annotationJobsFuture =
                            Future<List<AttachmentAnnotationJob>>.sync(() {
                          if (nativeBackend == null) {
                            return const <AttachmentAnnotationJob>[];
                          }

                          // For chat UI we want *all* non-ok jobs, regardless of next_retry_at.
                          const maxI64 = 9223372036854775807;
                          return nativeBackend.listDueAttachmentAnnotations(
                            sessionKey,
                            nowMs: maxI64,
                            limit: 500,
                          );
                        }).catchError((_) => const <AttachmentAnnotationJob>[]);

                        final linkedTodoBadgeFuture =
                            _loadLinkedTodoBadgesForMessages(
                          backend: backend,
                          sessionKey: sessionKey,
                          messages: messages,
                        );

                        final combinedJobsFuture = (() async {
                          final semanticJobs = await semanticJobsFuture;
                          final annotationJobs = await annotationJobsFuture;
                          final linkedTodoBadges = await linkedTodoBadgeFuture;
                          final annotationUi =
                              nativeBackend == null || annotationJobs.isEmpty
                                  ? (enabled: false, canRunNow: false)
                                  : await _loadAttachmentAnnotationUiState(
                                      nativeBackend,
                                      sessionKey,
                                    );
                          return (
                            semanticJobs: semanticJobs,
                            linkedTodoBadges: linkedTodoBadges,
                            annotationJobs: annotationJobs,
                            attachmentAnnotationEnabled: annotationUi.enabled,
                            attachmentAnnotationCanRunNow:
                                annotationUi.canRunNow,
                          );
                        })();

                        return FutureBuilder<
                            ({
                              List<SemanticParseJob> semanticJobs,
                              Map<String,
                                  _TodoMessageBadgeMeta> linkedTodoBadges,
                              List<AttachmentAnnotationJob> annotationJobs,
                              bool attachmentAnnotationEnabled,
                              bool attachmentAnnotationCanRunNow,
                            })>(
                          future: combinedJobsFuture,
                          builder: (context, snapshotJobs) {
                            final jobs = snapshotJobs.data?.semanticJobs ??
                                const <SemanticParseJob>[];
                            final linkedTodoBadgeByMessageId =
                                snapshotJobs.data?.linkedTodoBadges ??
                                    const <String, _TodoMessageBadgeMeta>{};
                            final jobsByMessageId =
                                <String, SemanticParseJob>{};
                            for (final job in jobs) {
                              jobsByMessageId[job.messageId] = job;
                            }

                            final annotationJobs =
                                snapshotJobs.data?.annotationJobs ??
                                    const <AttachmentAnnotationJob>[];
                            final annotationJobsBySha256 =
                                <String, AttachmentAnnotationJob>{};
                            for (final job in annotationJobs) {
                              annotationJobsBySha256[job.attachmentSha256] =
                                  job;
                            }

                            return ListView.builder(
                              key: _usePagination
                                  ? const ValueKey('chat_message_list')
                                  : null,
                              controller:
                                  _usePagination ? _scrollController : null,
                              reverse: _usePagination,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              findChildIndexCallback: (key) {
                                if (key is! ValueKey) return null;
                                final v = key.value;
                                if (v is! String) return null;
                                if (!v.startsWith('chat_message_row_')) {
                                  return null;
                                }
                                final messageId =
                                    v.substring('chat_message_row_'.length);

                                if (messageId == 'pending_assistant') {
                                  if (!hasPendingAssistant) return null;
                                  if (_usePagination) return 0;
                                  return messages.length +
                                      (pendingQuestion == null ? 0 : 1);
                                }

                                if (messageId == 'pending_user') {
                                  if (pendingQuestion == null) return null;
                                  if (_usePagination) {
                                    return hasPendingAssistant ? 1 : 0;
                                  }
                                  return messages.length;
                                }

                                final messageIndex =
                                    messageIndexById[messageId];
                                if (messageIndex == null) return null;
                                return _usePagination
                                    ? messageIndex + extraCount
                                    : messageIndex;
                              },
                              itemCount: messages.length + extraCount,
                              itemBuilder: _buildMessageListItemBuilder(
                                messages: messages,
                                extraCount: extraCount,
                                hasPendingAssistant: hasPendingAssistant,
                                pendingAssistantText: pendingAssistantText,
                                pendingFailureMessage: pendingFailureMessage,
                                pendingQuestion: pendingQuestion,
                                attachmentsBackend: attachmentsBackend,
                                sessionKey: sessionKey,
                                jobsByMessageId: jobsByMessageId,
                                linkedTodoBadgeByMessageId:
                                    linkedTodoBadgeByMessageId,
                                annotationJobsBySha256: annotationJobsBySha256,
                                attachmentAnnotationEnabled: snapshotJobs
                                        .data?.attachmentAnnotationEnabled ??
                                    false,
                                attachmentAnnotationCanRunNow: snapshotJobs
                                        .data?.attachmentAnnotationCanRunNow ??
                                    false,
                                colorScheme: colorScheme,
                                tokens: tokens,
                                isDesktopPlatform: isDesktopPlatform,
                              ),
                            );
                          },
                        );
                      },
                    ),
                    if (_usePagination && !_isAtBottom)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: FloatingActionButton.small(
                          key: const ValueKey('chat_jump_to_latest'),
                          onPressed: _jumpToLatest,
                          backgroundColor: colorScheme.secondaryContainer,
                          foregroundColor: colorScheme.onSecondaryContainer,
                          child: const Icon(Icons.arrow_downward_rounded),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_askError != null)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _askError!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: useCompactComposer
                      ? SlFocusRing(
                          key: const ValueKey('chat_input_ring'),
                          borderRadius: BorderRadius.circular(tokens.radiusLg),
                          child: SlSurface(
                            color: tokens.surface2,
                            borderColor: tokens.borderSubtle,
                            borderRadius:
                                BorderRadius.circular(tokens.radiusLg),
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Focus(
                                    // ignore: deprecated_member_use
                                    onKey: (node, event) {
                                      // ignore: deprecated_member_use
                                      if (event is! RawKeyDownEvent) {
                                        return KeyEventResult.ignored;
                                      }

                                      final key = event.logicalKey;
                                      bool isShortcutChar(String char) =>
                                          char == 'a' ||
                                          char == 'c' ||
                                          char == 'v' ||
                                          char == 'x';

                                      String? keyChar;
                                      final keyLabel = event.data.keyLabel;
                                      if (keyLabel.length == 1) {
                                        final lowered = keyLabel.toLowerCase();
                                        if (isShortcutChar(lowered)) {
                                          keyChar = lowered;
                                        }
                                      }
                                      if (keyChar == null) {
                                        final rawChar = event.character;
                                        if (rawChar != null &&
                                            rawChar.length == 1) {
                                          final lowered = rawChar.toLowerCase();
                                          if (isShortcutChar(lowered)) {
                                            keyChar = lowered;
                                          }
                                        }
                                      }
                                      final composing =
                                          _controller.value.composing;
                                      final isComposing = composing.isValid &&
                                          !composing.isCollapsed;

                                      final hardware =
                                          HardwareKeyboard.instance;
                                      final metaPressed =
                                          hardware.isMetaPressed;
                                      final controlPressed =
                                          hardware.isControlPressed;
                                      final shiftPressed =
                                          hardware.isShiftPressed;
                                      final hasModifier =
                                          metaPressed || controlPressed;

                                      final isPaste =
                                          key == LogicalKeyboardKey.paste ||
                                              ((keyChar == 'v' ||
                                                      key ==
                                                          LogicalKeyboardKey
                                                              .keyV) &&
                                                  hasModifier);
                                      if (isPaste) {
                                        unawaited(_pasteIntoChatInput());
                                        return KeyEventResult.handled;
                                      }

                                      final isSelectAll = hasModifier &&
                                          (keyChar == 'a' ||
                                              (keyChar == null &&
                                                  key ==
                                                      LogicalKeyboardKey.keyA));
                                      if (isSelectAll) {
                                        final textLength =
                                            _controller.value.text.length;
                                        _controller.selection = TextSelection(
                                          baseOffset: 0,
                                          extentOffset: textLength,
                                        );
                                        return KeyEventResult.handled;
                                      }

                                      final isCopy = (key ==
                                                  LogicalKeyboardKey.copy ||
                                              keyChar == 'c' ||
                                              key == LogicalKeyboardKey.keyC) &&
                                          hasModifier;
                                      if (isCopy) {
                                        final value = _controller.value;
                                        final selection = value.selection;
                                        if (selection.isValid &&
                                            !selection.isCollapsed) {
                                          final start = selection.start;
                                          final end = selection.end;
                                          final normalizedStart =
                                              start < end ? start : end;
                                          final normalizedEnd =
                                              start < end ? end : start;
                                          final selectedText =
                                              value.text.substring(
                                            normalizedStart,
                                            normalizedEnd,
                                          );
                                          unawaited(
                                            Clipboard.setData(
                                              ClipboardData(text: selectedText),
                                            ),
                                          );
                                        }
                                        return KeyEventResult.handled;
                                      }

                                      final isCut = (key ==
                                                  LogicalKeyboardKey.cut ||
                                              keyChar == 'x' ||
                                              key == LogicalKeyboardKey.keyX) &&
                                          hasModifier;
                                      if (isCut) {
                                        final value = _controller.value;
                                        final selection = value.selection;
                                        if (selection.isValid &&
                                            !selection.isCollapsed) {
                                          final start = selection.start;
                                          final end = selection.end;
                                          final normalizedStart =
                                              start < end ? start : end;
                                          final normalizedEnd =
                                              start < end ? end : start;
                                          final selectedText =
                                              value.text.substring(
                                            normalizedStart,
                                            normalizedEnd,
                                          );
                                          unawaited(
                                            Clipboard.setData(
                                              ClipboardData(text: selectedText),
                                            ),
                                          );
                                          final updatedText =
                                              value.text.replaceRange(
                                            normalizedStart,
                                            normalizedEnd,
                                            '',
                                          );
                                          _controller.value = value.copyWith(
                                            text: updatedText,
                                            selection: TextSelection.collapsed(
                                              offset: normalizedStart,
                                            ),
                                            composing: TextRange.empty,
                                          );
                                        }
                                        return KeyEventResult.handled;
                                      }

                                      if (key != LogicalKeyboardKey.enter &&
                                          key !=
                                              LogicalKeyboardKey.numpadEnter) {
                                        return KeyEventResult.ignored;
                                      }

                                      if (event.repeat) {
                                        return KeyEventResult.handled;
                                      }

                                      if (isComposing) {
                                        return KeyEventResult.ignored;
                                      }

                                      if (shiftPressed) {
                                        final value = _controller.value;
                                        final selection = value.selection;
                                        final start = selection.isValid
                                            ? selection.start
                                            : value.text.length;
                                        final end = selection.isValid
                                            ? selection.end
                                            : value.text.length;
                                        final normalizedStart =
                                            start < end ? start : end;
                                        final normalizedEnd =
                                            start < end ? end : start;
                                        final updatedText =
                                            value.text.replaceRange(
                                          normalizedStart,
                                          normalizedEnd,
                                          '\n',
                                        );
                                        _controller.value = value.copyWith(
                                          text: updatedText,
                                          selection: TextSelection.collapsed(
                                            offset: normalizedStart + 1,
                                          ),
                                          composing: TextRange.empty,
                                        );
                                        return KeyEventResult.handled;
                                      }

                                      unawaited(_send());
                                      return KeyEventResult.handled;
                                    },
                                    child: TextField(
                                      key: const ValueKey('chat_input'),
                                      focusNode: _inputFocusNode,
                                      controller: _controller,
                                      decoration: InputDecoration(
                                        hintText:
                                            context.t.common.fields.message,
                                        border: InputBorder.none,
                                        filled: false,
                                        isDense: true,
                                      ),
                                      keyboardType: TextInputType.multiline,
                                      textInputAction: TextInputAction.newline,
                                      minLines: 1,
                                      maxLines: 6,
                                    ),
                                  ),
                                ),
                                _buildCompactComposerActions(
                                  context,
                                  tokens: tokens,
                                  colorScheme: colorScheme,
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildDesktopDropTargetComposer(
                          context,
                          tokens: tokens,
                          colorScheme: colorScheme,
                          child: SlFocusRing(
                            key: const ValueKey('chat_input_ring'),
                            borderRadius:
                                BorderRadius.circular(tokens.radiusLg),
                            child: SlSurface(
                              color: tokens.surface2,
                              borderColor: tokens.borderSubtle,
                              borderRadius:
                                  BorderRadius.circular(tokens.radiusLg),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Focus(
                                      // ignore: deprecated_member_use
                                      onKey: (node, event) {
                                        // ignore: deprecated_member_use
                                        if (event is! RawKeyDownEvent) {
                                          return KeyEventResult.ignored;
                                        }

                                        final key = event.logicalKey;
                                        bool isShortcutChar(String char) =>
                                            char == 'a' ||
                                            char == 'c' ||
                                            char == 'v' ||
                                            char == 'x';

                                        String? keyChar;
                                        final keyLabel = event.data.keyLabel;
                                        if (keyLabel.length == 1) {
                                          final lowered =
                                              keyLabel.toLowerCase();
                                          if (isShortcutChar(lowered)) {
                                            keyChar = lowered;
                                          }
                                        }
                                        if (keyChar == null) {
                                          final rawChar = event.character;
                                          if (rawChar != null &&
                                              rawChar.length == 1) {
                                            final lowered =
                                                rawChar.toLowerCase();
                                            if (isShortcutChar(lowered)) {
                                              keyChar = lowered;
                                            }
                                          }
                                        }
                                        final composing =
                                            _controller.value.composing;
                                        final isComposing = composing.isValid &&
                                            !composing.isCollapsed;

                                        final hardware =
                                            HardwareKeyboard.instance;
                                        final metaPressed =
                                            hardware.isMetaPressed;
                                        final controlPressed =
                                            hardware.isControlPressed;
                                        final shiftPressed =
                                            hardware.isShiftPressed;
                                        final hasModifier =
                                            metaPressed || controlPressed;

                                        final isPaste =
                                            key == LogicalKeyboardKey.paste ||
                                                ((keyChar == 'v' ||
                                                        key ==
                                                            LogicalKeyboardKey
                                                                .keyV) &&
                                                    hasModifier);
                                        if (isPaste) {
                                          unawaited(_pasteIntoChatInput());
                                          return KeyEventResult.handled;
                                        }

                                        final isSelectAll = hasModifier &&
                                            (keyChar == 'a' ||
                                                (keyChar == null &&
                                                    key ==
                                                        LogicalKeyboardKey
                                                            .keyA));
                                        if (isSelectAll) {
                                          final textLength =
                                              _controller.value.text.length;
                                          _controller.selection = TextSelection(
                                            baseOffset: 0,
                                            extentOffset: textLength,
                                          );
                                          return KeyEventResult.handled;
                                        }

                                        final isCopy = (key ==
                                                    LogicalKeyboardKey.copy ||
                                                keyChar == 'c' ||
                                                key ==
                                                    LogicalKeyboardKey.keyC) &&
                                            hasModifier;
                                        if (isCopy) {
                                          final value = _controller.value;
                                          final selection = value.selection;
                                          if (selection.isValid &&
                                              !selection.isCollapsed) {
                                            final start = selection.start;
                                            final end = selection.end;
                                            final normalizedStart =
                                                start < end ? start : end;
                                            final normalizedEnd =
                                                start < end ? end : start;
                                            final selectedText =
                                                value.text.substring(
                                              normalizedStart,
                                              normalizedEnd,
                                            );
                                            unawaited(
                                              Clipboard.setData(
                                                ClipboardData(
                                                    text: selectedText),
                                              ),
                                            );
                                          }
                                          return KeyEventResult.handled;
                                        }

                                        final isCut = (key ==
                                                    LogicalKeyboardKey.cut ||
                                                keyChar == 'x' ||
                                                key ==
                                                    LogicalKeyboardKey.keyX) &&
                                            hasModifier;
                                        if (isCut) {
                                          final value = _controller.value;
                                          final selection = value.selection;
                                          if (selection.isValid &&
                                              !selection.isCollapsed) {
                                            final start = selection.start;
                                            final end = selection.end;
                                            final normalizedStart =
                                                start < end ? start : end;
                                            final normalizedEnd =
                                                start < end ? end : start;
                                            final selectedText =
                                                value.text.substring(
                                              normalizedStart,
                                              normalizedEnd,
                                            );
                                            unawaited(
                                              Clipboard.setData(
                                                ClipboardData(
                                                    text: selectedText),
                                              ),
                                            );
                                            final updatedText =
                                                value.text.replaceRange(
                                              normalizedStart,
                                              normalizedEnd,
                                              '',
                                            );
                                            _controller.value = value.copyWith(
                                              text: updatedText,
                                              selection:
                                                  TextSelection.collapsed(
                                                offset: normalizedStart,
                                              ),
                                              composing: TextRange.empty,
                                            );
                                          }
                                          return KeyEventResult.handled;
                                        }

                                        if (key != LogicalKeyboardKey.enter &&
                                            key !=
                                                LogicalKeyboardKey
                                                    .numpadEnter) {
                                          return KeyEventResult.ignored;
                                        }

                                        if (event.repeat) {
                                          return KeyEventResult.handled;
                                        }

                                        if (isComposing) {
                                          return KeyEventResult.ignored;
                                        }

                                        if (shiftPressed) {
                                          final value = _controller.value;
                                          final selection = value.selection;
                                          final start = selection.isValid
                                              ? selection.start
                                              : value.text.length;
                                          final end = selection.isValid
                                              ? selection.end
                                              : value.text.length;
                                          final normalizedStart =
                                              start < end ? start : end;
                                          final normalizedEnd =
                                              start < end ? end : start;
                                          final updatedText =
                                              value.text.replaceRange(
                                            normalizedStart,
                                            normalizedEnd,
                                            '\n',
                                          );
                                          _controller.value = value.copyWith(
                                            text: updatedText,
                                            selection: TextSelection.collapsed(
                                              offset: normalizedStart + 1,
                                            ),
                                            composing: TextRange.empty,
                                          );
                                          return KeyEventResult.handled;
                                        }

                                        unawaited(_send());
                                        return KeyEventResult.handled;
                                      },
                                      child: TextField(
                                        key: const ValueKey('chat_input'),
                                        focusNode: _inputFocusNode,
                                        controller: _controller,
                                        decoration: InputDecoration(
                                          hintText:
                                              context.t.common.fields.message,
                                          border: InputBorder.none,
                                          filled: false,
                                        ),
                                        keyboardType: TextInputType.multiline,
                                        textInputAction:
                                            TextInputAction.newline,
                                        minLines: 1,
                                        maxLines: 6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_supportsImageUpload ||
                                      _supportsDesktopRecordAudioAction) ...[
                                    if (_supportsDesktopRecordAudioAction) ...[
                                      Semantics(
                                        label: context.t.chat.attachRecordAudio,
                                        button: true,
                                        child: SlIconButton(
                                          key: const ValueKey(
                                              'chat_record_audio'),
                                          icon: Icons.mic_rounded,
                                          size: 44,
                                          iconSize: 22,
                                          tooltip:
                                              context.t.chat.attachRecordAudio,
                                          onPressed: _isComposerBusy
                                              ? null
                                              : () => unawaited(
                                                    _recordAndSendAudioFromSheet(),
                                                  ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (_supportsImageUpload) ...[
                                      Semantics(
                                        label: context.t.chat.attachTooltip,
                                        button: true,
                                        child: SlIconButton(
                                          key: const ValueKey('chat_attach'),
                                          icon: Icons.add_rounded,
                                          size: 44,
                                          iconSize: 22,
                                          tooltip: context.t.chat.attachTooltip,
                                          onPressed: _isComposerBusy
                                              ? null
                                              : _openAttachmentSheet,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ],
                                  ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: _controller,
                                    builder: (context, value, child) {
                                      final hasText =
                                          value.text.trim().isNotEmpty;

                                      if (_asking) {
                                        return SlButton(
                                          buttonKey:
                                              const ValueKey('chat_stop'),
                                          icon: const Icon(
                                            Icons.stop_circle_outlined,
                                            size: 18,
                                          ),
                                          variant: SlButtonVariant.outline,
                                          onPressed:
                                              _stopRequested ? null : _stopAsk,
                                          child: Text(
                                            _stopRequested
                                                ? context
                                                    .t.common.actions.stopping
                                                : context.t.common.actions.stop,
                                          ),
                                        );
                                      }

                                      if (!hasText) {
                                        return const SizedBox.shrink();
                                      }

                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SlButton(
                                            buttonKey:
                                                const ValueKey('chat_ask_ai'),
                                            icon: const Icon(
                                              Icons.auto_awesome_rounded,
                                              size: 18,
                                            ),
                                            variant: SlButtonVariant.secondary,
                                            onPressed:
                                                _isComposerBusy ? null : _askAi,
                                            child: Text(
                                              context.t.common.actions.askAi,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SlButton(
                                            buttonKey:
                                                const ValueKey('chat_send'),
                                            icon: const Icon(
                                              Icons.send_rounded,
                                              size: 18,
                                            ),
                                            variant: SlButtonVariant.primary,
                                            onPressed:
                                                _isComposerBusy ? null : _send,
                                            child: Text(
                                              context.t.common.actions.send,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
