import 'package:flutter/foundation.dart';

import '../../core/backend/knowledge_viewer_backend.dart';
import '../../src/rust/knowledge/models.dart';

final class KnowledgeDocumentController extends ChangeNotifier {
  KnowledgeDocumentController({
    required this.backend,
    required this.sessionKey,
    required this.documentId,
    required KnowledgeViewerDocument initialDocument,
    this.pageSize = 48,
  })  : _viewerDocument = initialDocument,
        _total = initialDocument.totalUnits.toInt();

  final KnowledgeViewerBackend backend;
  final Uint8List sessionKey;
  final int pageSize;

  String documentId;

  KnowledgeViewerDocument _viewerDocument;
  List<KnowledgeUnit> _units = const <KnowledgeUnit>[];
  List<KnowledgeSearchResult> _searchResults = const <KnowledgeSearchResult>[];
  bool _loadingPage = false;
  bool _loadingMore = false;
  int _loadEpoch = 0;
  bool _searching = false;
  bool _anchorMode = false;
  String? _highlightedUnitId;
  int _total;
  Object? _loadError;

  KnowledgeViewerDocument get viewerDocument => _viewerDocument;
  List<KnowledgeUnit> get units => _units;
  List<KnowledgeSearchResult> get searchResults => _searchResults;
  bool get loadingPage => _loadingPage;
  bool get loadingMore => _loadingMore;
  bool get searching => _searching;
  bool get anchorMode => _anchorMode;
  String? get highlightedUnitId => _highlightedUnitId;
  int get total => _total;
  Object? get loadError => _loadError;

  void reset({
    required String documentId,
    required KnowledgeViewerDocument initialDocument,
  }) {
    this.documentId = documentId;
    _viewerDocument = initialDocument;
    _total = initialDocument.totalUnits.toInt();
    _units = const <KnowledgeUnit>[];
    _searchResults = const <KnowledgeSearchResult>[];
    _loadingPage = false;
    _loadingMore = false;
    _searching = false;
    _anchorMode = false;
    _highlightedUnitId = null;
    _loadError = null;
    notifyListeners();
  }

  Future<void> loadPage({required bool reset}) async {
    final epoch = ++_loadEpoch;
    if (reset) {
      _loadingPage = true;
      _loadingMore = false;
      _loadError = null;
      notifyListeners();
    } else {
      if (_loadingPage ||
          _loadingMore ||
          _anchorMode ||
          _units.length >= _total) return;
      _loadingMore = true;
      _loadError = null;
      notifyListeners();
    }

    try {
      final page = await backend.listKnowledgeViewerUnits(
        sessionKey,
        documentId: documentId,
        limit: pageSize,
        offset: reset ? 0 : _units.length,
      );
      if (epoch != _loadEpoch) return;
      _viewerDocument = KnowledgeViewerDocument(
        document: _viewerDocument.document,
        totalUnits: page.total,
        sectionCount: _viewerDocument.sectionCount,
        chunkCount: _viewerDocument.chunkCount,
      );
      _total = page.total.toInt();
      _anchorMode = false;
      _units = reset ? page.units : _mergeUnits(_units, page.units);
    } catch (error) {
      if (epoch != _loadEpoch) return;
      _loadError = error;
    } finally {
      if (epoch == _loadEpoch) {
        _loadingPage = false;
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> clearSearchAndReload() async {
    _searchResults = const <KnowledgeSearchResult>[];
    _highlightedUnitId = null;
    notifyListeners();
    await loadPage(reset: true);
  }

  Future<void> searchDocument(String query) async {
    _searching = true;
    notifyListeners();
    try {
      final results = await backend.searchKnowledgeDocumentUnits(
        sessionKey,
        documentId: documentId,
        query: query,
        limit: 8,
      );
      _searchResults = results;
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  Future<void> jumpToResult(KnowledgeSearchResult result) async {
    final targetUnitId = result.unitId;
    if (targetUnitId != null &&
        _units.any((unit) => unit.unitId == targetUnitId)) {
      _highlightedUnitId = targetUnitId;
      notifyListeners();
      return;
    }

    final epoch = ++_loadEpoch;
    _loadingPage = true;
    _loadingMore = false;
    _loadError = null;
    notifyListeners();
    try {
      final units = await backend.listKnowledgeUnitsAroundAnchor(
        sessionKey,
        documentId: documentId,
        anchor: result.anchors,
        before: 2,
        after: 3,
      );
      if (epoch != _loadEpoch) return;
      final highlighted =
          targetUnitId ?? (units.isEmpty ? null : units.first.unitId);
      _anchorMode = true;
      _units = units;
      _highlightedUnitId = highlighted;
    } catch (error) {
      if (epoch != _loadEpoch) return;
      _loadError = error;
    } finally {
      if (epoch == _loadEpoch) {
        _loadingPage = false;
        notifyListeners();
      }
    }
  }

  static List<KnowledgeUnit> _mergeUnits(
    List<KnowledgeUnit> current,
    List<KnowledgeUnit> next,
  ) {
    final merged = <KnowledgeUnit>[];
    final seen = <String>{};
    for (final unit in [...current, ...next]) {
      if (!seen.add(unit.unitId)) continue;
      merged.add(unit);
    }
    return merged;
  }
}
