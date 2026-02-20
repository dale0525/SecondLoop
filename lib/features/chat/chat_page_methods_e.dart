part of 'chat_page.dart';

extension _ChatPageStateMethodsE on _ChatPageState {
  Future<void> _stopAsk() async {
    final sub = _askSub;
    if (!_asking || _stopRequested) return;

    final activeRequestId = _activeCloudRequestId;
    final activeGatewayBaseUrl = _activeCloudGatewayBaseUrl;
    final activeIdToken = _activeCloudIdToken;

    _setState(() {
      _stopRequested = true;
      _askSub = null;
      _asking = false;
      _pendingQuestion = null;
      _streamingAnswer = '';
      _askAttemptCreatedAtMs = null;
      _askAttemptAnchorMessageId = null;
      _activeCloudRequestId = null;
      _activeCloudGatewayBaseUrl = null;
      _activeCloudIdToken = null;
    });

    if (sub != null) {
      unawaited(sub.cancel());
    }

    if (activeRequestId != null &&
        activeGatewayBaseUrl != null &&
        activeIdToken != null) {
      unawaited(
        _cancelDetachedAskJob(
          gatewayBaseUrl: activeGatewayBaseUrl,
          idToken: activeIdToken,
          requestId: activeRequestId,
        ),
      );
      unawaited(
        _clearDetachedAskSnapshot(expectedRequestId: activeRequestId),
      );
    }

    if (!mounted) return;
    _setState(() => _stopRequested = false);
  }

