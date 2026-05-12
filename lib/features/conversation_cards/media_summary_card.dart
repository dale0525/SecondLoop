import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_status_chip.dart';
import '../agent_ui/agent_tab_bar.dart';

final class MediaSummaryData {
  const MediaSummaryData({
    required this.attachments,
    required this.summary,
    required this.fields,
    required this.reviewItems,
  });

  final List<MediaAttachmentChipData> attachments;
  final String summary;
  final List<ExtractedMediaField> fields;
  final List<MediaReviewItem> reviewItems;

  static MediaSummaryData demo() {
    return const MediaSummaryData(
      attachments: [
        MediaAttachmentChipData(
          name: 'passport-scan.pdf',
          type: 'PDF',
        ),
        MediaAttachmentChipData(
          name: 'meeting-audio.m4a',
          type: 'Audio',
        ),
      ],
      summary:
          'SecondLoop found identity-document metadata and a meeting transcript candidate.',
      fields: [
        ExtractedMediaField(
          label: 'Expiry date',
          value: '2027-04-18',
          source: 'passport-scan.pdf',
          confidencePercent: 92,
        ),
        ExtractedMediaField(
          label: 'Meeting action owner',
          value: 'Mina Park',
          source: 'meeting-audio.m4a',
          confidencePercent: 84,
        ),
      ],
      reviewItems: [
        MediaReviewItem(
          title: 'Create expiry reminder',
          subtitle: 'Six months before the passport expiry date.',
        ),
      ],
    );
  }
}

final class MediaAttachmentChipData {
  const MediaAttachmentChipData({
    required this.name,
    required this.type,
  });

  final String name;
  final String type;
}

final class ExtractedMediaField {
  const ExtractedMediaField({
    required this.label,
    required this.value,
    required this.source,
    required this.confidencePercent,
  });

  final String label;
  final String value;
  final String source;
  final int confidencePercent;
}

final class MediaReviewItem {
  const MediaReviewItem({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}

final class MediaSummaryCard extends StatefulWidget {
  const MediaSummaryCard({
    required this.data,
    super.key,
  });

  final MediaSummaryData data;

  @override
  State<MediaSummaryCard> createState() => _MediaSummaryCardState();
}

final class _MediaSummaryCardState extends State<MediaSummaryCard> {
  String _selectedTabId = 'summary';

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final t = context.t.chat.mediaSummary;
    return SlSurface(
      key: const ValueKey('media_summary_card'),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AgentDesignTokens.gapSm,
            runSpacing: AgentDesignTokens.gapSm,
            children: [
              for (final attachment in widget.data.attachments)
                Chip(
                  avatar: const Icon(Icons.attach_file_rounded, size: 16),
                  label: Text(attachment.name),
                ),
            ],
          ),
          const SizedBox(height: AgentDesignTokens.gapMd),
          AgentTabBar(
            tabs: [
              AgentTabItem(id: 'summary', label: t.tabs.summary),
              AgentTabItem(id: 'transcript', label: t.tabs.transcript),
              AgentTabItem(id: 'fields', label: t.tabs.fields),
              AgentTabItem(id: 'actions', label: t.tabs.actions),
              AgentTabItem(id: 'sources', label: t.tabs.sources),
            ],
            selectedId: _selectedTabId,
            onSelected: (id) => setState(() => _selectedTabId = id),
          ),
          const SizedBox(height: AgentDesignTokens.gapLg),
          _MediaSummaryTabBody(
            selectedTabId: _selectedTabId,
            data: widget.data,
          ),
        ],
      ),
    );
  }
}

final class _MediaSummaryTabBody extends StatelessWidget {
  const _MediaSummaryTabBody({
    required this.selectedTabId,
    required this.data,
  });

  final String selectedTabId;
  final MediaSummaryData data;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.mediaSummary;
    return switch (selectedTabId) {
      'transcript' => _MediaPlainSection(
          title: t.tabs.transcript,
          lines: data.attachments
              .where((attachment) => attachment.type == 'Audio')
              .map((attachment) => attachment.name)
              .toList(),
        ),
      'fields' => _ExtractedFields(fields: data.fields),
      'actions' => _SuggestedReviewItems(items: data.reviewItems),
      'sources' => _MediaPlainSection(
          title: t.tabs.sources,
          lines: [
            for (final attachment in data.attachments)
              '${attachment.type}: ${attachment.name}',
          ],
        ),
      _ => Text(data.summary),
    };
  }
}

final class _MediaPlainSection extends StatelessWidget {
  const _MediaPlainSection({
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        for (final line in lines) Text(line),
      ],
    );
  }
}

final class _ExtractedFields extends StatelessWidget {
  const _ExtractedFields({required this.fields});

  final List<ExtractedMediaField> fields;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.mediaSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.extractedFields,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        for (final field in fields) _ExtractedFieldRow(field: field),
      ],
    );
  }
}

final class _ExtractedFieldRow extends StatelessWidget {
  const _ExtractedFieldRow({required this.field});

  final ExtractedMediaField field;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = context.t.chat.mediaSummary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AgentDesignTokens.gapSm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      field.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  AgentStatusChip.allowed(
                    label: t.confidence(percent: field.confidencePercent),
                  ),
                ],
              ),
              const SizedBox(height: AgentDesignTokens.gapXs),
              Text(field.value),
              const SizedBox(height: AgentDesignTokens.gapXs),
              Text(
                t.source(name: field.source),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SuggestedReviewItems extends StatelessWidget {
  const _SuggestedReviewItems({required this.items});

  final List<MediaReviewItem> items;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.mediaSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.suggestedReviewItems,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(item.title),
            subtitle: Text(item.subtitle),
          ),
      ],
    );
  }
}
