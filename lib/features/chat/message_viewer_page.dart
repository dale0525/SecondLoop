import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_backend.dart';
import '../../core/backend/knowledge_viewer_backend.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/models.dart';
import '../../src/rust/knowledge/pages.dart' as rust_knowledge_pages;
import '../../ui/sl_markdown_style.dart';
import '../actions/assistant_message_actions.dart';
import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_viewer_page.dart';
import '../knowledge_viewer/knowledge_document_viewer.dart';
import '../knowledge_viewer/knowledge_document_viewer_page.dart';
import '../memory/memory_detail_page.dart';
import 'chat_answer_citation_controller.dart';
import 'chat_answer_evidence_models.dart';
import 'chat_answer_evidence_parser.dart';
import 'chat_answer_evidence_sheet.dart';
import 'chat_markdown_link_handler.dart';
import 'knowledge_document_deeplink.dart';
import 'message_deeplink.dart';
import 'chat_markdown_rich_rendering.dart';
import 'chat_markdown_sanitizer.dart';
import 'chat_markdown_theme_presets.dart';

const _kMessageKnowledgeViewerCharThreshold = 3200;
const _kMessageKnowledgeViewerLineThreshold = 120;

bool _shouldUseMessageKnowledgeViewer(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.length >= _kMessageKnowledgeViewerCharThreshold) return true;
  final lineCount = '\n'.allMatches(trimmed).length + 1;
  return lineCount >= _kMessageKnowledgeViewerLineThreshold;
}

class MessageViewerPage extends StatelessWidget {
  const MessageViewerPage({
    required this.content,
    this.messageId,
    this.citationsJson,
    this.navigationTrail = const <String>[],
    super.key,
  });

  static const int _maxNavigationDepth = 8;

  final String content;
  final String? messageId;
  final String? citationsJson;
  final List<String> navigationTrail;

  List<String> get _effectiveNavigationTrail {
    final trail = <String>[...navigationTrail];
    final currentMessageId = messageId?.trim() ?? '';
    if (currentMessageId.isNotEmpty && !trail.contains(currentMessageId)) {
      trail.add(currentMessageId);
    }
    return trail;
  }

