import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../i18n/strings.g.dart';
import 'package:secondloop/core/models/app_models.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'attachment_detail_workspace.dart';
import 'attachment_detail_text_content.dart';
import 'attachment_text_editor_card.dart';

String normalizeAudioPlaybackMimeType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  switch (normalized) {
    case 'audio/x-m4a':
    case 'audio/m4a':
      return 'audio/mp4';
    case 'audio/x-wav':
    case 'audio/wave':
      return 'audio/wav';
    case 'audio/x-mp3':
    case 'audio/mp3':
      return 'audio/mpeg';
    case 'audio/x-ogg':
    case 'application/ogg':
      return 'audio/ogg';
    default:
      if (normalized.startsWith('audio/')) return normalized;
      return mimeType.trim();
  }
}

class AudioAttachmentPlayerView extends StatefulWidget {
  const AudioAttachmentPlayerView({
    required this.attachment,
    required this.bytes,
    required this.displayTitle,
    this.metadataFuture,
    this.initialMetadata,
    this.annotationPayloadFuture,
    this.initialAnnotationPayload,
    this.onRetryRecognition,
    this.onSaveFull,
    this.actions = const <AttachmentDetailAction>[],
    super.key,
  });

  final Attachment attachment;
  final Uint8List bytes;
  final String displayTitle;
  final Future<AttachmentMetadata?>? metadataFuture;
  final AttachmentMetadata? initialMetadata;
  final Future<Map<String, Object?>?>? annotationPayloadFuture;
  final Map<String, Object?>? initialAnnotationPayload;
  final Future<void> Function()? onRetryRecognition;
  final Future<void> Function(String value)? onSaveFull;
  final List<AttachmentDetailAction> actions;

  @override
  State<AudioAttachmentPlayerView> createState() =>
      _AudioAttachmentPlayerViewState();
}

