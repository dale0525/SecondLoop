import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'note_editor_controller.dart';

class NoteDetailPage extends StatelessWidget {
  const NoteDetailPage({
    required this.controller,
    super.key,
  });

  final NoteEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('note_detail_page'),
      color: _NoteDetailColors.surface,
      child: Column(
        children: [
          const _NoteDetailTopBar(),
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding = constraints.maxWidth >=
                            _NoteDetailMetrics.desktopBreakpoint
                        ? _NoteDetailMetrics.desktopMargin
                        : _NoteDetailMetrics.mobileMargin;
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        32,
                        horizontalPadding,
                        84,
                      ),
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _NoteDetailMetrics.contentMaxWidth,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: _NoteDetailContent(controller: controller),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteDetailTopBar extends StatelessWidget {
  const _NoteDetailTopBar();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _NoteDetailColors.surface,
        border: Border(
          bottom: BorderSide(color: _NoteDetailColors.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('note_detail_back_button'),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: _NoteDetailColors.onSurfaceVariant,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.t.notes.vault.recent.viewDetail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _NoteDetailColors.onSurface,
                    fontSize: 20,
                    height: 28 / 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteDetailContent extends StatelessWidget {
  const _NoteDetailContent({required this.controller});

  final NoteEditorController controller;

  @override
  Widget build(BuildContext context) {
    final title = controller.title.trim().isEmpty
        ? context.t.notes.labels.untitled
        : controller.title.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _NoteDetailIconTile(),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.notes.vault.categories.notes,
                    style: const TextStyle(
                      color: _NoteDetailColors.onSurfaceVariant,
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    title,
                    key: const ValueKey('note_detail_title'),
                    style: const TextStyle(
                      color: _NoteDetailColors.onSurface,
                      fontSize: 28,
                      height: 34 / 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _NoteDetailStatusPill(status: controller.status),
          ],
        ),
        const SizedBox(height: 24),
        _NoteDetailBodyCard(body: controller.body),
      ],
    );
  }
}

class _NoteDetailIconTile extends StatelessWidget {
  const _NoteDetailIconTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _NoteDetailColors.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(
        Icons.edit_note,
        size: 22,
        color: _NoteDetailColors.onSurface,
      ),
    );
  }
}

class _NoteDetailStatusPill extends StatelessWidget {
  const _NoteDetailStatusPill({required this.status});

  final NoteEditorStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('note_detail_status_pill'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _NoteDetailColors.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label(context),
        style: const TextStyle(
          color: _NoteDetailColors.onSurfaceVariant,
          fontSize: 11,
          height: 14 / 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }

  String _label(BuildContext context) {
    return switch (status) {
      NoteEditorStatus.clean => context.t.notes.status.saved,
      NoteEditorStatus.pending => context.t.notes.status.pending,
      NoteEditorStatus.saving => context.t.notes.status.saving,
      NoteEditorStatus.conflict => context.t.notes.status.conflict,
      NoteEditorStatus.failed => context.t.notes.status.failed,
    };
  }
}

class _NoteDetailBodyCard extends StatelessWidget {
  const _NoteDetailBodyCard({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('note_detail_body_card'),
      color: _NoteDetailColors.lowestSurface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      shadowColor: const Color(0x1A000000),
      elevation: 1,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            body,
            key: const ValueKey('note_detail_body_text'),
            style: const TextStyle(
              color: _NoteDetailColors.onSurface,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

abstract final class _NoteDetailColors {
  static const surface = Color(0xFFF7F9FB);
  static const lowestSurface = Color(0xFFFFFFFF);
  static const surfaceContainer = Color(0xFFECEEF0);
  static const outlineVariant = Color(0xFFC6C6CD);
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF45464D);
}

abstract final class _NoteDetailMetrics {
  static const mobileMargin = 16.0;
  static const desktopMargin = 32.0;
  static const desktopBreakpoint = 768.0;
  static const contentMaxWidth = 1280.0;
}
