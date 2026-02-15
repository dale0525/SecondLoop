import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'video_attachment_player_page.dart';
import 'video_proxy_open_helper.dart';

class VideoAttachmentInlinePlayer extends StatefulWidget {
  const VideoAttachmentInlinePlayer({
    required this.playback,
    this.posterBytes,
    this.fallbackAspectRatio = 16 / 9,
    super.key,
  });

  final PreparedVideoProxyPlayback playback;
  final Uint8List? posterBytes;
  final double fallbackAspectRatio;

  @override
  State<VideoAttachmentInlinePlayer> createState() =>
      _VideoAttachmentInlinePlayerState();
}

class _VideoAttachmentInlinePlayerState
    extends State<VideoAttachmentInlinePlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  Object? _initError;
  var _selectedSegmentIndex = 0;
  var _showPosterOverlay = true;

  List<VideoAttachmentPlayerSegment> get _segments =>
      widget.playback.segmentFiles;

  @override
  void initState() {
    super.initState();
    _selectedSegmentIndex =
        _normalizeIndex(widget.playback.initialSegmentIndex);
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant VideoAttachmentInlinePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.playback, widget.playback)) return;
    _selectedSegmentIndex =
        _normalizeIndex(widget.playback.initialSegmentIndex);
    _showPosterOverlay = true;
    unawaited(_reinitializeSegment());
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    _initializeFuture = null;
    if (controller != null) {
      controller.dispose();
    }
    super.dispose();
  }

  int _normalizeIndex(int value) {
    if (_segments.isEmpty) return 0;
    if (value < 0) return 0;
    if (value >= _segments.length) return _segments.length - 1;
    return value;
  }

  void _initializeController({bool autoPlay = false}) {
    if (_segments.isEmpty) {
      setState(() {
        _controller = null;
        _initializeFuture = null;
        _initError = StateError('video_segments_empty');
      });
      return;
    }

    final segment = _segments[_selectedSegmentIndex];
    final controller = VideoPlayerController.file(File(segment.filePath));
    final future = controller.initialize().then((_) async {
      if (autoPlay) {
        await controller.play();
      }
      if (!mounted) return;
      setState(() {
        _initError = null;
      });
    }).catchError((error) {
      if (!mounted) return;
      setState(() {
        _initError = error;
      });
    });

    setState(() {
      _controller = controller;
      _initializeFuture = future;
      _initError = null;
    });
  }

  Future<void> _reinitializeSegment({bool autoPlay = false}) async {
    final old = _controller;
    _controller = null;
    _initializeFuture = null;
    if (mounted) {
      setState(() {});
    }
    if (old != null) {
      await old.dispose();
    }
    if (!mounted) return;
    _initializeController(autoPlay: autoPlay);
  }

  Future<void> _switchSegment(int index) async {
    if (_segments.length <= 1) return;
    final nextIndex = _normalizeIndex(index);
    if (nextIndex == _selectedSegmentIndex) return;
    final wasPlaying = _controller?.value.isPlaying ?? false;
    setState(() {
      _selectedSegmentIndex = nextIndex;
      _showPosterOverlay = true;
    });
    await _reinitializeSegment(autoPlay: wasPlaying);
  }

  Future<void> _togglePlayPause(VideoPlayerController controller) async {
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
      _showPosterOverlay = false;
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initializeFuture = _initializeFuture;
    if (controller == null || initializeFuture == null) {
      return _buildUnavailableView();
    }

    final poster = widget.posterBytes;

    return FutureBuilder<void>(
      future: initializeFuture,
      builder: (context, snapshot) {
        final initialized = snapshot.connectionState == ConnectionState.done &&
            _initError == null &&
            !snapshot.hasError &&
            controller.value.isInitialized;
        final aspectRatio = initialized && controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : widget.fallbackAspectRatio;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_segments.length > 1) _buildSegmentSelector(),
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: initialized
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            VideoPlayer(controller),
                            if (poster != null &&
                                poster.isNotEmpty &&
                                _showPosterOverlay &&
                                !controller.value.isPlaying)
                              Image.memory(
                                poster,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            _buildTapOverlay(controller),
                          ],
                        )
                      : _buildUnavailableView(
                          showProgress: snapshot.connectionState ==
                              ConnectionState.waiting,
                          poster: poster,
                        ),
                ),
              ),
            ),
            if (initialized)
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSegmentSelector() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        key: const ValueKey('video_inline_player_segment_selector'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        itemBuilder: (context, index) {
          return ChoiceChip(
            key: ValueKey('video_inline_player_segment_chip_$index'),
            selected: index == _selectedSegmentIndex,
            onSelected: (_) => unawaited(_switchSegment(index)),
            label: Text((index + 1).toString()),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _segments.length,
      ),
    );
  }

  Widget _buildTapOverlay(VideoPlayerController controller) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(_togglePlayPause(controller)),
        child: Center(
          child: Icon(
            controller.value.isPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded,
            size: 64,
            color: Colors.white.withOpacity(0.92),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailableView({
    bool showProgress = false,
    Uint8List? poster,
  }) {
    if (poster != null && poster.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            poster,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          if (showProgress)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
        ],
      );
    }

    return Center(
      child: Icon(
        Icons.smart_display_outlined,
        size: 32,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
