import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_viewer_backend.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/models.dart';
import 'knowledge_document_viewer.dart';

class KnowledgeDocumentViewerPage extends StatelessWidget {
  const KnowledgeDocumentViewerPage({
    required this.documentId,
    super.key,
  });

  final String documentId;

  static Future<void> openDocumentId(
    BuildContext context, {
    required String documentId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          KnowledgeDocumentViewerPage(documentId: documentId),
        ),
      ),
    );
  }

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
