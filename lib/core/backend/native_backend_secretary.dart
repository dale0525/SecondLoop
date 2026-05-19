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

Future<PlanningOutputRecord> _dartDbUpsertPlanningOutput({
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
}) async {
  final store = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(store, key);
  final record = PlanningOutputRecord(
    id: id,
    kind: kind,
    title: title,
    body: body,
    itemsJson: itemsJson,
    sourceRefsJson: sourceRefsJson,
    route: route,
    state: state,
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs,
    expiresAtMs: expiresAtMs,
  );
  store.planningOutputs[id] = record;
  return record;
}

Future<List<PlanningOutputRecord>> _dartDbListPlanningOutputs({
  required String appDir,
  required List<int> key,
  String? kind,
  required PlatformInt64 nowMs,
  required bool includeExpired,
}) async {
  final store = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(store, key);
  final now = nowMs;
  final records = store.planningOutputs.values.where((record) {
    if (kind != null && record.kind != kind) return false;
    if (includeExpired) return true;
    final expiresAt = record.expiresAtMs;
    return expiresAt == null || expiresAt > now;
  }).toList(growable: false);
  records.sort((left, right) {
    final byUpdated = right.updatedAtMs.compareTo(left.updatedAtMs);
    return byUpdated != 0 ? byUpdated : left.id.compareTo(right.id);
  });
  return records;
}

Future<SecretaryRunRecord> _dartDbCreateSecretaryRun({
  required String appDir,
  required List<int> key,
  required String triggerKind,
  required String route,
  required String status,
  String? inputSummary,
  String? outputSummary,
  String? error,
  required PlatformInt64 nowMs,
}) async {
  final store = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(store, key);
  final record = SecretaryRunRecord(
    id: 'secretary_run_${store.nextSecretaryRunSeq++}',
    triggerKind: triggerKind,
    route: route,
    status: status,
    inputSummary: inputSummary,
    outputSummary: outputSummary,
    error: error,
    createdAtMs: nowMs,
    updatedAtMs: nowMs,
  );
  store.secretaryRuns[record.id] = record;
  return record;
}

Future<SecretaryToolCallRecord> _dartDbCreateSecretaryToolCall({
  required String appDir,
  required List<int> key,
  required String runId,
  required String toolName,
  required String status,
  required bool requiresConfirmation,
  String? inputJson,
  String? outputJson,
  required PlatformInt64 nowMs,
}) async {
  final store = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(store, key);
  if (!store.secretaryRuns.containsKey(runId)) {
    throw StateError('secretary_run_not_found:$runId');
  }
  final record = SecretaryToolCallRecord(
    id: 'secretary_tool_call_${store.nextSecretaryToolCallSeq++}',
    runId: runId,
    toolName: toolName,
    status: status,
    requiresConfirmation: requiresConfirmation,
    inputJson: inputJson,
    outputJson: outputJson,
    createdAtMs: nowMs,
    updatedAtMs: nowMs,
  );
  store.secretaryToolCalls[record.id] = record;
  return record;
}

