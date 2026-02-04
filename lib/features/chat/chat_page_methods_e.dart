part of 'chat_page.dart';

extension _ChatPageStateMethodsE on _ChatPageState {
  Future<void> _stopAsk() async {
    final sub = _askSub;
    if (!_asking || _stopRequested) return;

    _setState(() {
      _stopRequested = true;
      _askSub = null;
      _asking = false;
      _pendingQuestion = null;
      _streamingAnswer = '';
    });

    if (sub != null) {
      unawaited(sub.cancel());
    }

    if (!mounted) return;
    _setState(() => _stopRequested = false);
  }

  Future<void> _askAi() async {
    if (_asking) return;
    if (_sending) return;

    final question = _controller.text.trim();
    if (question.isEmpty) return;

    _askFailureTimer?.cancel();
    _askFailureTimer = null;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    String? cloudIdToken;
    try {
      cloudIdToken = await cloudAuthScope?.controller.getIdToken();
    } catch (_) {
      cloudIdToken = null;
    }

    if (!mounted) return;
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;

    final route = await decideAskAiRoute(
      backend,
      sessionKey,
      cloudIdToken: cloudIdToken,
      cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
      subscriptionStatus: subscriptionStatus,
    );

    if (route == AskAiRouteKind.needsSetup) {
      final configured = await _ensureAskAiConfigured(backend, sessionKey);
      if (!configured) return;
    }

    final consented = await _ensureAskAiDataConsent();
    if (!consented) return;

    final allowCloudEmbeddings = route == AskAiRouteKind.cloudGateway &&
        await _ensureEmbeddingsDataConsent();
    final hasBrokEmbeddings = route == AskAiRouteKind.byok &&
        await _hasActiveEmbeddingProfile(backend, sessionKey);
    const topK = 10;

    _setState(() {
      _asking = true;
      _stopRequested = false;
      _askError = null;
      _askFailureMessage = null;
      _askFailureQuestion = null;
      _pendingQuestion = question;
      _streamingAnswer = '';
    });
    _controller.clear();

    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    final firstDayOfWeekIndex =
        MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final nowLocal = DateTime.now();
    final intent = AskAiIntentResolver.resolve(
      question,
      nowLocal,
      locale: locale,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    );

    var timeStartMs =
        intent.timeRange?.startLocal.toUtc().millisecondsSinceEpoch;
    var timeEndMs = intent.timeRange?.endLocal.toUtc().millisecondsSinceEpoch;
    if (timeStartMs == null || timeEndMs == null) {
      String? json;
      try {
        final future = route == AskAiRouteKind.cloudGateway
            ? backend.semanticParseAskAiTimeWindowCloudGateway(
                sessionKey,
                question: question,
                nowLocalIso: nowLocal.toIso8601String(),
                locale: locale,
                firstDayOfWeekIndex: firstDayOfWeekIndex,
                gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                idToken: cloudIdToken ?? '',
                modelName: cloudGatewayConfig.modelName,
              )
            : backend.semanticParseAskAiTimeWindow(
                sessionKey,
                question: question,
                nowLocalIso: nowLocal.toIso8601String(),
                locale: locale,
                firstDayOfWeekIndex: firstDayOfWeekIndex,
              );
        json = await future.timeout(_kAiSemanticParseTimeout);
      } catch (_) {
        json = null;
      }

      if (json != null && mounted) {
        final parsed = AiSemanticParse.tryParseAskAiTimeWindow(
          json,
          nowLocal: nowLocal,
          locale: locale,
          firstDayOfWeekIndex: firstDayOfWeekIndex,
        );
        if (parsed != null &&
            parsed.confidence >= _kAiTimeWindowParseMinConfidence) {
          timeStartMs = parsed.startLocal.toUtc().millisecondsSinceEpoch;
          timeEndMs = parsed.endLocal.toUtc().millisecondsSinceEpoch;
        }
      }
    }

    final hasTimeWindow = timeStartMs != null && timeEndMs != null;

    Stream<String> stream;
    switch (route) {
      case AskAiRouteKind.cloudGateway:
        if (allowCloudEmbeddings) {
          stream = hasTimeWindow
              ? backend.askAiStreamCloudGatewayWithEmbeddingsTimeWindow(
                  sessionKey,
                  widget.conversation.id,
                  question: question,
                  timeStartMs: timeStartMs,
                  timeEndMs: timeEndMs,
                  topK: topK,
                  thisThreadOnly: _thisThreadOnly,
                  gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                  idToken: cloudIdToken ?? '',
                  modelName: cloudGatewayConfig.modelName,
                  embeddingsModelName: _kCloudEmbeddingsModelName,
                )
              : backend.askAiStreamCloudGatewayWithEmbeddings(
                  sessionKey,
                  widget.conversation.id,
                  question: question,
                  topK: topK,
                  thisThreadOnly: _thisThreadOnly,
                  gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                  idToken: cloudIdToken ?? '',
                  modelName: cloudGatewayConfig.modelName,
                  embeddingsModelName: _kCloudEmbeddingsModelName,
                );
        } else {
          stream = hasTimeWindow
              ? backend.askAiStreamCloudGatewayTimeWindow(
                  sessionKey,
                  widget.conversation.id,
                  question: question,
                  timeStartMs: timeStartMs,
                  timeEndMs: timeEndMs,
                  topK: topK,
                  thisThreadOnly: _thisThreadOnly,
                  gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                  idToken: cloudIdToken ?? '',
                  modelName: cloudGatewayConfig.modelName,
                )
              : backend.askAiStreamCloudGateway(
                  sessionKey,
                  widget.conversation.id,
                  question: question,
                  topK: topK,
                  thisThreadOnly: _thisThreadOnly,
                  gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                  idToken: cloudIdToken ?? '',
                  modelName: cloudGatewayConfig.modelName,
                );
        }
        break;
      case AskAiRouteKind.byok:
      case AskAiRouteKind.needsSetup:
        stream = hasBrokEmbeddings
            ? (hasTimeWindow
                ? backend.askAiStreamWithBrokEmbeddingsTimeWindow(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    timeStartMs: timeStartMs,
                    timeEndMs: timeEndMs,
                    topK: topK,
                    thisThreadOnly: _thisThreadOnly,
                  )
                : backend.askAiStreamWithBrokEmbeddings(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    topK: topK,
                    thisThreadOnly: _thisThreadOnly,
                  ))
            : (hasTimeWindow
                ? backend.askAiStreamTimeWindow(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    timeStartMs: timeStartMs,
                    timeEndMs: timeEndMs,
                    topK: topK,
                    thisThreadOnly: _thisThreadOnly,
                  )
                : backend.askAiStream(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    topK: topK,
                    thisThreadOnly: _thisThreadOnly,
                  ));
        break;
    }

    Future<void> startStream(Stream<String> stream,
        {required bool fromCloud}) async {
      late final StreamSubscription<String> sub;
      var sawError = false;

      Future<void> handleStreamError(Object e) async {
        try {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          sawError = true;

          if (!fromCloud) {
            final message =
                '${context.t.chat.askAiFailedTemporary}\n\n${e.toString()}';
            _showAskAiFailure(question, message: message);
            return;
          }

          if (fromCloud && isCloudEmailNotVerifiedError(e)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: _kAskAiEmailNotVerifiedSnackKey,
                content: Text(context.t.chat.cloudGateway.emailNotVerified),
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: context.t.settings.cloudAccount.title,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const CloudAccountPage(),
                      ),
                    );
                  },
                ),
              ),
            );

            if (!mounted) return;
            if (!identical(_askSub, sub)) return;
            _showAskAiFailure(question);
            return;
          }

          final cloudStatus = fromCloud ? parseHttpStatusFromError(e) : null;

          bool hasByok;
          try {
            hasByok = await hasActiveLlmProfile(backend, sessionKey);
          } catch (_) {
            hasByok = false;
          }
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;

          if (fromCloud && hasByok && isCloudFallbackableError(e)) {
            final message = switch (cloudStatus) {
              401 => context.t.chat.cloudGateway.fallback.auth,
              402 => context.t.chat.cloudGateway.fallback.entitlement,
              429 => context.t.chat.cloudGateway.fallback.rateLimited,
              _ => context.t.chat.cloudGateway.fallback.generic,
            };

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: _kAskAiCloudFallbackSnackKey,
                content: Text(message),
                duration: const Duration(seconds: 3),
              ),
            );

            if (!mounted) return;
            if (!identical(_askSub, sub)) return;
            _setState(() {
              _askError = null;
              _streamingAnswer = '';
            });

            final hasBrokEmbeddings =
                await _hasActiveEmbeddingProfile(backend, sessionKey);
            if (!mounted) return;
            if (!identical(_askSub, sub)) return;

            final byokStream = hasBrokEmbeddings
                ? backend.askAiStreamWithBrokEmbeddings(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    topK: 10,
                    thisThreadOnly: _thisThreadOnly,
                  )
                : backend.askAiStream(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    topK: 10,
                    thisThreadOnly: _thisThreadOnly,
                  );
            await startStream(byokStream, fromCloud: false);
            return;
          }

          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          final message = fromCloud
              ? null
              : '${context.t.chat.askAiFailedTemporary}\n\n${e.toString()}';
          _showAskAiFailure(question, message: message);
        } catch (_) {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          final message = fromCloud
              ? null
              : '${context.t.chat.askAiFailedTemporary}\n\n${e.toString()}';
          _showAskAiFailure(question, message: message);
        }
      }

      sub = stream.listen(
        (delta) {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          if (delta.startsWith(_kAskAiErrorPrefix)) {
            sawError = true;
            final errText = delta.substring(_kAskAiErrorPrefix.length).trim();
            unawaited(handleStreamError(errText));
            return;
          }
          _setState(() => _streamingAnswer += delta);
        },
        onError: (e, st) {
          sawError = true;
          unawaited(
            () async {
              await handleStreamError(e);
            }(),
          );
        },
        onDone: () {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          if (sawError) {
            return;
          }
          if (_streamingAnswer.trim().isEmpty) {
            _showAskAiFailure(question);
            return;
          }
          _setState(() {
            _askSub = null;
            _asking = false;
            _pendingQuestion = null;
            _streamingAnswer = '';
          });
          _refresh();
          SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
        },
        cancelOnError: true,
      );

      if (!mounted) return;
      _setState(() => _askSub = sub);
    }

    await startStream(stream, fromCloud: route == AskAiRouteKind.cloudGateway);
  }

  Future<bool> _ensureAskAiDataConsent({bool allowPrompt = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final skip = prefs.getBool(_kAskAiDataConsentPrefsKey) ?? false;
    if (skip) return true;
    if (!allowPrompt) return false;
    if (!mounted) return false;

    var dontShowAgain = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = context.t;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              key: const ValueKey('ask_ai_consent_dialog'),
              scrollable: true,
              title: Text(t.chat.askAiConsent.title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.chat.askAiConsent.body),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const ValueKey('ask_ai_consent_dont_show_again'),
                    contentPadding: EdgeInsets.zero,
                    value: dontShowAgain,
                    onChanged: (value) {
                      setState(() => dontShowAgain = value ?? false);
                    },
                    title: Text(t.chat.askAiConsent.dontShowAgain),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.common.actions.cancel),
                ),
                FilledButton(
                  key: const ValueKey('ask_ai_consent_continue'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.common.actions.continueLabel),
                ),
              ],
            );
          },
        );
      },
    );

    if (approved != true) return false;
    if (dontShowAgain) {
      await prefs.setBool(_kAskAiDataConsentPrefsKey, true);
    }
    return true;
  }

  Future<bool> _ensureEmbeddingsDataConsent({bool forceDialog = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getBool(_kEmbeddingsDataConsentPrefsKey);
    if (existing == true) {
      _cloudEmbeddingsConsented = true;
      return true;
    }
    if (existing == false && !forceDialog) {
      _cloudEmbeddingsConsented = false;
      return false;
    }
    if (!mounted) return false;

    var dontShowAgain = true;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = context.t;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              key: const ValueKey('embeddings_consent_dialog'),
              scrollable: true,
              title: Text(t.chat.embeddingsConsent.title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.chat.embeddingsConsent.body),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const ValueKey('embeddings_consent_dont_show_again'),
                    contentPadding: EdgeInsets.zero,
                    value: dontShowAgain,
                    onChanged: (value) {
                      setState(() => dontShowAgain = value ?? true);
                    },
                    title: Text(t.chat.embeddingsConsent.dontShowAgain),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.chat.embeddingsConsent.actions.useLocal),
                ),
                FilledButton(
                  key: const ValueKey('embeddings_consent_continue'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.chat.embeddingsConsent.actions.enableCloud),
                ),
              ],
            );
          },
        );
      },
    );

    if (approved != true) {
      await EmbeddingsDataConsentPrefs.setEnabled(prefs, false);
      _cloudEmbeddingsConsented = false;
      return false;
    }

    _cloudEmbeddingsConsented = true;
    await EmbeddingsDataConsentPrefs.setEnabled(prefs, true);
    return true;
  }

  Future<bool> _hasActiveEmbeddingProfile(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    try {
      final profiles = await backend.listEmbeddingProfiles(sessionKey);
      return profiles.any((p) => p.isActive);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureAskAiConfigured(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    try {
      final hasActiveProfile = await hasActiveLlmProfile(backend, sessionKey);
      if (hasActiveProfile) return true;
    } catch (_) {
      return true;
    }
    if (!mounted) return false;

    final action = await showDialog<_AskAiSetupAction>(
      context: context,
      builder: (context) {
        final t = context.t;
        return AlertDialog(
          key: const ValueKey('ask_ai_setup_dialog'),
          title: Text(t.chat.askAiSetup.title),
          content: Text(t.chat.askAiSetup.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.common.actions.cancel),
            ),
            TextButton(
              key: const ValueKey('ask_ai_setup_subscribe'),
              onPressed: () =>
                  Navigator.of(context).pop(_AskAiSetupAction.subscribe),
              child: Text(t.chat.askAiSetup.actions.subscribe),
            ),
            FilledButton(
              key: const ValueKey('ask_ai_setup_configure_byok'),
              onPressed: () =>
                  Navigator.of(context).pop(_AskAiSetupAction.configureByok),
              child: Text(t.chat.askAiSetup.actions.configureByok),
            ),
          ],
        );
      },
    );

    if (!mounted) return false;

    switch (action) {
      case _AskAiSetupAction.configureByok:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
        );
        break;
      case _AskAiSetupAction.subscribe:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CloudAccountPage()),
        );
        break;
      case null:
        break;
    }

    return false;
  }
}
