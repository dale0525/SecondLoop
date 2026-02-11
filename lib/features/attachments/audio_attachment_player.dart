import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';

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
    this.metadataFuture,
    this.initialMetadata,
    this.annotationPayloadFuture,
    this.initialAnnotationPayload,
    this.onRetryRecognition,
    super.key,
  });

  final Attachment attachment;
  final Uint8List bytes;
  final Future<AttachmentMetadata?>? metadataFuture;
  final AttachmentMetadata? initialMetadata;
  final Future<Map<String, Object?>?>? annotationPayloadFuture;
  final Map<String, Object?>? initialAnnotationPayload;
  final Future<void> Function()? onRetryRecognition;

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
    return '${rounded}x';
  }

  Future<void> _openFullTextDialog(
    BuildContext context, {
    required String title,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
            child: SingleChildScrollView(
              child: SelectableText(text),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.t.common.actions.cancel),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayerCard(BuildContext context) {
    final loadError = _loadError;
    const rewindTooltip = '-15s';
    const forwardTooltip = '+15s';
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

    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      Slider(
                        value: currentMs,
                        min: 0,
                        max: maxMs <= 0 ? 1 : maxMs,
                        onChanged: maxMs <= 0
                            ? null
                            : (nextMs) => _player.seek(
                                  Duration(milliseconds: nextMs.round()),
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

  Widget _buildTranscriptCard(
    BuildContext context, {
    required Map<String, Object?>? payload,
    required Future<void> Function()? onRetryRecognition,
  }) {
    final transcriptTitle = context.t.attachments.content.fullText;
    final transcriptExcerpt = payload?['transcript_excerpt']?.toString().trim();
    final transcriptFull = payload?['transcript_full']?.toString().trim();
    final durationMsValue = payload?['duration_ms'];
    final durationMs = durationMsValue is num ? durationMsValue.toInt() : null;

    if ((transcriptExcerpt ?? '').isEmpty && (transcriptFull ?? '').isEmpty) {
      return SlSurface(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              context.t.sync.progressDialog.preparing,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final displayed = (transcriptExcerpt ?? transcriptFull ?? '').trim();
    final full = (transcriptFull ?? '').trim();
    final canOpenFull = full.isNotEmpty && full.length > displayed.length;

    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            transcriptTitle,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          if (durationMs != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatDuration(Duration(milliseconds: durationMs)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          SelectableText(
            displayed,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onRetryRecognition != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('attachment_transcript_retry'),
                onPressed: () => unawaited(onRetryRecognition()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.t.common.actions.retry),
              ),
            ),
          ],
          if (canOpenFull) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => unawaited(
                  _openFullTextDialog(
                    context,
                    title: transcriptTitle,
                    text: full,
                  ),
                ),
                icon: const Icon(Icons.open_in_new_outlined, size: 18),
                label: Text(context.t.common.actions.open),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildView(
    BuildContext context, {
    required AttachmentMetadata? metadata,
    required Map<String, Object?>? payload,
  }) {
    final title = (metadata?.title ?? payload?['title'])?.toString().trim();

    return Center(
      key: const ValueKey('audio_attachment_player_view'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((title ?? '').isNotEmpty) ...[
                SlSurface(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _buildPlayerCard(context),
              const SizedBox(height: 12),
              _buildTranscriptCard(
                context,
                payload: payload,
                onRetryRecognition: widget.onRetryRecognition,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget buildWith(
      AttachmentMetadata? meta,
      Map<String, Object?>? payload,
    ) {
      return _buildView(
        context,
        metadata: meta,
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
