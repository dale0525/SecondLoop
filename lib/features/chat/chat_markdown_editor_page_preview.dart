part of 'chat_markdown_editor_page.dart';

mixin _ChatMarkdownEditorPreviewMixin on State<ChatMarkdownEditorPage> {
  TextEditingController get _controller;
  ScrollController get _previewScrollController;
  GlobalKey get _previewRepaintBoundaryKey;
  ChatMarkdownThemePreset get _themePreset;
  bool get _exportRenderMode;

  Widget _buildPane(
    BuildContext context, {
    Key? key,
    required String title,
    required IconData icon,
    required Widget child,
  });

  Widget _buildPreviewPane(BuildContext context) {
    final theme = Theme.of(context);
    final previewTheme = resolveChatMarkdownTheme(_themePreset, theme);

    return _buildPane(
      context,
      key: const ValueKey('chat_markdown_editor_preview'),
      title: context.t.chat.markdownEditor.previewLabel,
      icon: Icons.visibility_outlined,
      child: DecoratedBox(
        decoration: BoxDecoration(color: previewTheme.canvasColor),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final normalized = normalizeChatMarkdownForPreview(value.text);

                if (normalized.trim().isEmpty) {
                  return _buildEmptyPreviewState(theme, previewTheme);
                }

                final markdown = buildChatMarkdownPreviewBody(
                  context,
                  text: normalized,
                  selectable: !_exportRenderMode,
                  preset: _themePreset,
                  density: _exportRenderMode
                      ? ChatMarkdownPreviewDensity.compact
                      : ChatMarkdownPreviewDensity.regular,
                );

                if (_exportRenderMode) {
                  return _buildExportPreviewSurface(
                    constraints,
                    markdown,
                  );
                }
                return _buildInteractivePreviewSurface(markdown);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyPreviewState(
    ThemeData theme,
    ChatMarkdownPreviewTheme previewTheme,
  ) {
    final emptyLabel = Text(
      context.t.chat.markdownEditor.emptyPreview,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: previewTheme.mutedTextColor,
      ),
      textAlign: TextAlign.center,
    );

    if (_exportRenderMode) {
      return Center(
        child: RepaintBoundary(
          key: _previewRepaintBoundaryKey,
          child: DecoratedBox(
            decoration: BoxDecoration(color: previewTheme.canvasColor),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: emptyLabel,
            ),
          ),
        ),
      );
    }

    return Center(
      child: RepaintBoundary(
        key: _previewRepaintBoundaryKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: emptyLabel,
        ),
      ),
    );
  }

  Widget _buildInteractivePreviewSurface(
    Widget markdown,
  ) {
    return Scrollbar(
      controller: _previewScrollController,
      child: SingleChildScrollView(
        controller: _previewScrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        child: ChatMarkdownPreviewPanel(
          preset: _themePreset,
          child: RepaintBoundary(
            key: _previewRepaintBoundaryKey,
            child: markdown,
          ),
        ),
      ),
    );
  }

  Widget _buildExportPreviewSurface(
    BoxConstraints constraints,
    Widget markdown,
  ) {
    final maxWidth =
        constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
    final exportSurfaceWidth = math.max(360.0, maxWidth - 8);
    final exportContentWidth = math.min(980.0, exportSurfaceWidth);

    return Scrollbar(
      controller: _previewScrollController,
      child: SingleChildScrollView(
        controller: _previewScrollController,
        padding: EdgeInsets.zero,
        child: Center(
          child: RepaintBoundary(
            key: _previewRepaintBoundaryKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: chatMarkdownPreviewCanvasColor(
                  context,
                  preset: _themePreset,
                ),
              ),
              child: SizedBox(
                width: exportContentWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(54, 48, 54, 64),
                  child: markdown,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
