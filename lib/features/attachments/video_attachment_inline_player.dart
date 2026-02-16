import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
  static const Duration _controlsHideDelay = Duration(seconds: 3);
  static const List<double> _volumeOptions = <double>[0, 0.25, 0.5, 0.75, 1];
  static const List<double> _speedOptions = <double>[
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    2
  ];

  VideoPlayerController? _controller;
  VideoPlayerController? _listenedController;
  Future<void>? _initializeFuture;
  Object? _initError;
  var _selectedSegmentIndex = 0;
  var _showPosterOverlay = true;
  var _controlsVisible = true;
  var _selectedVolume = 1.0;
  var _selectedSpeed = 1.0;
  var _lastKnownPlayingState = false;
  Duration? _dragPreviewPosition;
  Timer? _controlsHideTimer;

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
    _controlsVisible = true;
    _dragPreviewPosition = null;
    unawaited(_reinitializeSegment());
  }

  @override
  void dispose() {
    _cancelControlsHideTimer();
    _detachControllerListener(_listenedController);
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

  void _attachControllerListener(VideoPlayerController controller) {
    _detachControllerListener(_listenedController);
    _listenedController = controller;
    _lastKnownPlayingState = controller.value.isPlaying;
    controller.addListener(_handleControllerValueChanged);
  }

  void _detachControllerListener(VideoPlayerController? controller) {
    if (controller == null) return;
    controller.removeListener(_handleControllerValueChanged);
    if (identical(_listenedController, controller)) {
      _listenedController = null;
    }
  }

  void _handleControllerValueChanged() {
    final controller = _listenedController;
    if (!mounted || controller == null) return;

    final isPlaying = controller.value.isPlaying;
    if (isPlaying == _lastKnownPlayingState) return;
    _lastKnownPlayingState = isPlaying;

    if (isPlaying) {
      if (_showPosterOverlay || !_controlsVisible) {
        setState(() {
          _showPosterOverlay = false;
          _controlsVisible = true;
        });
      }
      _scheduleControlsAutoHide(controller);
      return;
    }

    _cancelControlsHideTimer();
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
  }

  void _cancelControlsHideTimer() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
  }

  void _scheduleControlsAutoHide(VideoPlayerController controller) {
    _cancelControlsHideTimer();
    if (!controller.value.isPlaying) return;
    _controlsHideTimer = Timer(_controlsHideDelay, () {
      if (!mounted || !controller.value.isPlaying || !_controlsVisible) {
        return;
      }
      setState(() {
        _controlsVisible = false;
      });
    });
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
    _attachControllerListener(controller);

    final future = controller.initialize().then((_) async {
      await controller.setVolume(_selectedVolume);
      await controller.setPlaybackSpeed(_selectedSpeed);
      if (autoPlay) {
        await controller.play();
      }
      if (!mounted) return;
      setState(() {
        _initError = null;
        _showPosterOverlay = !autoPlay;
        _controlsVisible = true;
        _dragPreviewPosition = null;
      });
      if (autoPlay) {
        _scheduleControlsAutoHide(controller);
      }
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
    _cancelControlsHideTimer();
    _dragPreviewPosition = null;
    final old = _controller;
    _controller = null;
    _initializeFuture = null;
    _detachControllerListener(old);
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
      _controlsVisible = true;
      _dragPreviewPosition = null;
    });
    await _reinitializeSegment(autoPlay: wasPlaying);
  }

  Future<void> _togglePlayPause(VideoPlayerController controller) async {
    if (controller.value.isPlaying) {
      await controller.pause();
      if (!mounted) return;
      _cancelControlsHideTimer();
      setState(() {
        _controlsVisible = true;
      });
      return;
    }

    await controller.play();
    if (!mounted) return;
    setState(() {
      _showPosterOverlay = false;
      _controlsVisible = true;
    });
    _scheduleControlsAutoHide(controller);
  }

  void _handleSurfaceTap(
    VideoPlayerController controller,
    VideoPlayerValue value,
  ) {
    if (!value.isInitialized) return;
    if (!value.isPlaying) {
      unawaited(_togglePlayPause(controller));
      return;
    }

    if (_controlsVisible) {
      _cancelControlsHideTimer();
      setState(() {
        _controlsVisible = false;
      });
      return;
    }

    setState(() {
      _controlsVisible = true;
    });
    _scheduleControlsAutoHide(controller);
  }

  Future<void> _seekTo(
    VideoPlayerController controller,
    Duration target,
  ) async {
    final duration = controller.value.duration;
    var safeTarget = target;
    if (safeTarget < Duration.zero) safeTarget = Duration.zero;
    if (duration > Duration.zero && safeTarget > duration) {
      safeTarget = duration;
    }
    await controller.seekTo(safeTarget);
    if (!mounted) return;
    setState(() {
      _dragPreviewPosition = null;
    });
    if (controller.value.isPlaying) {
      _scheduleControlsAutoHide(controller);
    }
  }

  Future<void> _setVolume(
    VideoPlayerController controller,
    double volume,
  ) async {
    final normalized = volume.clamp(0.0, 1.0).toDouble();
    await controller.setVolume(normalized);
    if (!mounted) return;
    setState(() {
      _selectedVolume = normalized;
    });
    if (controller.value.isPlaying) {
      _scheduleControlsAutoHide(controller);
    }
  }

  Future<void> _setPlaybackSpeed(
    VideoPlayerController controller,
    double speed,
  ) async {
    final normalized = speed.clamp(0.25, 4.0).toDouble();
    await controller.setPlaybackSpeed(normalized);
    if (!mounted) return;
    setState(() {
      _selectedSpeed = normalized;
    });
    if (controller.value.isPlaying) {
      _scheduleControlsAutoHide(controller);
    }
  }

  String _formatDuration(Duration value) {
    final safe = value < Duration.zero ? Duration.zero : value;
    final totalSeconds = safe.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatSpeed(double speed) {
    var value = speed.toStringAsFixed(2);
    value = value.replaceFirst(RegExp(r'0+$'), '');
    value = value.replaceFirst(RegExp(r'\.$'), '');
    return value;
  }

  IconData _volumeIconForLevel(double volume) {
    if (volume <= 0.01) return Icons.volume_off_rounded;
    if (volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
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

        final mediaBox = AspectRatio(
          aspectRatio: aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: initialized
                  ? ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        return _buildPlayerSurface(
                          controller: controller,
                          value: value,
                          poster: poster,
                        );
                      },
                    )
                  : _buildUnavailableView(
                      showProgress:
                          snapshot.connectionState == ConnectionState.waiting,
                      poster: poster,
                    ),
            ),
          ),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.hasBoundedHeight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_segments.length > 1) _buildSegmentSelector(),
                  Expanded(
                    child: Center(child: mediaBox),
                  ),
                ],
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_segments.length > 1) _buildSegmentSelector(),
                mediaBox,
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerSurface({
    required VideoPlayerController controller,
    required VideoPlayerValue value,
    required Uint8List? poster,
  }) {
    final showControls = _controlsVisible || !value.isPlaying;
    return Stack(
      fit: StackFit.expand,
      children: [
        VideoPlayer(controller),
        if (poster != null &&
            poster.isNotEmpty &&
            _showPosterOverlay &&
            !value.isPlaying)
          Image.memory(
            poster,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleSurfaceTap(controller, value),
            child: const SizedBox.expand(),
          ),
        ),
        if (!value.isPlaying)
          Center(
            child: Material(
              color: Colors.black.withOpacity(0.48),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('video_inline_player_center_play_button'),
                onTap: () => unawaited(_togglePlayPause(controller)),
                child: const SizedBox(
                  width: 68,
                  height: 68,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            ),
          ),
        if (showControls)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildControlsBar(controller: controller, value: value),
          ),
      ],
    );
  }

  Widget _buildControlsBar({
    required VideoPlayerController controller,
    required VideoPlayerValue value,
  }) {
    final actualDuration =
        value.duration > Duration.zero ? value.duration : Duration.zero;
    final sliderMaxDuration = actualDuration > Duration.zero
        ? actualDuration
        : const Duration(milliseconds: 1);

    final previewPosition = _dragPreviewPosition ?? value.position;
    final clampedPreview = previewPosition < Duration.zero
        ? Duration.zero
        : (previewPosition > sliderMaxDuration
            ? sliderMaxDuration
            : previewPosition);
    final clampedPosition = clampedPreview.inMilliseconds.toDouble();
    final maxMillis = math.max(sliderMaxDuration.inMilliseconds, 1).toDouble();
    final currentPositionLabel =
        _formatDuration(Duration(milliseconds: clampedPosition.round()));
    final totalDurationLabel = _formatDuration(actualDuration);
    final timeLabel = '$currentPositionLabel / $totalDurationLabel';
    final speedLabel = '${_formatSpeed(_selectedSpeed)}x';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0),
            Colors.black.withOpacity(0.7),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 20,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.8,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  key: const ValueKey('video_inline_player_seek_slider'),
                  value: clampedPosition,
                  min: 0,
                  max: maxMillis,
                  onChangeStart: (_) {
                    _cancelControlsHideTimer();
                  },
                  onChanged: (next) {
                    setState(() {
                      _dragPreviewPosition =
                          Duration(milliseconds: next.round());
                    });
                  },
                  onChangeEnd: (next) {
                    final target = Duration(milliseconds: next.round());
                    unawaited(_seekTo(controller, target));
                  },
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('video_inline_player_play_pause_button'),
                  onPressed: () => unawaited(_togglePlayPause(controller)),
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Text(
                    timeLabel,
                    key: const ValueKey('video_inline_player_time_label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withOpacity(0.92),
                        ),
                  ),
                ),
                PopupMenuButton<double>(
                  key: const ValueKey('video_inline_player_volume_button'),
                  initialValue: _selectedVolume,
                  tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                  onOpened: _cancelControlsHideTimer,
                  onCanceled: () {
                    if (controller.value.isPlaying) {
                      _scheduleControlsAutoHide(controller);
                    }
                  },
                  onSelected: (next) => unawaited(_setVolume(controller, next)),
                  itemBuilder: (context) {
                    return _volumeOptions.map((option) {
                      final optionLabel = '${(option * 100).round()}%';
                      return PopupMenuItem<double>(
                        value: option,
                        child: Text(optionLabel),
                      );
                    }).toList(growable: false);
                  },
                  icon: Icon(
                    _volumeIconForLevel(_selectedVolume),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                PopupMenuButton<double>(
                  key: const ValueKey('video_inline_player_speed_button'),
                  initialValue: _selectedSpeed,
                  tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                  onOpened: _cancelControlsHideTimer,
                  onCanceled: () {
                    if (controller.value.isPlaying) {
                      _scheduleControlsAutoHide(controller);
                    }
                  },
                  onSelected: (next) =>
                      unawaited(_setPlaybackSpeed(controller, next)),
                  itemBuilder: (context) {
                    return _speedOptions.map((option) {
                      final optionLabel = '${_formatSpeed(option)}x';
                      return PopupMenuItem<double>(
                        value: option,
                        child: Text(optionLabel),
                      );
                    }).toList(growable: false);
                  },
                  icon: Text(
                    speedLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
