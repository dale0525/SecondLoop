import 'dart:typed_data';

import 'app_backend.dart';
import 'knowledge_index_models.dart';
import 'native_backend.dart';
import '../../src/rust/knowledge/history.dart' as rust_knowledge_history;
import '../../src/rust/knowledge/pages.dart' as rust_knowledge_pages;

abstract interface class KnowledgeBackend {
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key);

  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key);

  Future<void> requestKnowledgeRebuild(Uint8List key);

  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  });

  Future<void> cancelKnowledgeRebuild(Uint8List key);

  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  });

  Future<KnowledgeMemoryFeedback> upsertKnowledgeMemoryFeedback(
    Uint8List key, {
    required String documentId,
    KnowledgeMemoryStatus? status,
    required bool useForAskAi,
    required bool isDeleted,
    required bool markedInaccurate,
    String? correctedTitle,
    String? correctedSummary,
  });

  Future<List<KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  });
}

abstract interface class GeneratedMemoryKnowledgeBackend {
  Future<List<ContentKnowledgeDocument>> listGeneratedMemoryDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  });
}

abstract interface class KnowledgePagesBackend {
  Future<List<rust_knowledge_pages.KnowledgePageSummary>>
      listKnowledgePageSummaries(Uint8List key);

  Future<List<rust_knowledge_history.KnowledgePageChangeRecord>>
      listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  });

  Future<rust_knowledge_pages.KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  });

  Future<rust_knowledge_pages.KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  });

  Future<rust_knowledge_pages.KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required rust_knowledge_pages.KnowledgeWrongReason reason,
    String? note,
  });

  Future<rust_knowledge_pages.KnowledgePageDetail>
      setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  });

  Future<rust_knowledge_pages.KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  });

  Future<rust_knowledge_pages.KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  });

  Future<rust_knowledge_pages.KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  });
}

KnowledgeBackend? maybeKnowledgeBackendFor(AppBackend backend) {
  if (backend is KnowledgeBackend) return backend as KnowledgeBackend;
  if (backend is NativeAppBackend) return NativeKnowledgeBackend(backend);
  return null;
}

final class NativeKnowledgeBackend
    implements
        KnowledgeBackend,
        GeneratedMemoryKnowledgeBackend,
        KnowledgePagesBackend {
  NativeKnowledgeBackend(this._backend);

  final NativeAppBackend _backend;

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) =>
      _backend.getKnowledgeIndexStatus(key);

  @override
  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key) =>
      _backend.getKnowledgeDebugStats(key);

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) =>
      _backend.requestKnowledgeRebuild(key);

  @override
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) =>
      _backend.processPendingKnowledgeIndexJobs(key, limit: limit);

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) =>
      _backend.cancelKnowledgeRebuild(key);

  @override
  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) =>
      _backend.listKnowledgeDocuments(key, limit: limit, offset: offset);

  @override
  Future<List<rust_knowledge_pages.KnowledgePageSummary>>
      listKnowledgePageSummaries(Uint8List key) =>
          _backend.listKnowledgePageSummaries(key);

  @override
  Future<List<rust_knowledge_history.KnowledgePageChangeRecord>>
      listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) =>
          _backend.listRecentKnowledgePageChanges(
            key,
            limit: limit,
          );

  @override
  Future<rust_knowledge_pages.KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) =>
      _backend.getKnowledgePageDetail(key, pageId: pageId);

  @override
  Future<rust_knowledge_pages.KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) =>
      _backend.correctKnowledgePage(
        key,
        pageId: pageId,
        title: title,
        summary: summary,
        body: body,
      );

  @override
  Future<rust_knowledge_pages.KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required rust_knowledge_pages.KnowledgeWrongReason reason,
    String? note,
  }) =>
      _backend.markKnowledgePageWrong(
        key,
        pageId: pageId,
        reason: reason,
        note: note,
      );

  @override
  Future<rust_knowledge_pages.KnowledgePageDetail>
      setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) =>
          _backend.setKnowledgePageAnswerAllowed(
            key,
            pageId: pageId,
            allowed: allowed,
            note: note,
          );

  @override
  Future<rust_knowledge_pages.KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) =>
      _backend.archiveKnowledgePage(
        key,
        pageId: pageId,
        note: note,
      );

  @override
  Future<rust_knowledge_pages.KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) =>
      _backend.removeKnowledgePage(
        key,
        pageId: pageId,
        note: note,
      );

  @override
  Future<rust_knowledge_pages.KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) =>
      _backend.mergeKnowledgePageInto(
        key,
        pageId: pageId,
        targetPageId: targetPageId,
        note: note,
      );

  @override
  Future<List<ContentKnowledgeDocument>> listGeneratedMemoryDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) =>
      _backend.listGeneratedMemoryDocuments(
        key,
        limit: limit,
        offset: offset,
      );

  @override
  Future<KnowledgeMemoryFeedback> upsertKnowledgeMemoryFeedback(
    Uint8List key, {
    required String documentId,
    KnowledgeMemoryStatus? status,
    required bool useForAskAi,
    required bool isDeleted,
    required bool markedInaccurate,
    String? correctedTitle,
    String? correctedSummary,
  }) =>
      _backend.upsertKnowledgeMemoryFeedback(
        key,
        documentId: documentId,
        status: status,
        useForAskAi: useForAskAi,
        isDeleted: isDeleted,
        markedInaccurate: markedInaccurate,
        correctedTitle: correctedTitle,
        correctedSummary: correctedSummary,
      );

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) =>
      _backend.listKnowledgeUnits(
        key,
        documentId: documentId,
        unitKind: unitKind,
        limit: limit,
        offset: offset,
      );
}

KnowledgePagesBackend? maybeKnowledgePagesBackendFor(AppBackend backend) {
  if (backend is KnowledgePagesBackend) {
    return backend as KnowledgePagesBackend;
  }
  if (backend is NativeAppBackend) {
    return NativeKnowledgeBackend(backend);
  }
  return null;
}
