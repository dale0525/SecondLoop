part of 'chat_page.dart';

extension _ChatPageStateMessageEditMethods on _ChatPageState {
  Future<void> _editMessage(Message message) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);

    Future<({String content, bool openMarkdown})?> showSimpleEditor(
      String initialText,
    ) {
      var draft = initialText;
      return showDialog<({String content, bool openMarkdown})>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.t.chat.editMessageTitle),
          content: SizedBox(
            width: 560,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('edit_message_content'),
                    initialValue: initialText,
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 1,
                    maxLines: 6,
                    onChanged: (value) => draft = value,
                    decoration: InputDecoration(
                      hintText: context.t.common.fields.message,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('chat_markdown_editor_switch_markdown'),
                  tooltip: context.t.chat.markdownEditor.openButton,
                  onPressed: () => Navigator.of(dialogContext).pop(
                    (content: draft, openMarkdown: true),
                  ),
                  icon: const Icon(Icons.open_in_full_rounded),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton.icon(
              key: const ValueKey('edit_message_save'),
              onPressed: () => Navigator.of(dialogContext).pop(
                (content: draft, openMarkdown: false),
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(context.t.common.actions.save),
            ),
          ],
        ),
      );
    }

    Future<ChatMarkdownEditorResult?> showMarkdownEditor(String initialText) {
      return _pushRouteFromChat<ChatMarkdownEditorResult>(
        MaterialPageRoute(
          builder: (context) => ChatMarkdownEditorPage(
            initialText: initialText,
            title: context.t.chat.editMessageTitle,
            saveLabel: context.t.common.actions.save,
            inputFieldKey: const ValueKey('edit_message_content'),
            saveButtonKey: const ValueKey('edit_message_save'),
            allowPlainMode: true,
            initialMode: ChatEditorMode.markdown,
          ),
        ),
      );
    }

    try {
      var draft = message.content;
      var useMarkdown = shouldUseMarkdownEditorByDefault(draft);

      while (true) {
        if (useMarkdown) {
          final markdownResult = await showMarkdownEditor(draft);
          if (markdownResult == null) return;
          draft = markdownResult.text;
          if (markdownResult.shouldSwitchToSimpleInput) {
            useMarkdown = false;
            continue;
          }
        } else {
          final plainResult = await showSimpleEditor(draft);
          if (plainResult == null) return;
          draft = plainResult.content;
          if (plainResult.openMarkdown) {
            useMarkdown = true;
            continue;
          }
        }

        final trimmed = draft.trim();
        await backend.editMessage(sessionKey, message.id, trimmed);

        var shouldRequeueSemanticParse = false;
        try {
          final linkedTodoInfo = await _resolveLinkedTodoInfo(message);
          shouldRequeueSemanticParse =
              shouldRequeueSemanticParseAfterMessageEdit(
            previousText: message.content,
            editedText: trimmed,
            isSourceEntry: linkedTodoInfo?.isSourceEntry == true,
          );

          if (linkedTodoInfo != null && linkedTodoInfo.isSourceEntry) {
            final recurrenceRuleJson = await backend.getTodoRecurrenceRuleJson(
              sessionKey,
              todoId: linkedTodoInfo.todo.id,
            );
            if (recurrenceRuleJson != null &&
                recurrenceRuleJson.trim().isNotEmpty) {
              final settings = await ActionsSettingsStore.load();
              if (!mounted) return;

              final locale = Localizations.localeOf(context);
              final nowLocal = DateTime.now();
              final timeResolution = LocalTimeResolver.resolve(
                trimmed,
                nowLocal,
                locale: locale,
                dayEndMinutes: settings.dayEndMinutes,
              );
              if (timeResolution != null &&
                  timeResolution.candidates.length == 1) {
                final dueAtLocal = timeResolution.candidates.single.dueAtLocal;
                await backend.updateTodoDueWithScope(
                  sessionKey,
                  todoId: linkedTodoInfo.todo.id,
                  dueAtMs: dueAtLocal.toUtc().millisecondsSinceEpoch,
                  scope: TodoRecurrenceEditScope.thisAndFuture,
                );
              }
            }
          }
        } catch (_) {
          // ignore: message edit should still succeed even if todo sync fails.
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        try {
          await backend.markSemanticParseJobCanceled(
            sessionKey,
            messageId: message.id,
            nowMs: nowMs,
          );
        } catch (_) {
          // ignore
        }

        if (shouldRequeueSemanticParse && mounted) {
          final subscriptionStatus =
              SubscriptionScope.maybeOf(context)?.status ??
                  SubscriptionStatus.unknown;
          final cloudAuthScope = CloudAuthScope.maybeOf(context);
          final cloudGatewayConfig =
              cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

          final prefs = await SharedPreferences.getInstance();
          final consented =
              prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false;

          if (consented) {
            String? cloudIdToken;
            try {
              cloudIdToken = await cloudAuthScope?.controller.getIdToken();
            } catch (_) {
              cloudIdToken = null;
            }

            AskAiRouteKind route;
            try {
              route = await decideAiAutomationRoute(
                backend,
                sessionKey,
                cloudIdToken: cloudIdToken,
                cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
                subscriptionStatus: subscriptionStatus,
              );
            } catch (_) {
              route = AskAiRouteKind.needsSetup;
            }

            if (route != AskAiRouteKind.needsSetup) {
              try {
                await backend.enqueueSemanticParseJob(
                  sessionKey,
                  messageId: message.id,
                  nowMs: nowMs,
                );
              } catch (_) {
                // ignore
              }
            }
          }
        }

        if (!mounted) return;
        syncEngine?.notifyLocalMutation();
        _refresh();
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.t.chat.messageUpdated),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.chat.editFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