Future<List<SecretaryToolCallRecord>> _dartDbListSecretaryToolCallsForRun({
  required String appDir,
  required List<int> key,
  required String runId,
}) async {
  final store = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(store, key);
  final records = store.secretaryToolCalls.values
      .where((record) => record.runId == runId)
      .toList(growable: false);
  records.sort((left, right) {
    final byCreated = left.createdAtMs.compareTo(right.createdAtMs);
    return byCreated != 0 ? byCreated : left.id.compareTo(right.id);
  });
  return records;
}

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
    final dbCreate = _dbCreateSecretaryMemoryProposal;
    if (dbCreate != null) {
      final appDir = await _getAppDir();
      return dbCreate(
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
    return _dartCreateSecretaryMemoryProposal(
      key,
      sourceMessageId: sourceMessageId,
      kind: kind,
      title: title,
      body: body,
      confidence: confidence,
      sourceRefsJson: sourceRefsJson,
      actionHint: actionHint,
      nowMs: nowMs,
    );
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    final dbList = _dbListSecretaryMemoryProposals;
    if (dbList != null) {
      final appDir = await _getAppDir();
      return dbList(
        appDir: appDir,
        key: key,
        state: state,
      );
    }
    return _dartListSecretaryMemoryProposals(key, state: state);
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    final dbAccept = _dbAcceptSecretaryMemoryProposal;
    if (dbAccept != null) {
      final appDir = await _getAppDir();
      return dbAccept(
        appDir: appDir,
        key: key,
        proposalId: proposalId,
        nowMs: PlatformInt64Util.from(nowMs),
      );
    }
    return _dartAcceptSecretaryMemoryProposal(
      key,
      proposalId: proposalId,
      nowMs: nowMs,
    );
  }

  @override
  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    final dbDismiss = _dbDismissSecretaryMemoryProposal;
    if (dbDismiss != null) {
      final appDir = await _getAppDir();
      return dbDismiss(
        appDir: appDir,
        key: key,
        proposalId: proposalId,
        nowMs: PlatformInt64Util.from(nowMs),
      );
    }
    return _dartDismissSecretaryMemoryProposal(
      key,
      proposalId: proposalId,
      nowMs: nowMs,
    );
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    final dbList = _dbListMemoryPages;
    if (dbList != null) {
      final appDir = await _getAppDir();
      return dbList(appDir: appDir, key: key, state: state);
    }
    return _dartListMemoryPages(key, state: state);
  }

  @override
  Future<MemoryPageRecord> getMemoryPage(
    Uint8List key, {
    required String pageId,
  }) async {
    final dbGet = _dbGetMemoryPage;
    if (dbGet != null) {
      final appDir = await _getAppDir();
      return dbGet(appDir: appDir, key: key, pageId: pageId);
    }
    return _dartGetMemoryPage(key, pageId: pageId);
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
    final dbCorrect = _dbCorrectMemoryPage;
    if (dbCorrect != null) {
      final appDir = await _getAppDir();
      return dbCorrect(
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
    return _dartCorrectMemoryPage(
      key,
      pageId: pageId,
      title: title,
      summary: summary,
      body: body,
      nowMs: nowMs,
    );
  }

  @override
  Future<MemoryPageRecord> archiveMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    final dbArchive = _dbArchiveMemoryPage;
    if (dbArchive != null) {
      final appDir = await _getAppDir();
      return dbArchive(
        appDir: appDir,
        key: key,
        pageId: pageId,
        nowMs: PlatformInt64Util.from(nowMs),
      );
    }
    return _dartSetMemoryPageState(
      key,
      pageId: pageId,
      state: 'archived',
      nowMs: nowMs,
    );
  }

  @override
  Future<MemoryPageRecord> restoreMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    final dbRestore = _dbRestoreMemoryPage;
    if (dbRestore != null) {
      final appDir = await _getAppDir();
      return dbRestore(
        appDir: appDir,
        key: key,
        pageId: pageId,
        nowMs: PlatformInt64Util.from(nowMs),
      );
    }
    return _dartSetMemoryPageState(
      key,
      pageId: pageId,
      state: 'active',
      nowMs: nowMs,
    );
  }

  Future<SecretaryMemoryProposalRecord> _dartCreateSecretaryMemoryProposal(
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
    final store = await _readDartSecretaryMemoryStore(key);
    final proposalId = 'proposal-${store.nextProposalSeq}';
    final proposal = SecretaryMemoryProposalRecord(
      id: proposalId,
      sourceMessageId: sourceMessageId,
      kind: kind,
      title: title,
      body: body,
      confidence: confidence,
      state: 'pending',
      sourceRefsJson: sourceRefsJson,
      actionHint: actionHint,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    await _writeDartSecretaryMemoryStore(
      key,
      store.copyWith(
        nextProposalSeq: store.nextProposalSeq + 1,
        proposals: <String, SecretaryMemoryProposalRecord>{
          ...store.proposals,
          proposalId: proposal,
        },
      ),
    );
    return proposal;
  }

  Future<List<SecretaryMemoryProposalRecord>> _dartListSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    final store = await _readDartSecretaryMemoryStore(key);
    final records = store.proposals.values
        .where((proposal) => state == null || proposal.state == state)
        .toList(growable: false);
    records.sort(
      (left, right) => comparePlatformInt(left.createdAtMs, right.createdAtMs),
    );
    return records;
  }

  Future<MemoryPageRecord> _dartAcceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    final store = await _readDartSecretaryMemoryStore(key);
    final proposal = store.proposals[proposalId];
    if (proposal == null) {
      throw StateError('Missing memory proposal $proposalId');
    }
    final sourceDocumentIdsJson =
        _sourceDocumentIdsJson(proposal.sourceMessageId);
    final existingPage = proposal.sourceMessageId == null
        ? null
        : store.pages.values.cast<MemoryPageRecord?>().firstWhere(
              (page) => page?.sourceDocumentIdsJson == sourceDocumentIdsJson,
              orElse: () => null,
            );
    if (existingPage != null) {
      await _writeDartSecretaryMemoryStore(
        key,
        store.copyWith(
          proposals: <String, SecretaryMemoryProposalRecord>{
            ...store.proposals,
            proposalId: _copyProposal(
              proposal,
              state: 'accepted',
              updatedAtMs: nowMs,
              acceptedAtMs: nowMs,
            ),
          },
        ),
      );
      return existingPage;
    }

    final pageId = 'memory-${store.nextPageSeq}';
    final page = MemoryPageRecord(
      pageId: pageId,
      pageType: 'memory',
      state: 'active',
      sourceCount: platformIntFromInt(proposal.sourceMessageId == null ? 0 : 1),
      title: proposal.title,
      summary: proposal.body,
      body: proposal.body,
      primaryEvidenceJson: proposal.sourceRefsJson ?? '[]',
      sourceDocumentIdsJson: sourceDocumentIdsJson,
      confidenceLevel: proposal.confidence,
      humanCorrected: false,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    await _writeDartSecretaryMemoryStore(
      key,
      store.copyWith(
        nextPageSeq: store.nextPageSeq + 1,
        proposals: <String, SecretaryMemoryProposalRecord>{
          ...store.proposals,
          proposalId: _copyProposal(
            proposal,
            state: 'accepted',
            updatedAtMs: nowMs,
            acceptedAtMs: nowMs,
          ),
        },
        pages: <String, MemoryPageRecord>{...store.pages, pageId: page},
      ),
    );
    return page;
  }

  Future<SecretaryMemoryProposalRecord> _dartDismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    final store = await _readDartSecretaryMemoryStore(key);
    final proposal = store.proposals[proposalId];
    if (proposal == null) {
      throw StateError('Missing memory proposal $proposalId');
    }
    final dismissed = _copyProposal(
      proposal,
      state: 'dismissed',
      updatedAtMs: nowMs,
      dismissedAtMs: nowMs,
    );
    await _writeDartSecretaryMemoryStore(
      key,
      store.copyWith(
        proposals: <String, SecretaryMemoryProposalRecord>{
          ...store.proposals,
          proposalId: dismissed,
        },
      ),
    );
    return dismissed;
  }

  Future<List<MemoryPageRecord>> _dartListMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    final store = await _readDartSecretaryMemoryStore(key);
    final pages = store.pages.values
        .where((page) => state == null || page.state == state)
        .toList(growable: false);
    pages.sort(
      (left, right) => comparePlatformInt(left.createdAtMs, right.createdAtMs),
    );
    return pages;
  }

  Future<MemoryPageRecord> _dartGetMemoryPage(
    Uint8List key, {
    required String pageId,
  }) async {
    final store = await _readDartSecretaryMemoryStore(key);
    final page = store.pages[pageId];
    if (page == null) throw StateError('Missing memory page $pageId');
    return page;
  }

  Future<MemoryPageRecord> _dartCorrectMemoryPage(
    Uint8List key, {
    required String pageId,
    required String title,
    required String summary,
    required String body,
    required int nowMs,
  }) async {
    final store = await _readDartSecretaryMemoryStore(key);
    final page = store.pages[pageId];
    if (page == null) throw StateError('Missing memory page $pageId');
    final corrected = _copyPage(
      page,
      title: title,
      summary: summary,
      body: body,
      humanCorrected: true,
      updatedAtMs: nowMs,
    );
    await _writeDartSecretaryMemoryStore(
      key,
      store.copyWith(
        pages: <String, MemoryPageRecord>{
          ...store.pages,
          pageId: corrected,
        },
      ),
    );
    return corrected;
  }

  Future<MemoryPageRecord> _dartSetMemoryPageState(
    Uint8List key, {
    required String pageId,
    required String state,
    required int nowMs,
  }) async {
    final store = await _readDartSecretaryMemoryStore(key);
    final page = store.pages[pageId];
    if (page == null) throw StateError('Missing memory page $pageId');
    final updated = _copyPage(
      page,
      state: state,
      updatedAtMs: nowMs,
    );
    await _writeDartSecretaryMemoryStore(
      key,
      store.copyWith(
        pages: <String, MemoryPageRecord>{...store.pages, pageId: updated},
      ),
    );
    return updated;
  }

  Future<_DartSecretaryMemoryStore> _readDartSecretaryMemoryStore(
    Uint8List key,
  ) async {
    final raw = await _secureBlobStore.readValue(
      _dartSecretaryMemoryStoreKey(key),
    );
    return _DartSecretaryMemoryStore.fromJsonString(raw);
  }

  Future<void> _writeDartSecretaryMemoryStore(
    Uint8List key,
    _DartSecretaryMemoryStore store,
  ) {
    return _secureBlobStore.update({
      _dartSecretaryMemoryStoreKey(key): store.toJsonString(),
    });
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
