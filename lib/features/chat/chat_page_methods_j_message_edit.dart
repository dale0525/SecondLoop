part of 'chat_page.dart';

extension _ChatPageStateMessageEditMethods on _ChatPageState {
  Future<void> _editMessage(Message message) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final initialText = message.role == 'assistant'
        ? _displayTextForMessage(message)
        : message.content;

    try {
      final markdownResult = await openChatMarkdownEditor(
        context,
        initialText: initialText,
        title: context.t.chat.editMessageTitle,
        saveLabel: context.t.common.actions.save,
        inputFieldKey: const ValueKey('edit_message_content'),
        saveButtonKey: const ValueKey('edit_message_save'),
        allowPlainMode: false,
        routePusher: (route) => _pushRouteFromChat(route),
      );
      if (markdownResult == null) return;

      var trimmed = markdownResult.text.trim();
      final noChange = message.role == 'assistant'
          ? trimmed == initialText.trim()
          : trimmed == message.content;
      if (noChange) return;

      if (markdownResult.draftAttachments.isNotEmpty) {
        if (backend is! NativeAppBackend) {
          if (!mounted) return;
          messenger.showSnackBar(
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

        final nativeBackend = backend;
        final submission = await editMarkdownEditorMessage(
          messageId: message.id,
          markdown: markdownResult.text,
          draftAttachments: markdownResult.draftAttachments,
          ingestAttachment: (draft) => _ingestComposerDraftAttachment(
            nativeBackend,
            sessionKey,
            draft,
          ),
          editMessage: (messageId, content) =>
              backend.editMessage(sessionKey, messageId, content),
          linkAttachmentToMessage: (messageId, attachmentSha256) =>
              nativeBackend.linkAttachmentToMessage(
            sessionKey,
            messageId,
            attachmentSha256: attachmentSha256,
          ),
        );
        final draftsByLocalId = {
          for (final draft in markdownResult.draftAttachments)
            draft.localId: draft,
        };
        for (final entry in submission.ingestedAttachmentShaByLocalId.entries) {
          final draft = draftsByLocalId[entry.key];
          if (draft == null) continue;
          await _handleLinkedDraftAttachment(
            nativeBackend,
            sessionKey,
            entry.value,
            draft,
          );
        }
        trimmed = submission.markdown.trim();
      } else {
        await backend.editMessage(sessionKey, message.id, trimmed);
      }

      var shouldRequeueSemanticParse = false;
      try {
        final linkedTodoInfo = await _resolveLinkedTodoInfo(message);
        shouldRequeueSemanticParse = shouldRequeueSemanticParseAfterMessageEdit(
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
        final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
            SubscriptionStatus.unknown;
        final cloudAuthScope = CloudAuthScope.maybeOf(context);
        final cloudGatewayConfig =
            cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

        final prefs = await SharedPreferences.getInstance();
        final consented =
            prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false;

        if (consented) {
          final cloudIdToken = await readCloudCapabilityIdToken(
            cloudAuthScope?.controller,
            mode: CloudCapabilityAuthMode.interactive,
          );

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
              await bestEffortWarmCloudCapabilityAuth(
                cloudAuthScope?.controller,
              );
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
