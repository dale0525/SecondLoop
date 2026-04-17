import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_viewer_backend.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../src/rust/knowledge/models.dart';
import '../../ui/sl_markdown_style.dart';
import '../actions/assistant_message_actions.dart';
import '../actions/calendar/event_deeplink.dart';
import '../actions/calendar/event_viewer_page.dart';
import '../actions/todo/todo_deeplink.dart';
import '../actions/todo/todo_detail_page.dart';
import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_viewer_page.dart';
import '../knowledge_viewer/knowledge_document_viewer.dart';
import 'chat_answer_citation_controller.dart';
import 'chat_answer_evidence_parser.dart';
import 'chat_markdown_link_handler.dart';
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

  Future<bool> _openInAppTodo(BuildContext context, String href) async {
    final parsed = parseTodoDeepLink(href);
    if (parsed == null) return false;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (sessionKey == null) return false;

    Todo? todo;
    try {
      todo = await backend.getTodoById(sessionKey, parsed.todoId);
    } catch (_) {
      todo = null;
    }
    if (todo == null || !context.mounted) return false;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          TodoDetailPage(initialTodo: todo!),
        ),
      ),
    );
    return true;
  }

  Future<bool> _openInAppEvent(BuildContext context, String href) async {
    final parsed = parseEventDeepLink(href);
    if (parsed == null) return false;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (sessionKey == null) return false;

    Event? event;
    try {
      event = await backend.getEventById(sessionKey, parsed.eventId);
    } catch (_) {
      event = null;
    }
    if (event == null || !context.mounted) return false;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          EventViewerPage(event: event!),
        ),
      ),
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

  Future<void> _showUnsupportedSecondLoopLink(
    BuildContext context,
    String href,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t.errors.loadFailed(error: 'unsupported_secondloop_link'),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _openInAppLink(BuildContext context, String href) async {
    if (await _openInAppTodo(context, href)) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    if (await _openInAppEvent(context, href)) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    if (await _openInAppAttachment(context, href)) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    return _openInAppMessage(context, href);
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
          );
          if (handledCitation) {
            return;
          }
          await handleChatMarkdownTapLink(
            href,
            handleInApp: (target) => _openInAppLink(context, target),
            handleUnsupportedSecondLoopLink: (target) =>
                _showUnsupportedSecondLoopLink(context, target),
          );
        },
      ),
      onTapLink: (text, href, title) {
        unawaited(
          handleChatMarkdownTapLink(
            href,
            handleInApp: (target) => _openInAppLink(context, target),
            handleUnsupportedSecondLoopLink: (target) =>
                _showUnsupportedSecondLoopLink(context, target),
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
                      canOpenDirectSource: canOpenChatMarkdownHref,
                      onOpenDirectSource: (href) =>
                          _openInAppLink(context, href),
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
