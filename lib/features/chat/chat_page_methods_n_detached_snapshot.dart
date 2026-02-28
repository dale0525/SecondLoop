part of 'chat_page.dart';

extension _ChatPageStateMethodsNDetachedSnapshot on _ChatPageState {
  Future<void> _clearDetachedAskSnapshot({String? expectedRequestId}) async {
    final expected = expectedRequestId?.trim() ?? '';
    if (expected.isEmpty) {
      await DetachedAskRecoveryService.clearSnapshot();
      return;
    }
    await DetachedAskRecoveryService.clearSnapshot(expectedRequestId: expected);
  }

  Future<Map<String, dynamic>?> _fetchDetachedAskJobStatus({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) {
    return DetachedAskRecoveryService.fetchCloudDetachedJobStatus(
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      requestId: requestId,
    );
  }

  Future<void> _cancelDetachedAskJob({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) {
    return DetachedAskRecoveryService.cancelCloudDetachedJob(
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      requestId: requestId,
    );
  }
}
