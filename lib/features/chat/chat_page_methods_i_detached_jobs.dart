part of 'chat_page.dart';

extension _ChatPageStateMethodsIDetachedJobs on _ChatPageState {
  Uri? _buildCloudDetachedAckUri(String gatewayBaseUrl, String requestId) {
    final base = gatewayBaseUrl.trim();
    final normalizedRequestId = requestId.trim();
    if (base.isEmpty || normalizedRequestId.isEmpty) return null;

    final normalizedBase = base.replaceFirst(RegExp(r'/+$'), '');
    try {
      return Uri.parse('$normalizedBase/v1/chat/jobs/$normalizedRequestId/ack');
    } catch (_) {
      return null;
    }
  }

  Future<void> _ackCloudDetachedChatJob({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) async {
    if (!_kCloudDetachedRequestIdPattern.hasMatch(requestId.trim())) {
      return;
    }

    final uri = _buildCloudDetachedAckUri(gatewayBaseUrl, requestId);
    if (uri == null) return;

    final token = idToken.trim();
    if (token.isEmpty) return;

    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
    ];

    for (final delay in retryDelays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      try {
        final req =
            await client.postUrl(uri).timeout(const Duration(seconds: 6));
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final resp = await req.close().timeout(const Duration(seconds: 6));
        await resp.drain<void>().timeout(const Duration(seconds: 6));

        if ((resp.statusCode >= 200 && resp.statusCode < 300) ||
            resp.statusCode == 404) {
          return;
        }
        if (resp.statusCode != 409) {
          return;
        }
      } catch (_) {
        // Best-effort only.
      } finally {
        client.close(force: true);
      }
    }
  }

  Future<void> _finalizeDetachedAskSnapshot({
    required String? requestId,
    String? gatewayBaseUrl,
    String? idToken,
  }) async {
    final rid = requestId?.trim() ?? '';
    if (rid.isEmpty) return;

    final base = gatewayBaseUrl?.trim() ?? '';
    final token = idToken?.trim() ?? '';

    if (base.isNotEmpty && token.isNotEmpty) {
      await _ackCloudDetachedChatJob(
        gatewayBaseUrl: base,
        idToken: token,
        requestId: rid,
      );
    }

    await _clearDetachedAskSnapshot(expectedRequestId: rid);
  }
}
