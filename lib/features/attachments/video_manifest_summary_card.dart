import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'video_keyframe_ocr_worker.dart';

class VideoManifestSummaryCard extends StatelessWidget {
  const VideoManifestSummaryCard({
    super.key,
    required this.manifest,
    required this.payload,
  });

  final ParsedVideoManifest manifest;
  final Map<String, Object?>? payload;

  bool get _hasAudio => (manifest.audioSha256 ?? '').trim().isNotEmpty;

  bool get _isProxyTruncated => payload?['video_proxy_truncated'] == true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SlSurface(
      key: const ValueKey('video_manifest_summary_surface'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t.attachments.content.videoInsights.fields.summary,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryCountChip(
                key: const ValueKey('video_manifest_summary_segments'),
                icon: Icons.splitscreen_rounded,
                label:
                    context.t.attachments.content.videoInsights.fields.segments,
                value: '${manifest.segments.length}',
              ),
              _SummaryCountChip(
                key: const ValueKey('video_manifest_summary_keyframes'),
                icon: Icons.photo_library_outlined,
                label: context
                    .t.attachments.content.videoInsights.fields.keyframes,
                value: '${manifest.keyframes.length}',
              ),
              _SummaryBoolChip(
                key: const ValueKey('video_manifest_summary_audio'),
                icon: Icons.graphic_eq_rounded,
                label: context.t.attachments.workspace.types.audio,
                value: _hasAudio,
              ),
              _SummaryBoolChip(
                key: const ValueKey('video_manifest_summary_truncated'),
                icon: Icons.content_cut_rounded,
                label: context
                    .t.attachments.content.videoInsights.fields.truncated,
                value: _isProxyTruncated,
              ),
            ],
          ),
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ) ??
                TextStyle(color: colorScheme.onSurfaceVariant),
            child: Text(
              _isProxyTruncated
                  ? context.t.attachments.content.videoInsights.detail
                      .groupedVideoHint(count: manifest.segments.length)
                  : context.t.attachments.content.videoInsights.detail
                      .derivedAssetsHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCountChip extends StatelessWidget {
  const _SummaryCountChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBoolChip extends StatelessWidget {
  const _SummaryBoolChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stateColor = value ? colorScheme.primary : colorScheme.outline;
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Icon(
                  value ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 18,
                  color: stateColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
