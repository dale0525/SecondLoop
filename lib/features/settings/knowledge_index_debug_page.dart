import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_backend.dart';
import '../../core/backend/knowledge_index_models.dart';
import '../../core/backend/knowledge_viewer_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../knowledge_viewer/knowledge_document_anchor_helpers.dart';
import '../knowledge_viewer/knowledge_document_viewer.dart';
import 'knowledge_index_status_card.dart';

class KnowledgeIndexDebugPage extends StatefulWidget {
  const KnowledgeIndexDebugPage({super.key});

  @override
  State<KnowledgeIndexDebugPage> createState() =>
      _KnowledgeIndexDebugPageState();
}

class _KnowledgeIndexDebugPageState extends State<KnowledgeIndexDebugPage> {
  List<ContentKnowledgeDocument>? _documents;
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_reload(forceLoading: true));
  }

  KnowledgeBackend? get _knowledgeBackend {
    final backend = AppBackendScope.maybeOf(context);
    if (backend == null) return null;
    return maybeKnowledgeBackendFor(backend);
  }

  Uint8List? get _sessionKey {
    final scope = SessionScope.maybeOf(context);
    if (scope == null) return null;
    return Uint8List.fromList(scope.sessionKey);
  }

  Future<void> _reload({required bool forceLoading}) async {
    final backend = _knowledgeBackend;
    final key = _sessionKey;
    if (backend == null || key == null) {
      if (!mounted) return;
      setState(() {
        _documents = null;
        _loading = false;
        _error = null;
      });
      return;
    }

    final generation = ++_generation;
    if (forceLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final docs = await backend.listKnowledgeDocuments(key, limit: 50);
      if (!mounted || generation != _generation) return;
      setState(() {
        _documents = docs;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _anchorSummary(KnowledgeAnchorSet anchors) {
    final labels = knowledgeAnchorLabels(anchors);
    if (labels.isEmpty) return '';
    return labels.join(' · ');
  }

  void _openDocument(String documentId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            KnowledgeIndexDocumentViewerPage(documentId: documentId),
      ),
    );
  }

  Widget _buildDocumentsCard(BuildContext context) {
    if (_loading) {
      return const SlSurface(
        key: ValueKey('knowledge_index_debug_loading'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error case final error?) {
      return SlSurface(
        key: const ValueKey('knowledge_index_debug_error'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(error),
        ),
      );
    }

    final docs = _documents ?? const <ContentKnowledgeDocument>[];
    if (docs.isEmpty) {
      return SlSurface(
        key: const ValueKey('knowledge_index_debug_empty'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.t.settings.knowledgeIndex.status.empty),
        ),
      );
    }

    return SlSurface(
      key: const ValueKey('knowledge_index_debug_documents'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < docs.length; i++) ...[
            if (i != 0) const Divider(height: 1),
            _KnowledgeDocumentTile(
              doc: docs[i],
              anchorSummary: _anchorSummary(docs[i].anchors),
              onOpen: _openDocument,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('knowledge_index_debug_page'),
      appBar: AppBar(
        title: Text(context.t.settings.knowledgeIndex.title),
        actions: [
          IconButton(
            key: const ValueKey('knowledge_index_debug_refresh'),
            tooltip: context.t.common.actions.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _reload(forceLoading: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_knowledgeBackend != null && _sessionKey != null)
            const KnowledgeIndexStatusCard(),
          const SizedBox(height: 12),
          _buildDocumentsCard(context),
        ],
      ),
    );
  }
}

final class _KnowledgeDocumentTile extends StatelessWidget {
  const _KnowledgeDocumentTile({
    required this.doc,
    required this.anchorSummary,
    required this.onOpen,
  });

  final ContentKnowledgeDocument doc;
  final String anchorSummary;
  final void Function(String documentId) onOpen;

  @override
  Widget build(BuildContext context) {
    final title = (doc.title ?? '').trim().isNotEmpty
        ? doc.title!.trim()
        : doc.documentId;
    final subtitleLines = <String>[
      '${doc.originType.name} · ${doc.sourceKind.name} · ${doc.role.name}',
      if (anchorSummary.isNotEmpty) anchorSummary,
    ];
    return ListTile(
      key: ValueKey('knowledge_index_debug_doc_${doc.documentId}'),
      title: Text(title),
      subtitle: Text(subtitleLines.join('\n')),
      isThreeLine: subtitleLines.length >= 2,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onOpen(doc.documentId),
    );
  }
}

class KnowledgeIndexDocumentViewerPage extends StatelessWidget {
  const KnowledgeIndexDocumentViewerPage({
    required this.documentId,
    super.key,
  });

  final String documentId;

  Future<KnowledgeViewerDocument?> _resolve(BuildContext context) async {
    final backend = AppBackendScope.maybeOf(context);
    final viewerBackend =
        backend == null ? null : maybeKnowledgeViewerBackendFor(backend);
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (viewerBackend == null || sessionKey == null) return null;

    try {
      return await viewerBackend.getKnowledgeViewerDocument(
        sessionKey,
        documentId: documentId,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildErrorScaffold(BuildContext context, String message) {
    return Scaffold(
      appBar: AppBar(title: Text(documentId)),
      body: Center(child: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<KnowledgeViewerDocument?>(
      future: _resolve(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final resolved = snapshot.data;
        if (resolved == null) {
          return _buildErrorScaffold(
            context,
            context.t.errors.loadFailed(error: documentId),
          );
        }

        final backend = AppBackendScope.maybeOf(context);
        final viewerBackend =
            backend == null ? null : maybeKnowledgeViewerBackendFor(backend);
        final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
        if (viewerBackend == null || sessionKey == null) {
          return _buildErrorScaffold(
            context,
            context.t.errors.loadFailed(error: documentId),
          );
        }

        final doc = resolved.document;
        final title = (doc.title ?? '').trim().isNotEmpty
            ? doc.title!.trim()
            : documentId;

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: KnowledgeDocumentViewer(
            backend: viewerBackend,
            sessionKey: sessionKey,
            documentId: documentId,
            initialDocument: resolved,
            fallbackText: doc.rawText,
          ),
        );
      },
    );
  }
}
