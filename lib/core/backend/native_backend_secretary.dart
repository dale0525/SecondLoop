part of 'native_backend.dart';

typedef DbCreateSecretaryMemoryProposalFn
    = Future<SecretaryMemoryProposalRecord> Function({
  required String appDir,
  required List<int> key,
  String? sourceMessageId,
  required String kind,
  required String title,
  required String body,
  required double confidence,
  String? sourceRefsJson,
  String? actionHint,
  required PlatformInt64 nowMs,
});

typedef DbListSecretaryMemoryProposalsFn
    = Future<List<SecretaryMemoryProposalRecord>> Function({
  required String appDir,
  required List<int> key,
  String? state,
});

typedef DbAcceptSecretaryMemoryProposalFn = Future<MemoryPageRecord> Function({
  required String appDir,
  required List<int> key,
  required String proposalId,
  required PlatformInt64 nowMs,
});

typedef DbDismissSecretaryMemoryProposalFn
    = Future<SecretaryMemoryProposalRecord> Function({
  required String appDir,
  required List<int> key,
  required String proposalId,
  required PlatformInt64 nowMs,
});

typedef DbListMemoryPagesFn = Future<List<MemoryPageRecord>> Function({
  required String appDir,
  required List<int> key,
  String? state,
});

typedef DbGetMemoryPageFn = Future<MemoryPageRecord> Function({
  required String appDir,
  required List<int> key,
  required String pageId,
});

typedef DbCorrectMemoryPageFn = Future<MemoryPageRecord> Function({
  required String appDir,
  required List<int> key,
  required String pageId,
  required String title,
  required String summary,
  required String body,
  String? reason,
  required PlatformInt64 nowMs,
});

typedef DbSetMemoryPageStateFn = Future<MemoryPageRecord> Function({
  required String appDir,
  required List<int> key,
  required String pageId,
  required PlatformInt64 nowMs,
});

typedef DbUpsertPlanningOutputFn = Future<PlanningOutputRecord> Function({
  required String appDir,
  required List<int> key,
  required String id,
  required String kind,
  required String title,
  required String body,
  required String itemsJson,
  String? sourceRefsJson,
  required String route,
  required String state,
  required PlatformInt64 createdAtMs,
  required PlatformInt64 updatedAtMs,
  PlatformInt64? expiresAtMs,
});

typedef DbListPlanningOutputsFn = Future<List<PlanningOutputRecord>> Function({
  required String appDir,
  required List<int> key,
  String? kind,
  required PlatformInt64 nowMs,
  required bool includeExpired,
});

typedef DbCreateSecretaryRunFn = Future<SecretaryRunRecord> Function({
  required String appDir,
  required List<int> key,
  required String triggerKind,
  required String route,
  required String status,
  String? inputSummary,
  String? outputSummary,
  String? error,
  required PlatformInt64 nowMs,
});

typedef DbCreateSecretaryToolCallFn = Future<SecretaryToolCallRecord> Function({
  required String appDir,
  required List<int> key,
  required String runId,
  required String toolName,
  required String status,
  required bool requiresConfirmation,
  String? inputJson,
  String? outputJson,
  required PlatformInt64 nowMs,
});

typedef DbListSecretaryToolCallsForRunFn = Future<List<SecretaryToolCallRecord>>
    Function({
  required String appDir,
  required List<int> key,
  required String runId,
});

mixin _NativeAppBackendSecretary on _NativeAppBackendAccess {
  @override
  Future<SecretaryMemoryProposalRecord> createSecretaryMemoryProposal(
    Uint8List key, {
    String? sourceMessageId,
    required String kind,
    required String title,
    required String body,
    required double confidence,
    String? sourceRefsJson,
    String? actionHint,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbCreateSecretaryMemoryProposal(
      appDir: appDir,
      key: key,
      sourceMessageId: sourceMessageId,
      kind: kind,
      title: title,
      body: body,
      confidence: confidence,
      sourceRefsJson: sourceRefsJson,
      actionHint: actionHint,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    final appDir = await _getAppDir();
    return _dbListSecretaryMemoryProposals(
      appDir: appDir,
      key: key,
      state: state,
    );
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbAcceptSecretaryMemoryProposal(
      appDir: appDir,
      key: key,
      proposalId: proposalId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbDismissSecretaryMemoryProposal(
      appDir: appDir,
      key: key,
      proposalId: proposalId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    final appDir = await _getAppDir();
    return _dbListMemoryPages(appDir: appDir, key: key, state: state);
  }

  @override
  Future<MemoryPageRecord> getMemoryPage(
    Uint8List key, {
    required String pageId,
  }) async {
    final appDir = await _getAppDir();
    return _dbGetMemoryPage(appDir: appDir, key: key, pageId: pageId);
  }

  @override
  Future<MemoryPageRecord> correctMemoryPage(
    Uint8List key, {
    required String pageId,
    required String title,
    required String summary,
    required String body,
    String? reason,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbCorrectMemoryPage(
      appDir: appDir,
      key: key,
      pageId: pageId,
      title: title,
      summary: summary,
      body: body,
      reason: reason,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<MemoryPageRecord> archiveMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbArchiveMemoryPage(
      appDir: appDir,
      key: key,
      pageId: pageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<MemoryPageRecord> restoreMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbRestoreMemoryPage(
      appDir: appDir,
      key: key,
      pageId: pageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<PlanningOutputRecord> upsertPlanningOutput(
    Uint8List key, {
    required String id,
    required String kind,
    required String title,
    required String body,
    required String itemsJson,
    String? sourceRefsJson,
    required String route,
    required String state,
    required int createdAtMs,
    required int updatedAtMs,
    int? expiresAtMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbUpsertPlanningOutput(
      appDir: appDir,
      key: key,
      id: id,
      kind: kind,
      title: title,
      body: body,
      itemsJson: itemsJson,
      sourceRefsJson: sourceRefsJson,
      route: route,
      state: state,
      createdAtMs: PlatformInt64Util.from(createdAtMs),
      updatedAtMs: PlatformInt64Util.from(updatedAtMs),
      expiresAtMs:
          expiresAtMs == null ? null : PlatformInt64Util.from(expiresAtMs),
    );
  }

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async {
    final appDir = await _getAppDir();
    return _dbListPlanningOutputs(
      appDir: appDir,
      key: key,
      kind: kind,
      nowMs: PlatformInt64Util.from(nowMs),
      includeExpired: includeExpired,
    );
  }

  @override
  Future<SecretaryRunRecord> createSecretaryRun(
    Uint8List key, {
    required String triggerKind,
    required String route,
    required String status,
    String? inputSummary,
    String? outputSummary,
    String? error,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbCreateSecretaryRun(
      appDir: appDir,
      key: key,
      triggerKind: triggerKind,
      route: route,
      status: status,
      inputSummary: inputSummary,
      outputSummary: outputSummary,
      error: error,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<SecretaryToolCallRecord> createSecretaryToolCall(
    Uint8List key, {
    required String runId,
    required String toolName,
    required String status,
    required bool requiresConfirmation,
    String? inputJson,
    String? outputJson,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return _dbCreateSecretaryToolCall(
      appDir: appDir,
      key: key,
      runId: runId,
      toolName: toolName,
      status: status,
      requiresConfirmation: requiresConfirmation,
      inputJson: inputJson,
      outputJson: outputJson,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<List<SecretaryToolCallRecord>> listSecretaryToolCallsForRun(
    Uint8List key, {
    required String runId,
  }) async {
    final appDir = await _getAppDir();
    return _dbListSecretaryToolCallsForRun(
      appDir: appDir,
      key: key,
      runId: runId,
    );
  }
}