  static Future<void> openById(
    BuildContext context, {
    required String messageId,
    List<String> navigationTrail = const <String>[],
  }) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return;
    }
    if (navigationTrail.contains(normalizedMessageId)) {
      return;
    }
    if (navigationTrail.length >= _maxNavigationDepth) {
      return;
    }

    final session = SessionScope.maybeOf(context);
    if (session == null) {
      return;
    }

    final backend = AppBackendScope.of(context);
    final message = await backend.getMessageById(
      session.sessionKey,
      normalizedMessageId,
    );
    if (!context.mounted || message == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          MessageViewerPage(
            content: message.role == 'assistant'
                ? parseAssistantMessageActions(message.content).displayText
                : message.content,
            messageId: message.id,
            citationsJson: message.citationsJson,
            navigationTrail: <String>[...navigationTrail, normalizedMessageId],
          ),
        ),
      ),
    );
  }

  Future<bool> _openInAppAttachment(BuildContext context, String href) async {
    final parsed = parseAttachmentDeepLink(href);
    if (parsed == null) return false;

    await AttachmentViewerPage.openBySha(
      context,
      attachmentSha256: parsed.attachmentSha256,
      initialContentKind: parsed.kind,
      initialChunkIndex: parsed.chunk,
    );
    return true;
  }

  Future<bool> _openInAppMessage(BuildContext context, String href) async {
    final parsed = parseMessageDeepLink(href);
    if (parsed == null) return false;

    await MessageViewerPage.openById(
      context,
      messageId: parsed.messageId,
      navigationTrail: _effectiveNavigationTrail,
    );
    return true;
  }

  Future<void> _disableMemoryFromEvidence(
    BuildContext context,
    String documentId,
  ) async {
    final pagesBackend =
        maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (documentId.startsWith('page:') &&
        pagesBackend != null &&
        sessionKey != null) {
      await pagesBackend.setKnowledgePageAnswerAllowed(
        sessionKey,
        pageId: documentId,
        allowed: false,
      );
      return;
    }
    final backend = maybeKnowledgeBackendFor(AppBackendScope.of(context));
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    if (backend == null || viewerBackend == null || sessionKey == null) return;
    final document = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: documentId,
    );
    final feedback = document.document.memoryFeedback;
    await backend.upsertKnowledgeMemoryFeedback(
      sessionKey,
      documentId: documentId,
      status: feedback.status,
      useForAskAi: false,
      isDeleted: feedback.isDeleted,
      markedInaccurate: feedback.markedInaccurate,
      correctedTitle: feedback.correctedTitle,
      correctedSummary: feedback.correctedSummary,
    );
  }

  Future<void> _deleteMemoryFromEvidence(
    BuildContext context,
    String documentId,
  ) async {
    final pagesBackend =
        maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (documentId.startsWith('page:') &&
        pagesBackend != null &&
        sessionKey != null) {
      await pagesBackend.archiveKnowledgePage(
        sessionKey,
        pageId: documentId,
      );
      return;
    }
    final backend = maybeKnowledgeBackendFor(AppBackendScope.of(context));
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    if (backend == null || viewerBackend == null || sessionKey == null) return;
    final document = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: documentId,
    );
    final feedback = document.document.memoryFeedback;
    await backend.upsertKnowledgeMemoryFeedback(
      sessionKey,
      documentId: documentId,
      status: feedback.status,
      useForAskAi: feedback.useForAskAi,
      isDeleted: true,
      markedInaccurate: feedback.markedInaccurate,
      correctedTitle: feedback.correctedTitle,
      correctedSummary: feedback.correctedSummary,
    );
  }

  Future<ChatAnswerEvidenceMemoryCard?> _correctMemoryFromEvidence(
    BuildContext context,
    ChatAnswerEvidenceMemoryCard card, {
    required String title,
    required String summary,
  }) async {
    final pagesBackend =
        maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (card.documentId.startsWith('page:') &&
        pagesBackend != null &&
        sessionKey != null) {
      final detail = await pagesBackend.correctKnowledgePage(
        sessionKey,
        pageId: card.documentId,
        title: title,
        summary: summary,
        body: summary,
      );
      return _memoryCardFromPageDetail(card, detail);
    }
    final backend = maybeKnowledgeBackendFor(AppBackendScope.of(context));
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    if (backend == null || viewerBackend == null || sessionKey == null) {
      return null;
    }
    final document = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: card.documentId,
    );
    final feedback = document.document.memoryFeedback;
    await backend.upsertKnowledgeMemoryFeedback(
      sessionKey,
      documentId: card.documentId,
      status: KnowledgeMemoryStatus.confirmed,
      useForAskAi: feedback.useForAskAi,
      isDeleted: false,
      markedInaccurate: feedback.markedInaccurate,
      correctedTitle: title,
      correctedSummary: summary,
    );
    final refreshed = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: card.documentId,
    );
    return _memoryCardFromViewerDocument(card, refreshed.document);
  }

  Future<ChatAnswerEvidenceMemoryCard?> _refreshMemoryFromEvidence(
    BuildContext context,
    ChatAnswerEvidenceMemoryCard card,
  ) async {
    final pagesBackend =
        maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (card.documentId.startsWith('page:') &&
        pagesBackend != null &&
        sessionKey != null) {
      final detail = await pagesBackend.getKnowledgePageDetail(
        sessionKey,
        pageId: card.documentId,
      );
      return _memoryCardFromPageDetail(card, detail);
    }
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    if (viewerBackend == null || sessionKey == null) {
      return card;
    }
    final refreshed = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: card.documentId,
    );
    return _memoryCardFromViewerDocument(card, refreshed.document);
  }

  ChatAnswerEvidenceMemoryCard _memoryCardFromViewerDocument(
    ChatAnswerEvidenceMemoryCard card,
    ContentKnowledgeDocument document,
  ) {
    final memoryDisplay = document.memoryDisplay;
    return card.copyWith(
      title: document.title,
      summary: document.summary,
      body: document.rawText,
      status: (memoryDisplay?.status ??
              document.memoryFeedback.status ??
              KnowledgeMemoryStatus.confirmed)
          .name,
      sourceCount: memoryDisplay?.sourceCount.toInt() ?? card.sourceCount,
      updatedAtMs: document.updatedAtMs.toInt(),
      useForAskAi: document.memoryFeedback.useForAskAi,
      isDeleted: document.memoryFeedback.isDeleted,
      markedInaccurate: document.memoryFeedback.markedInaccurate,
    );
  }

  ChatAnswerEvidenceMemoryCard _memoryCardFromPageDetail(
    ChatAnswerEvidenceMemoryCard card,
    rust_knowledge_pages.KnowledgePageDetail detail,
  ) {
    final page = detail.page;
    final status = page.humanCorrected
        ? KnowledgeMemoryStatus.confirmed.name
        : (page.state == rust_knowledge_pages.KnowledgePageState.outdated
            ? KnowledgeMemoryStatus.maybeOutdated.name
            : KnowledgeMemoryStatus.inferred.name);
    return card.copyWith(
      title: page.title,
      summary: page.currentSummary,
      body: page.currentBody,
      status: status,
      sourceCount: page.sourceCount.toInt(),
      updatedAtMs: page.updatedAtMs.toInt(),
      useForAskAi: page.answerPolicy.defaultAllowed,
      isDeleted: page.state == rust_knowledge_pages.KnowledgePageState.removed,
      markedInaccurate:
          page.state == rust_knowledge_pages.KnowledgePageState.needsReview,
    );
  }

  Future<bool> _openInAppKnowledgeDocument(
    BuildContext context,
    String href,
  ) async {
    final parsed = parseKnowledgeDocumentDeepLink(href);
    if (parsed == null) return false;
    if (maybeKnowledgeViewerBackendFor(AppBackendScope.of(context)) == null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            context.t.errors.loadFailed(
              error: 'knowledge_viewer_backend_unavailable',
            ),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return true;
    }

    await KnowledgeDocumentViewerPage.openDocumentId(
      context,
      documentId: parsed.documentId,
      initialHighlightedUnitId: parsed.unitId,
    );
    return true;
  }

  Future<bool> _openInAppLink(BuildContext context, String href) async {
    if (await _openInAppAttachment(context, href)) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    if (await _openInAppKnowledgeDocument(context, href)) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    return _openInAppMessage(context, href);
  }

  Future<void> _openMemoryCard(BuildContext context, String documentId) {
    return MemoryDetailPage.openDocumentId(context, documentId: documentId);
  }

  Future<_ResolvedMessageKnowledgeDocument?> _resolveKnowledgeDocument(
    BuildContext context,
  ) async {
    final normalizedMessageId = messageId?.trim() ?? '';
    if (normalizedMessageId.isEmpty) return null;
    if (!_shouldUseMessageKnowledgeViewer(content)) return null;

    final backend = AppBackendScope.maybeOf(context);
    final viewerBackend =
        backend == null ? null : maybeKnowledgeViewerBackendFor(backend);
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (viewerBackend == null || sessionKey == null) return null;

    final documentId = 'message:$normalizedMessageId';
    try {
      final document = await viewerBackend.getKnowledgeViewerDocument(
        sessionKey,
        documentId: documentId,
      );
      return _ResolvedMessageKnowledgeDocument(
        documentId: documentId,
        document: document,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildMarkdownBody(
    BuildContext context, {
    required String normalized,
    required ChatAnswerCitationController citationController,
  }) {
    final backend = AppBackendScope.maybeOf(context);
    final viewerBackend =
        backend == null ? null : maybeKnowledgeViewerBackendFor(backend);
    final knowledgeBackend =
        backend == null ? null : maybeKnowledgeBackendFor(backend);
    final openMemoryCard = viewerBackend == null
        ? null
        : (String documentId) => _openMemoryCard(context, documentId);
    final correctMemoryCard = knowledgeBackend == null || viewerBackend == null
        ? null
        : (
            ChatAnswerEvidenceMemoryCard card,
            String title,
            String summary,
          ) =>
            _correctMemoryFromEvidence(
              context,
              card,
              title: title,
              summary: summary,
            );
    final refreshMemoryCard = knowledgeBackend == null || viewerBackend == null
        ? null
        : (ChatAnswerEvidenceMemoryCard card) =>
            _refreshMemoryFromEvidence(context, card);
    final disableMemoryCard = knowledgeBackend == null || viewerBackend == null
        ? null
        : (String documentId) =>
            _disableMemoryFromEvidence(context, documentId);
    final deleteMemoryCard = knowledgeBackend == null || viewerBackend == null
        ? null
        : (String documentId) => _deleteMemoryFromEvidence(context, documentId);
    final previewTheme = resolveChatMarkdownTheme(
        ChatMarkdownThemePreset.studio, Theme.of(context));
    return Markdown(
      key: const ValueKey('message_viewer_markdown'),
      data: normalized,
      selectable: true,
      softLineBreak: true,
      styleSheet: slMarkdownStyleSheet(context),
      blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
      inlineSyntaxes: buildChatMarkdownInlineSyntaxes(
        enableSecondLoopDeepLinks: true,
      ),
      builders: buildChatMarkdownElementBuilders(
        previewTheme: previewTheme,
        exportRenderMode: false,
        citationLabelResolver: citationController.chipLabelForHref,
        onTapLink: (href) async {
          final handledCitation = await citationController.handleCitationTap(
            context,
            href: href,
            onOpenDirectSource: (target) => _openInAppLink(context, target),
            onOpenMemoryCard: openMemoryCard,
            onCorrectMemoryCard: correctMemoryCard,
            onRefreshMemoryCard: refreshMemoryCard,
            onDisableMemoryCard: disableMemoryCard,
            onDeleteMemoryCard: deleteMemoryCard,
          );
          if (handledCitation) {
            return;
          }
          await handleChatMarkdownTapLink(
            href,
            handleInApp: (target) => _openInAppLink(context, target),
          );
        },
      ),
      onTapLink: (text, href, title) {
        unawaited(
          handleChatMarkdownTapLink(
            href,
            handleInApp: (target) => _openInAppLink(context, target),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required String normalized,
    required ChatAnswerCitationController citationController,
  }) {
    if (!_shouldUseMessageKnowledgeViewer(content) ||
        (messageId?.trim().isEmpty ?? true)) {
      return _buildMarkdownBody(
        context,
        normalized: normalized,
        citationController: citationController,
      );
    }

    return FutureBuilder<_ResolvedMessageKnowledgeDocument?>(
      future: _resolveKnowledgeDocument(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final resolved = snapshot.data;
        if (resolved == null) {
          return _buildMarkdownBody(
            context,
            normalized: normalized,
            citationController: citationController,
          );
        }

        final backend = AppBackendScope.maybeOf(context);
        final viewerBackend =
            backend == null ? null : maybeKnowledgeViewerBackendFor(backend);
        final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
        if (viewerBackend == null || sessionKey == null) {
          return _buildMarkdownBody(
            context,
            normalized: normalized,
            citationController: citationController,
          );
        }

        return KnowledgeDocumentViewer(
          backend: viewerBackend,
          sessionKey: sessionKey,
          documentId: resolved.documentId,
          initialDocument: resolved.document,
          fallbackText: normalized,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalized = sanitizeChatMarkdown(content);
    final backend = AppBackendScope.maybeOf(context);
    final viewerBackend =
        backend == null ? null : maybeKnowledgeViewerBackendFor(backend);
    final knowledgeBackend =
        backend == null ? null : maybeKnowledgeBackendFor(backend);
    final openMemoryCard = viewerBackend == null
        ? null
        : (String documentId) => _openMemoryCard(context, documentId);
    final correctMemoryCard = knowledgeBackend == null || viewerBackend == null
        ? null
        : (
            ChatAnswerEvidenceMemoryCard card,
            String title,
            String summary,
          ) =>
            _correctMemoryFromEvidence(
              context,
              card,
              title: title,
              summary: summary,
            );
    final refreshMemoryCard = knowledgeBackend == null || viewerBackend == null
        ? null
        : (ChatAnswerEvidenceMemoryCard card) =>
            _refreshMemoryFromEvidence(context, card);
    final disableMemoryCard = knowledgeBackend == null || viewerBackend == null
        ? null
        : (String documentId) =>
            _disableMemoryFromEvidence(context, documentId);
    final deleteMemoryCard = knowledgeBackend == null || viewerBackend == null
        ? null
        : (String documentId) => _deleteMemoryFromEvidence(context, documentId);
    final citationController = ChatAnswerCitationController(
      parseChatAnswerEvidence(citationsJson),
    );
    final evidence = citationController.evidence;

    return Scaffold(
      key: const ValueKey('message_viewer_page'),
      appBar: AppBar(
        title: Text(context.t.chat.messageViewer.title),
        actions: [
          IconButton(
            key: const ValueKey('message_viewer_copy'),
            tooltip: context.t.common.actions.copy,
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: normalized.trim()));
              } catch (_) {
                return;
              }
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.t.actions.history.actions.copied),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (evidence != null && evidence.hasEvidence)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ChatAnswerEvidenceSummaryBar(
                  evidence: evidence,
                  onOpenSources: () => unawaited(
                    citationController.openEvidence(
                      context,
                      initialTab: ChatAnswerEvidenceTab.directSources,
                      onOpenDirectSource: (href) =>
                          _openInAppLink(context, href),
                      onOpenMemoryCard: openMemoryCard,
                      canOpenDirectSource: (href) =>
                          _canOpenDirectSourceHref(context, href),
                      onCorrectMemoryCard: correctMemoryCard,
                      onRefreshMemoryCard: refreshMemoryCard,
                      onDisableMemoryCard: disableMemoryCard,
                      onDeleteMemoryCard: deleteMemoryCard,
                    ),
                  ),
                  onOpenMemory: () => unawaited(
                    citationController.openEvidence(
                      context,
                      initialTab: ChatAnswerEvidenceTab.memoryCards,
                      onOpenDirectSource: (href) =>
                          _openInAppLink(context, href),
                      onOpenMemoryCard: openMemoryCard,
                      canOpenDirectSource: (href) =>
                          _canOpenDirectSourceHref(context, href),
                      onCorrectMemoryCard: correctMemoryCard,
                      onRefreshMemoryCard: refreshMemoryCard,
                      onDisableMemoryCard: disableMemoryCard,
                      onDeleteMemoryCard: deleteMemoryCard,
                    ),
                  ),
                  onOpenEvidence: () => unawaited(
                    citationController.openEvidence(
                      context,
                      onOpenDirectSource: (href) =>
                          _openInAppLink(context, href),
                      onOpenMemoryCard: openMemoryCard,
                      canOpenDirectSource: (href) =>
                          _canOpenDirectSourceHref(context, href),
                      onCorrectMemoryCard: correctMemoryCard,
                      onRefreshMemoryCard: refreshMemoryCard,
                      onDisableMemoryCard: disableMemoryCard,
                      onDeleteMemoryCard: deleteMemoryCard,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _buildBody(
              context,
              normalized: normalized,
              citationController: citationController,
            ),
          ),
        ],
      ),
    );
  }
}

final class _ResolvedMessageKnowledgeDocument {
  const _ResolvedMessageKnowledgeDocument({
    required this.documentId,
    required this.document,
  });

  final String documentId;
  final KnowledgeViewerDocument document;
}

bool _canOpenDirectSourceHref(BuildContext context, String href) {
  if (parseKnowledgeDocumentDeepLink(href) != null) {
    return maybeKnowledgeViewerBackendFor(AppBackendScope.of(context)) != null;
  }
  return true;
}
