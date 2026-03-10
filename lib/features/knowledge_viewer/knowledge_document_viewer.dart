import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/knowledge_viewer_backend.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/models.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../chat/chat_markdown_editor_launcher.dart';
import 'knowledge_document_anchor_helpers.dart';
import 'knowledge_document_block_tile.dart';
import 'knowledge_document_controller.dart';
import 'knowledge_document_models.dart';
import 'knowledge_document_search_bar.dart';

class KnowledgeDocumentViewer extends StatefulWidget {
  const KnowledgeDocumentViewer({
    required this.backend,
    required this.sessionKey,
    required this.documentId,
    required this.initialDocument,
    required this.fallbackText,
    this.onSave,
    this.extraActions = const <KnowledgeDocumentViewerAction>[],
    this.pageSize = 48,
    super.key,
  });

  final KnowledgeViewerBackend backend;
  final Uint8List sessionKey;
  final String documentId;
  final KnowledgeViewerDocument initialDocument;
  final String fallbackText;
  final Future<void> Function(String value)? onSave;
  final List<KnowledgeDocumentViewerAction> extraActions;
  final int pageSize;

  @override
  State<KnowledgeDocumentViewer> createState() =>
      _KnowledgeDocumentViewerState();
}

class _KnowledgeDocumentViewerState extends State<KnowledgeDocumentViewer> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _unitKeys = <String, GlobalKey>{};

  late final TextEditingController _queryController;
  late KnowledgeDocumentController _controller;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _controller = KnowledgeDocumentController(
      backend: widget.backend,
      sessionKey: widget.sessionKey,
      documentId: widget.documentId,
      initialDocument: widget.initialDocument,
      pageSize: widget.pageSize,
    );
    unawaited(_controller.loadPage(reset: true));
  }

  @override
  void didUpdateWidget(covariant KnowledgeDocumentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId) {
      _controller.reset(
        documentId: widget.documentId,
        initialDocument: widget.initialDocument,
      );
      _queryController.text = '';
      unawaited(_controller.loadPage(reset: true));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _searchDocument() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      await _controller.clearSearchAndReload();
      return;
    }
    await _controller.searchDocument(query);
  }

  GlobalKey _unitKey(String unitId) {
    return _unitKeys.putIfAbsent(unitId, GlobalKey.new);
  }

  void _scrollToUnit(String unitId) {
    final key = _unitKeys[unitId];
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = key.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        alignment: 0.18,
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _jumpToResult(KnowledgeSearchResult result) async {
    await _controller.jumpToResult(result);
    if (!mounted) return;
    final highlighted = _controller.highlightedUnitId;
    if (highlighted != null) _scrollToUnit(highlighted);
  }

  Future<void> _copyDocument() async {
    final text = _copyableText().trim();
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null && Scaffold.maybeOf(context) != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.actions.history.actions.copied),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _copyableText() {
    final rawText = _controller.viewerDocument.document.rawText.trim();
    if (rawText.isNotEmpty) return rawText;
    return _controller.units
        .map((unit) => unit.rawText.trim().isNotEmpty
            ? unit.rawText.trim()
            : unit.normalizedText.trim())
        .where((value) => value.isNotEmpty)
        .join('\n\n');
  }

  Future<void> _editDocument() async {
    final onSave = widget.onSave;
    if (onSave == null) return;

    final doc = _controller.viewerDocument.document;
    final result = await openChatMarkdownEditor(
      context,
      initialText: widget.fallbackText,
      title: (doc.title ?? '').trim().isNotEmpty
          ? doc.title!.trim()
          : context.t.attachments.content.fullText,
      saveLabel: context.t.common.actions.save,
      allowPlainMode: false,
    );
    if (result == null) return;

    try {
      await onSave(result.text.trim());
    } catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null && Scaffold.maybeOf(context) != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.t.errors.saveFailed(error: '$error')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildSearchResults(BuildContext context) {
    final results = _controller.searchResults;
    if (results.isEmpty) return const SizedBox.shrink();
    return SlSurface(
      key: const ValueKey('knowledge_viewer_search_results'),
      padding: const EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final result = results[index];
            final subtitleParts = knowledgeAnchorLabels(result.anchors);
            return ListTile(
              key: ValueKey(
                'knowledge_viewer_search_hit_${result.unitId ?? result.documentId}',
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                result.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitleParts.isEmpty
                  ? null
                  : Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
              onTap: () => unawaited(_jumpToResult(result)),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewerHeight = (MediaQuery.sizeOf(context).height * 0.45)
        .clamp(260.0, 520.0)
        .toDouble();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final summary =
            (_controller.viewerDocument.document.summary ?? '').trim();
        final units = _controller.units;
        final highlightedUnitId = _controller.highlightedUnitId;

        return Material(
          color: Colors.transparent,
          child: SlSurface(
            key: const ValueKey('attachment_knowledge_viewer'),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summary.isNotEmpty) ...[
                  Text(
                    context.t.attachments.content.summary,
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    summary,
                    key: const ValueKey('knowledge_viewer_summary'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                KnowledgeDocumentSearchBar(
                  queryController: _queryController,
                  searching: _controller.searching,
                  onSearch: _searchDocument,
                  onCopy: _copyDocument,
                  onEdit: widget.onSave == null ? null : _editDocument,
                  extraActions: widget.extraActions,
                ),
                const SizedBox(height: 12),
                _buildSearchResults(context),
                if (_controller.searchResults.isNotEmpty)
                  const SizedBox(height: 12),
                Container(
                  height: viewerHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: SlTokens.of(context).borderSubtle),
                  ),
                  child: _controller.loadError != null
                      ? Center(
                          child: IconButton(
                            key: const ValueKey('knowledge_viewer_retry'),
                            onPressed: () => unawaited(
                              _controller.loadPage(reset: true),
                            ),
                            tooltip: context.t.common.actions.retry,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        )
                      : _controller.loadingPage && units.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.separated(
                              key: const ValueKey('knowledge_viewer_list'),
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: units.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final unit = units[index];
                                return KeyedSubtree(
                                  key: _unitKey(unit.unitId),
                                  child: KnowledgeDocumentBlockTile(
                                    unit: unit,
                                    highlighted:
                                        unit.unitId == highlightedUnitId,
                                  ),
                                );
                              },
                            ),
                ),
                if (!_controller.anchorMode &&
                    units.length < _controller.total) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        key: const ValueKey('knowledge_viewer_load_more'),
                        onPressed: _controller.loadingMore
                            ? null
                            : () =>
                                unawaited(_controller.loadPage(reset: false)),
                        icon: _controller.loadingMore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_more_rounded),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