  Future<void> _askAi({
    String? questionOverride,
    bool forceDisableTimeWindow = false,
  }) async {
    if (_asking) return;
    if (_sending) return;
    if (_recordingAudio) return;

    final question = (questionOverride ?? _controller.text).trim();
    if (question.isEmpty) return;

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

    AskAiRouteKind route;
    if (_composerAskAiRouteLoading) {
      route = await _resolveAskAiRouteWithPreference(
        backend,
        sessionKey,
        cloudIdToken: cloudIdToken,
        cloudGatewayConfig: cloudGatewayConfig,
        subscriptionStatus: subscriptionStatus,
      );

      if (mounted) {
        _setState(() {
          _composerAskAiRouteLoading = false;
          _composerAskAiRoute = route;
        });
      }
    } else {
      route = _composerAskAiRoute;
    }

    if (route == AskAiRouteKind.needsSetup) {
      await _openAskAiSettingsFromComposer();
      return;
    }

    final consented = await _ensureAskAiDataConsent();
    if (!consented) return;

    final allowCloudEmbeddings = route == AskAiRouteKind.cloudGateway &&
        await _ensureEmbeddingsDataConsent();
    final hasBrokEmbeddings = route == AskAiRouteKind.byok &&
        await _hasActiveEmbeddingProfile(backend, sessionKey);
    const topK = 10;
    final attemptAnchorMessageId = _latestCommittedMessageId();
    final attemptCreatedAtMs = DateTime.now().millisecondsSinceEpoch;

    _setState(() {
      _asking = true;
      _stopRequested = false;
      _askError = null;
      _askFailureMessage = null;
      _askFailureQuestion = null;
      _askFailureCreatedAtMs = null;
      _askFailureAnchorMessageId = null;
      _clearAskScopeEmptyState();
      _askAttemptCreatedAtMs = attemptCreatedAtMs;
      _askAttemptAnchorMessageId = attemptAnchorMessageId;
      _pendingQuestion = question;
      _streamingAnswer = '';
    });
    if (questionOverride == null) {
      _controller.clear();
    }

    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    final firstDayOfWeekIndex =
        MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final nowLocal = DateTime.now();
    final intent = forceDisableTimeWindow
        ? null
        : AskAiIntentResolver.resolve(
            question,
            nowLocal,
            locale: locale,
            firstDayOfWeekIndex: firstDayOfWeekIndex,
          );
    var timeStartMs =
        intent?.timeRange?.startLocal.toUtc().millisecondsSinceEpoch;
    var timeEndMs = intent?.timeRange?.endLocal.toUtc().millisecondsSinceEpoch;

    if (!forceDisableTimeWindow && (timeStartMs == null || timeEndMs == null)) {
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
    final canRetryCloudWithoutEmbeddings =
        route == AskAiRouteKind.cloudGateway &&
            allowCloudEmbeddings &&
            !hasTimeWindow;

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
                  topK: 0,
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

    final tagScopedStream = await _buildTagScopedAskStream(
      backend: backend,
      route: route,
      sessionKey: sessionKey,
      question: question,
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
      cloudGatewayConfig: cloudGatewayConfig,
      cloudIdToken: cloudIdToken,
    );
    if (tagScopedStream != null) {
      stream = tagScopedStream;
    }

    Future<void> startStream(
      Stream<String> stream, {
      required bool fromCloud,
      required bool canRetryWithoutEmbeddings,
      String? cloudGatewayBaseUrl,
      String? cloudIdTokenForStream,
    }) async {
      late final StreamSubscription<String> sub;
      var sawError = false;

      if (fromCloud) {
        _activeCloudRequestId = null;
        _activeCloudGatewayBaseUrl = cloudGatewayBaseUrl?.trim();
        _activeCloudIdToken = cloudIdTokenForStream?.trim();
      } else {
        _activeCloudRequestId = null;
        _activeCloudGatewayBaseUrl = null;
        _activeCloudIdToken = null;
      }

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
                    unawaited(
                      _pushRouteFromChat(
                        MaterialPageRoute(
                          builder: (context) => const CloudAccountPage(),
                        ),
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

          if (fromCloud &&
              canRetryWithoutEmbeddings &&
              cloudStatus == null &&
              _isCloudEmbeddingsPreflightFailure(e)) {
            _setState(() {
              _askError = null;
              _streamingAnswer = '';
            });
            final fallbackStream = backend.askAiStreamCloudGateway(
              sessionKey,
              widget.conversation.id,
              question: question,
              topK: 0,
              thisThreadOnly: _thisThreadOnly,
              gatewayBaseUrl: cloudGatewayConfig.baseUrl,
              idToken: cloudIdToken ?? '',
              modelName: cloudGatewayConfig.modelName,
            );
            await startStream(
              fallbackStream,
              fromCloud: true,
              canRetryWithoutEmbeddings: false,
              cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
              cloudIdTokenForStream: cloudIdToken,
            );
            return;
          }

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

            final staleRequestId = _activeCloudRequestId;
            _activeCloudRequestId = null;
            _activeCloudGatewayBaseUrl = null;
            _activeCloudIdToken = null;
            await _clearDetachedAskSnapshot(
              expectedRequestId: staleRequestId,
            );

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
            await startStream(
              byokStream,
              fromCloud: false,
              canRetryWithoutEmbeddings: false,
            );
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
          if (delta.startsWith(_kAskAiMetaPrefix)) {
            if (fromCloud) {
              unawaited(
                _handleCloudAskMetaDelta(
                  delta,
                  question: question,
                  gatewayBaseUrl: cloudGatewayBaseUrl,
                  idToken: cloudIdTokenForStream,
                ),
              );
            }
            return;
          }
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
          final completedRequestId = _activeCloudRequestId;
          final completedGatewayBaseUrl = _activeCloudGatewayBaseUrl;
          final completedIdToken = _activeCloudIdToken;
          final completedAnswer = _streamingAnswer;
          _setState(() {
            _askSub = null;
            _asking = false;
            _pendingQuestion = null;
            _streamingAnswer = '';
            _captureAskScopeEmptyState(
              question: question,
              answer: completedAnswer,
            );
            _askAttemptCreatedAtMs = null;
            _askAttemptAnchorMessageId = null;
            _activeCloudRequestId = null;
            _activeCloudGatewayBaseUrl = null;
            _activeCloudIdToken = null;
          });
          unawaited(
            _finalizeDetachedAskSnapshot(
              requestId: completedRequestId,
              gatewayBaseUrl: completedGatewayBaseUrl,
              idToken: completedIdToken,
            ),
          );
          _refresh();
          SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
        },
        cancelOnError: true,
      );

      if (!mounted) return;
      _setState(() => _askSub = sub);
    }

    await startStream(
      stream,
      fromCloud: route == AskAiRouteKind.cloudGateway,
      canRetryWithoutEmbeddings: canRetryCloudWithoutEmbeddings,
      cloudGatewayBaseUrl: route == AskAiRouteKind.cloudGateway
          ? cloudGatewayConfig.baseUrl
          : null,
      cloudIdTokenForStream:
          route == AskAiRouteKind.cloudGateway ? cloudIdToken : null,
    );
  }

  Future<bool> _ensureAskAiDataConsent({bool allowPrompt = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final skip = prefs.getBool(_kAskAiDataConsentPrefsKey) ?? false;
    if (skip) return true;
    if (!allowPrompt) return false;
    if (!mounted) return false;

    var dontShowAgain = false;
    final approved = await _showDialogFromChat<bool>(
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
    final approved = await _showDialogFromChat<bool>(
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

  Future<void> _handleCloudAskMetaDelta(
    String delta, {
    required String question,
    String? gatewayBaseUrl,
    String? idToken,
  }) async {
    if (!delta.startsWith(_kAskAiMetaPrefix)) return;
    final rawPayload = delta.substring(_kAskAiMetaPrefix.length).trim();
    if (rawPayload.isEmpty) return;

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) return;
      payload = decoded;
    } catch (_) {
      return;
    }

    if ((payload['type'] as String?)?.trim() != 'cloud_request_id') {
      return;
    }

    final requestId = (payload['request_id'] as String?)?.trim();
    if (requestId == null || requestId.isEmpty) return;

    _activeCloudRequestId = requestId;
    if ((gatewayBaseUrl ?? '').trim().isNotEmpty) {
      _activeCloudGatewayBaseUrl = gatewayBaseUrl!.trim();
    }
    if ((idToken ?? '').trim().isNotEmpty) {
      _activeCloudIdToken = idToken!.trim();
    }

    await _persistDetachedAskSnapshot(
      requestId: requestId,
      question: question,
      gatewayBaseUrl: _activeCloudGatewayBaseUrl,
    );
  }

  Future<void> _persistDetachedAskSnapshot({
    required String requestId,
    required String question,
    String? gatewayBaseUrl,
  }) async {
    if (requestId.trim().isEmpty) return;
    if (question.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final payload = <String, Object?>{
      'request_id': requestId.trim(),
      'question': question,
      'conversation_id': widget.conversation.id,
      'gateway_base_url': gatewayBaseUrl?.trim(),
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_kAskAiDetachedJobPrefsKey, jsonEncode(payload));
  }

  Future<void> _clearDetachedAskSnapshot({String? expectedRequestId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (expectedRequestId == null || expectedRequestId.trim().isEmpty) {
      await prefs.remove(_kAskAiDetachedJobPrefsKey);
      return;
    }

    final raw = prefs.getString(_kAskAiDetachedJobPrefsKey);
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_kAskAiDetachedJobPrefsKey);
        return;
      }
      final currentRequestId = (decoded['request_id'] as String?)?.trim();
      if (currentRequestId == expectedRequestId.trim()) {
        await prefs.remove(_kAskAiDetachedJobPrefsKey);
      }
    } catch (_) {
      await prefs.remove(_kAskAiDetachedJobPrefsKey);
    }
  }

  Future<void> _recoverDetachedAskAiIfNeeded() async {
    if (!mounted) return;
    if (_detachedAskRecoveryChecked) return;

    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    if (cloudAuthScope == null) {
      _detachedAskRecoveryChecked = false;
      return;
    }
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    _detachedAskRecoveryChecked = true;

    _detachedAskRecoveryTimer?.cancel();
    _detachedAskRecoveryTimer = null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAskAiDetachedJobPrefsKey);
    if (raw == null || raw.trim().isEmpty) return;

    Map<String, dynamic> snapshot;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_kAskAiDetachedJobPrefsKey);
        return;
      }
      snapshot = decoded;
    } catch (_) {
      await prefs.remove(_kAskAiDetachedJobPrefsKey);
      return;
    }

    int? parseInt(Object? value) {
      if (value is int) return value;
      if (value is double) return value.isFinite ? value.toInt() : null;
      if (value is String) return int.tryParse(value);
      return null;
    }

    final createdAtMs = parseInt(snapshot['created_at_ms']);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const snapshotMaxAgeMs = 26 * 60 * 60 * 1000;
    if (createdAtMs != null && nowMs - createdAtMs > snapshotMaxAgeMs) {
      await prefs.remove(_kAskAiDetachedJobPrefsKey);
      return;
    }

    final conversationId = (snapshot['conversation_id'] as String?)?.trim();
    if (conversationId != widget.conversation.id) {
      _detachedAskRecoveryChecked = false;
      return;
    }

    final requestId = (snapshot['request_id'] as String?)?.trim();
    if (requestId == null || requestId.isEmpty) {
      await prefs.remove(_kAskAiDetachedJobPrefsKey);
      return;
    }

    final question = (snapshot['question'] as String?)?.trim();
    if (question == null || question.isEmpty) {
      await prefs.remove(_kAskAiDetachedJobPrefsKey);
      return;
    }

    String? idToken;
    try {
      idToken = await cloudAuthScope.controller.getIdToken();
    } catch (_) {
      idToken = null;
    }
    if ((idToken ?? '').trim().isEmpty) {
      _detachedAskRecoveryChecked = false;
      return;
    }

    final snapshotBase = (snapshot['gateway_base_url'] as String?)?.trim();
    final gatewayBaseUrl = (snapshotBase?.isNotEmpty ?? false)
        ? snapshotBase!
        : cloudAuthScope.gatewayConfig.baseUrl.trim();
    if (gatewayBaseUrl.isEmpty) {
      _detachedAskRecoveryChecked = false;
      return;
    }

    final status = await _fetchDetachedAskJobStatus(
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken!,
      requestId: requestId,
    );
    if (status == null) {
      _detachedAskRecoveryChecked = false;
      return;
    }

    final state = (status['status'] as String?)?.trim().toLowerCase() ?? '';

    if (state == 'running' || state == 'cancel_requested') {
      final pollDelay = detachedAskRecoveryPollDelay(
        nowMs: nowMs,
        createdAtMs: createdAtMs,
      );

      _detachedAskRecoveryChecked = false;
      _detachedAskRecoveryTimer = Timer(pollDelay, () {
        if (!mounted) return;
        unawaited(_recoverDetachedAskAiIfNeeded());
      });
      return;
    }

    if (state == 'completed') {
      final resultText = (status['result_text'] as String?)?.trim() ?? '';
      if (resultText.isEmpty) {
        await prefs.remove(_kAskAiDetachedJobPrefsKey);
        return;
      }

      await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'user',
        content: question,
      );
      await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'assistant',
        content: resultText,
      );
      await _finalizeDetachedAskSnapshot(
        requestId: requestId,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
      );

      if (!mounted) return;
      _refresh();
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: _kAskAiDetachedRecoveredSnackKey,
          content: Text(context.t.chat.askAiRecoveredDetached),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    await prefs.remove(_kAskAiDetachedJobPrefsKey);
  }

  Future<Map<String, dynamic>?> _fetchDetachedAskJobStatus({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) async {
    final base = gatewayBaseUrl.trim();
    final token = idToken.trim();
    final rid = requestId.trim();
    if (base.isEmpty || token.isEmpty || rid.isEmpty) return null;

    final client = HttpClient();
    try {
      final uri = Uri.parse(base).resolve('/v1/chat/jobs/$rid');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final resp = await req.close().timeout(const Duration(seconds: 45));
      final text =
          await utf8.decodeStream(resp).timeout(const Duration(seconds: 45));
      if (resp.statusCode == 404) {
        return <String, dynamic>{'status': 'not_found'};
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _cancelDetachedAskJob({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) async {
    final base = gatewayBaseUrl.trim();
    final token = idToken.trim();
    final rid = requestId.trim();
    if (base.isEmpty || token.isEmpty || rid.isEmpty) return;

    final client = HttpClient();
    try {
      final uri = Uri.parse(base).resolve('/v1/chat/jobs/$rid/cancel');
      final req =
          await client.postUrl(uri).timeout(const Duration(seconds: 12));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode('{}'));
      final resp = await req.close().timeout(const Duration(seconds: 45));
      await utf8.decodeStream(resp).timeout(const Duration(seconds: 45));
    } catch (_) {
      return;
    } finally {
      client.close(force: true);
    }
  }
}
