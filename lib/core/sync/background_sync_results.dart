part of 'background_sync.dart';

Future<void> _writeBackgroundResult({
  required SyncConfigStore store,
  required SyncBackendType backendType,
  required String scopeId,
  required SyncBackgroundDirection direction,
  required _BackgroundSyncOpResult result,
  required int? retryCount,
}) async {
  final status = switch (result.status) {
    _BackgroundOpStatus.success => SyncBackgroundResultStatus.success,
    _BackgroundOpStatus.skipped => SyncBackgroundResultStatus.skipped,
    _BackgroundOpStatus.failure => SyncBackgroundResultStatus.failure,
  };
  await store.writeBackgroundSyncResult(
    SyncBackgroundResult(
      backendType: backendType,
      direction: direction,
      status: status,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      statusCode: result.statusCode,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
      userMessage: result.userMessage,
      retryCount: retryCount,
      durationMs: result.durationMs,
    ),
    backendType: backendType,
    scopeId: scopeId,
  );
}
