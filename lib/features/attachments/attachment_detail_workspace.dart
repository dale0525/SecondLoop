import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

const double kAttachmentDetailWorkspaceMaxWidth = 1180;
const double kAttachmentDetailWorkspaceGap = 16;
const double kAttachmentDetailWorkspaceInspectorWidth = 360;

enum AttachmentDetailInspectorTab {
  content,
  metadata,
}

final class AttachmentDetailMetric {
  const AttachmentDetailMetric({
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;
}

final class AttachmentDetailMetadataItem {
  const AttachmentDetailMetadataItem({
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;
}

final class AttachmentDetailAction {
  const AttachmentDetailAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.key,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final FutureOr<void> Function()? onPressed;
  final Key? key;
  final bool primary;
}

class AttachmentDetailWorkspace extends StatelessWidget {
  const AttachmentDetailWorkspace({
    required this.title,
    required this.typeLabel,
    required this.content,
    this.preview,
    this.metrics = const <AttachmentDetailMetric>[],
    this.metadataItems = const <AttachmentDetailMetadataItem>[],
    this.actions = const <AttachmentDetailAction>[],
    this.maxWidth = kAttachmentDetailWorkspaceMaxWidth,
    super.key,
  });

  final String title;
  final String typeLabel;
  final Widget? preview;
  final Widget content;
  final List<AttachmentDetailMetric> metrics;
  final List<AttachmentDetailMetadataItem> metadataItems;
  final List<AttachmentDetailAction> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasPreview = preview != null;
        final isWide = hasPreview && constraints.maxWidth >= 980;

        return Center(
          key: const ValueKey('attachment_detail_workspace'),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AttachmentDetailHeaderBar(
                    title: title,
                    typeLabel: typeLabel,
                    metrics: metrics,
                    actions: actions,
                  ),
                  const SizedBox(height: kAttachmentDetailWorkspaceGap),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: KeyedSubtree(
                            key: const ValueKey(
                                'attachment_detail_preview_pane'),
                            child: preview!,
                          ),
                        ),
                        const SizedBox(width: kAttachmentDetailWorkspaceGap),
                        SizedBox(
                          width: kAttachmentDetailWorkspaceInspectorWidth,
                          child: AttachmentDetailInspector(
                            content: content,
                            metadataItems: metadataItems,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    if (hasPreview)
                      KeyedSubtree(
                        key: const ValueKey('attachment_detail_preview_pane'),
                        child: preview!,
                      ),
                    if (hasPreview)
                      const SizedBox(height: kAttachmentDetailWorkspaceGap),
                    AttachmentDetailInspector(
                      content: content,
                      metadataItems: metadataItems,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AttachmentDetailHeaderBar extends StatelessWidget {
  const AttachmentDetailHeaderBar({
    required this.title,
    required this.typeLabel,
    required this.metrics,
    required this.actions,
    super.key,
  });

  final String title;
  final String typeLabel;
  final List<AttachmentDetailMetric> metrics;
  final List<AttachmentDetailAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = SlTokens.of(context);
    final secondaryActions =
        actions.where((action) => !action.primary).toList();
    final primaryAction = actions.where((action) => action.primary).firstOrNull;

    return SlSurface(
      key: const ValueKey('attachment_detail_header_bar'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: tokens.borderSubtle,
                            ),
                          ),
                          child: Text(
                            typeLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (metrics.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: metrics
                            .where((metric) => metric.value.trim().isNotEmpty)
                            .map((metric) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surface2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: tokens.borderSubtle),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  metric.label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  metric.value,
                                  key: metric.valueKey,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ],
                  ],
                ),
              ),
              if (primaryAction != null || secondaryActions.isNotEmpty) ...[
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    runAlignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in secondaryActions)
                        OutlinedButton.icon(
                          key: action.key,
                          onPressed: action.onPressed == null
                              ? null
                              : () => unawaited(Future.sync(action.onPressed!)),
                          icon: Icon(action.icon),
                          label: Text(action.label),
                        ),
                      if (primaryAction != null)
                        FilledButton.icon(
                          key: primaryAction.key,
                          onPressed: primaryAction.onPressed == null
                              ? null
                              : () => unawaited(
                                  Future.sync(primaryAction.onPressed!)),
                          icon: Icon(primaryAction.icon),
                          label: Text(primaryAction.label),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class AttachmentDetailInspector extends StatefulWidget {
  const AttachmentDetailInspector({
    required this.content,
    required this.metadataItems,
    super.key,
  });

  final Widget content;
  final List<AttachmentDetailMetadataItem> metadataItems;

  @override
  State<AttachmentDetailInspector> createState() =>
      _AttachmentDetailInspectorState();
}

class _AttachmentDetailInspectorState extends State<AttachmentDetailInspector> {
  AttachmentDetailInspectorTab _tab = AttachmentDetailInspectorTab.content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = SlTokens.of(context);

    Widget buildTabButton({
      required AttachmentDetailInspectorTab tab,
      required Key key,
      required String label,
    }) {
      final selected = _tab == tab;
      return Expanded(
        child: TextButton(
          key: key,
          onPressed: () => setState(() => _tab = tab),
          style: TextButton.styleFrom(
            foregroundColor:
                selected ? scheme.onSurface : scheme.onSurfaceVariant,
            backgroundColor: selected ? tokens.surface2 : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return SlSurface(
      key: const ValueKey('attachment_detail_inspector'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.borderSubtle),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                buildTabButton(
                  tab: AttachmentDetailInspectorTab.content,
                  key: const ValueKey('attachment_detail_tab_content'),
                  label: context.t.attachments.workspace.tabs.content,
                ),
                const SizedBox(width: 4),
                buildTabButton(
                  tab: AttachmentDetailInspectorTab.metadata,
                  key: const ValueKey('attachment_detail_tab_metadata'),
                  label: context.t.attachments.workspace.tabs.metadata,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _tab == AttachmentDetailInspectorTab.content
                ? KeyedSubtree(
                    key: const ValueKey('attachment_detail_inspector_content'),
                    child: widget.content,
                  )
                : KeyedSubtree(
                    key: const ValueKey('attachment_detail_inspector_metadata'),
                    child: _AttachmentDetailMetadataList(
                      items: widget.metadataItems,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentDetailMetadataList extends StatelessWidget {
  const _AttachmentDetailMetadataList({
    required this.items,
  });

  final List<AttachmentDetailMetadataItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visibleItems = items
        .where((item) => item.value.trim().isNotEmpty)
        .toList(growable: false);
    if (visibleItems.isEmpty) {
      return Text(
        context.t.attachments.content.emptyText,
        key: const ValueKey('attachment_detail_metadata_empty'),
        style: theme.textTheme.bodySmall?.copyWith(
          fontStyle: FontStyle.italic,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: visibleItems.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  item.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  item.value,
                  key: item.valueKey,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }
}

String formatAttachmentByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = -1;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String formatAttachmentDurationLabel(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
