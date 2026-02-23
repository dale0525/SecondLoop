part of 'chat_page.dart';

extension _ChatPageStateMethodsLAskScope on _ChatPageState {
  String _askScopeLocalDay(DateTime value) {
    final dt = value.toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isCloudEmbeddingsPreflightFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('embedding') ||
        message.contains('embedder') ||
        message.contains('query vector dim mismatch');
  }

  Future<Stream<String>?> _buildTagScopedAskStream({
    required AppBackend backend,
    required AskAiRouteKind route,
    required Uint8List sessionKey,
    required String question,
    required int? timeStartMs,
    required int? timeEndMs,
    required CloudGatewayConfig cloudGatewayConfig,
    required String? cloudIdToken,
  }) async {
    final hasTimeWindow = timeStartMs != null && timeEndMs != null;
    final hasScopedConstraints = hasTimeWindow ||
        _selectedTagFilterIds.isNotEmpty ||
        _selectedTagExcludeIds.isNotEmpty;
    if (!hasScopedConstraints) {
      return null;
    }
    if (kIsWeb) return null;
    if (backend is! NativeAppBackend) return null;

    final appDir = await getNativeAppDir();
    if (!mounted) return null;

    final includeTagIds = _selectedTagFilterIds.toList(growable: false);
    final excludeTagIds = _selectedTagExcludeIds.toList(growable: false);
    final localeLanguage = Localizations.localeOf(context).languageCode;

    if (route == AskAiRouteKind.cloudGateway) {
      return rust_ask_scope.ragAskAiStreamCloudGatewayScoped(
        appDir: appDir,
        key: sessionKey,
        conversationId: widget.conversation.id,
        question: question,
        topK: 10,
        thisThreadOnly: _thisThreadOnly,
        timeStartMs: timeStartMs,
        timeEndMs: timeEndMs,
        includeTagIds: includeTagIds,
        excludeTagIds: excludeTagIds,
        strictMode: true,
        localeLanguage: localeLanguage,
        gatewayBaseUrl: cloudGatewayConfig.baseUrl,
        firebaseIdToken: cloudIdToken ?? '',
        modelName: cloudGatewayConfig.modelName,
      );
    }

    return rust_ask_scope.ragAskAiStreamScoped(
      appDir: appDir,
      key: sessionKey,
      conversationId: widget.conversation.id,
      question: question,
      topK: 10,
      thisThreadOnly: _thisThreadOnly,
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
      includeTagIds: includeTagIds,
      excludeTagIds: excludeTagIds,
      strictMode: true,
      localeLanguage: localeLanguage,
      localDay: _askScopeLocalDay(DateTime.now()),
    );
  }
}
