part of 'chat_page.dart';

extension _ChatPageStateMethodsPAskAiMeta on _ChatPageState {
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

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    _activeCloudRequestId = requestId;
    if ((gatewayBaseUrl ?? '').trim().isNotEmpty) {
      _activeCloudGatewayBaseUrl = gatewayBaseUrl!.trim();
    }
    if ((idToken ?? '').trim().isNotEmpty) {
      _activeCloudIdToken = idToken!.trim();
    }

    await DetachedAskRecoveryService.persistSnapshot(
      requestId: requestId,
      question: question,
      conversationId: widget.conversation.id,
      gatewayBaseUrl: _activeCloudGatewayBaseUrl,
      state: DetachedAskSnapshotState.streamingConnected,
    );
    unawaited(
      DetachedAskRecoveryService.trackMetric(
        backend: backend,
        sessionKey: sessionKey,
        metric: DetachedAskRecoveryService.metricAskAiDetachedSnapshotPersisted,
        conversationId: widget.conversation.id,
        requestId: requestId,
        detail: 'request_id_attached',
      ),
    );
  }
}