class _AudioAttachmentPlayerViewState extends State<AudioAttachmentPlayerView> {
  late final AudioPlayer _player;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    unawaited(_loadAudio());
  }

  @override
  void didUpdateWidget(covariant AudioAttachmentPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.bytes, widget.bytes) &&
        oldWidget.attachment.sha256 == widget.attachment.sha256) {
      return;
    }
    unawaited(_loadAudio());
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _loadAudio() async {
    final normalizedMimeType =
        normalizeAudioPlaybackMimeType(widget.attachment.mimeType);
    final source = _InMemoryAudioSource(
      widget.bytes,
      contentType: normalizedMimeType,
    );
    try {
      await _player.setAudioSource(source, preload: true);
      if (!mounted) return;
      setState(() => _loadError = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekRelative(Duration delta) async {
    final pos = _player.position;
    final duration = _player.duration ?? Duration.zero;
    var target = pos + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await _player.seek(target);
  }

  static String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final hours = (totalSeconds ~/ 3600);
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  static String _speedLabel(double speed) {
    final rounded = speed.toStringAsFixed(speed % 1 == 0 ? 1 : 2);
    return t.common.labels.playbackSpeed(value: rounded);
  }

  SliderThemeData _sliderTheme(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = SlTokens.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SliderTheme.of(context).copyWith(
      trackHeight: 5,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: Color.alphaBlend(
        scheme.onSurface.withOpacity(isDark ? 0.08 : 0.05),
        tokens.surface2,
      ),
      secondaryActiveTrackColor: scheme.primary.withOpacity(
        isDark ? 0.28 : 0.2,
      ),
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withOpacity(isDark ? 0.18 : 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    );
  }

  Widget _buildPlayerCard(BuildContext context) {
    final loadError = _loadError;
    final rewindTooltip = t.common.labels.seekBackwardSeconds(seconds: 15);
    final forwardTooltip = t.common.labels.seekForwardSeconds(seconds: 15);
    if (loadError != null) {
      return SlSurface(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t.errors.loadFailed(error: '$loadError'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => unawaited(_loadAudio()),
                icon: const Icon(Icons.refresh),
                label: Text(context.t.common.actions.refresh),
              ),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SlSurface(
      key: const ValueKey('audio_attachment_player_card'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.attachment.mimeType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: rewindTooltip,
                onPressed: () => unawaited(
                  _seekRelative(const Duration(seconds: -15)),
                ),
                icon: const Icon(Icons.replay_10_rounded),
              ),
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, stateSnapshot) {
                  final state = stateSnapshot.data;
                  final isPlaying = state?.playing ?? _player.playing;
                  return IconButton.filledTonal(
                    onPressed: () => unawaited(_togglePlayPause()),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: forwardTooltip,
                onPressed: () => unawaited(
                  _seekRelative(const Duration(seconds: 15)),
                ),
                icon: const Icon(Icons.forward_10_rounded),
              ),
              const Spacer(),
              PopupMenuButton<double>(
                initialValue: _player.speed,
                tooltip: context.t.common.actions.edit,
                onSelected: (value) => unawaited(_player.setSpeed(value)),
                itemBuilder: (context) {
                  const speeds = <double>[0.75, 1.0, 1.25, 1.5, 2.0];
                  return speeds
                      .map(
                        (speed) => PopupMenuItem<double>(
                          value: speed,
                          child: Text(_speedLabel(speed)),
                        ),
                      )
                      .toList(growable: false);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: StreamBuilder<double>(
                    stream: _player.speedStream,
                    initialData: _player.speed,
                    builder: (context, speedSnapshot) {
                      final speed = speedSnapshot.data ?? 1.0;
                      return Text(_speedLabel(speed));
                    },
                  ),
                ),
              ),
            ],
          ),
          StreamBuilder<Duration?>(
            stream: _player.durationStream,
            builder: (context, durationSnapshot) {
              final duration = durationSnapshot.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, positionSnapshot) {
                  final maxMs = duration.inMilliseconds.toDouble();
                  final pos = positionSnapshot.data ?? Duration.zero;
                  final currentMs = pos.inMilliseconds
                      .toDouble()
                      .clamp(0.0, maxMs <= 0 ? 0.0 : maxMs)
                      .toDouble();
                  return Column(
                    children: [
                      SliderTheme(
                        data: _sliderTheme(context),
                        child: Slider(
                          key: const ValueKey('audio_attachment_seek_slider'),
                          value: currentMs,
                          min: 0,
                          max: maxMs <= 0 ? 1 : maxMs,
                          onChanged: maxMs <= 0
                              ? null
                              : (nextMs) => _player.seek(
                                    Duration(milliseconds: nextMs.round()),
                                  ),
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _formatDuration(pos),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Spacer(),
                          Text(
                            _formatDuration(duration),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFullSection(
    BuildContext context, {
    required Map<String, Object?>? payload,
  }) {
    final textContent = resolveAttachmentDetailTextContent(
      payload,
      mimeTypeOverride: widget.attachment.mimeType,
    );
    final fullText = textContent.full;
    final retryAction = widget.onRetryRecognition == null
        ? null
        : AttachmentTextEditorCardAction(
            id: 'regenerate',
            icon: Icons.auto_awesome_rounded,
            label: context.t.attachments.content.rerunOcr,
            tooltip: context.t.attachments.content.rerunOcr,
            buttonKey: const ValueKey('attachment_text_full_regenerate'),
            onPressed: widget.onRetryRecognition,
          );

    return AttachmentTextEditorCard(
      fieldKeyPrefix: 'attachment_text_full',
      label: context.t.attachments.content.fullText,
      showLabel: false,
      text: fullText,
      markdown: true,
      emptyText: attachmentDetailEmptyTextLabel(context),
      extraAction: retryAction,
      onSave: widget.onSaveFull,
    );
  }

  List<AttachmentDetailMetric> _buildWorkspaceMetrics(
    Map<String, Object?>? payload,
  ) {
    final metrics = <AttachmentDetailMetric>[
      AttachmentDetailMetric(
        label: context.t.attachments.workspace.metrics.type,
        value: widget.attachment.mimeType,
      ),
    ];
    final durationMs = _asInt(payload?['duration_ms']);
    if (durationMs != null && durationMs > 0) {
      metrics.add(
        AttachmentDetailMetric(
          label: context.t.attachments.workspace.metrics.duration,
          value: formatAttachmentDurationLabel(
            Duration(milliseconds: durationMs),
          ),
        ),
      );
    }
    return metrics;
  }

  List<AttachmentDetailMetadataItem> _buildMetadataItems(
    BuildContext context, {
    required AttachmentMetadata? metadata,
    required Map<String, Object?>? payload,
  }) {
    final items = <AttachmentDetailMetadataItem>[
      AttachmentDetailMetadataItem(
        label: context.t.attachments.metadata.format,
        value: widget.attachment.mimeType,
      ),
      AttachmentDetailMetadataItem(
        label: context.t.attachments.metadata.size,
        value: formatAttachmentByteSize(widget.attachment.byteLen.toInt()),
      ),
    ];

    final durationMs = _asInt(payload?['duration_ms']);
    if (durationMs != null && durationMs > 0) {
      items.add(
        AttachmentDetailMetadataItem(
          label: context.t.attachments.workspace.metadata.duration,
          value: formatAttachmentDurationLabel(
            Duration(milliseconds: durationMs),
          ),
        ),
      );
    }

    final filename =
        metadata?.filenames.isNotEmpty == true ? metadata!.filenames.first : '';
    if (filename.trim().isNotEmpty) {
      items.add(
        AttachmentDetailMetadataItem(
          label: context.t.attachments.workspace.metadata.filename,
          value: filename.trim(),
        ),
      );
    }

    final sourceUrl = metadata?.sourceUrls.isNotEmpty == true
        ? metadata!.sourceUrls.first.trim()
        : '';
    if (sourceUrl.isNotEmpty) {
      items.add(
        AttachmentDetailMetadataItem(
          label: context.t.attachments.workspace.metadata.source,
          value: sourceUrl,
        ),
      );
    }

    return items;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _buildView(
    BuildContext context, {
    required AttachmentMetadata? metadata,
    required Map<String, Object?>? payload,
  }) {
    return KeyedSubtree(
      key: const ValueKey('audio_attachment_player_view'),
      child: AttachmentDetailWorkspace(
        title: widget.displayTitle,
        typeLabel: context.t.attachments.workspace.types.audio,
        metrics: _buildWorkspaceMetrics(payload),
        preview: _buildPlayerCard(context),
        content: _buildFullSection(
          context,
          payload: payload,
        ),
        metadataItems: _buildMetadataItems(
          context,
          metadata: metadata,
          payload: payload,
        ),
        actions: widget.actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget buildWith(
      AttachmentMetadata? metadata,
      Map<String, Object?>? payload,
    ) {
      return _buildView(
        context,
        metadata: metadata,
        payload: payload,
      );
    }

    if (widget.metadataFuture == null &&
        widget.annotationPayloadFuture == null) {
      return buildWith(
        widget.initialMetadata,
        widget.initialAnnotationPayload,
      );
    }

    return FutureBuilder<AttachmentMetadata?>(
      future: widget.metadataFuture,
      initialData: widget.initialMetadata,
      builder: (context, metaSnapshot) {
        return FutureBuilder<Map<String, Object?>?>(
          future: widget.annotationPayloadFuture,
          initialData: widget.initialAnnotationPayload,
          builder: (context, payloadSnapshot) {
            return buildWith(metaSnapshot.data, payloadSnapshot.data);
          },
        );
      },
    );
  }
}

final class _InMemoryAudioSource extends StreamAudioSource {
  _InMemoryAudioSource(
    this.bytes, {
    required this.contentType,
  });

  final Uint8List bytes;
  final String contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final safeStart = (start ?? 0).clamp(0, bytes.lengthInBytes);
    final safeEnd =
        (end ?? bytes.lengthInBytes).clamp(safeStart, bytes.lengthInBytes);
    final chunk = bytes.sublist(safeStart, safeEnd);
    return StreamAudioResponse(
      sourceLength: bytes.lengthInBytes,
      contentLength: chunk.length,
      offset: safeStart,
      contentType: contentType,
      stream: Stream<List<int>>.value(chunk),
    );
  }
}
