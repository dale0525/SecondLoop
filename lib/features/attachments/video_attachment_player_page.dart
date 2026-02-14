import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../i18n/strings.g.dart';

final class VideoAttachmentPlayerSegment {
  const VideoAttachmentPlayerSegment({
    required this.filePath,
    required this.sha256,
    required this.mimeType,
  });

  final String filePath;
  final String sha256;
  final String mimeType;
}

final class VideoAttachmentPlayerPage extends StatefulWidget {
  const VideoAttachmentPlayerPage({
    required this.displayTitle,
    required this.segmentFiles,
    this.initialSegmentIndex = 0,
    this.onOpenWithSystem,
    super.key,
  });

  final String displayTitle;
  final List<VideoAttachmentPlayerSegment> segmentFiles;
  final int initialSegmentIndex;
  final Future<void> Function()? onOpenWithSystem;

  @override
  State<VideoAttachmentPlayerPage> createState() =>
      _VideoAttachmentPlayerPageState();
}

final class _VideoAttachmentPlayerPageState
    extends State<VideoAttachmentPlayerPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  Object? _initError;
  late int _selectedSegmentIndex;

  List<VideoAttachmentPlayerSegment> get _segments => widget.segmentFiles;

  @override
  void initState() {
    super.initState();
    _selectedSegmentIndex = _normalizeIndex(widget.initialSegmentIndex);
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant VideoAttachmentPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.segmentFiles, widget.segmentFiles)) return;
    _selectedSegmentIndex = _normalizeIndex(_selectedSegmentIndex);
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
    final file = File(segment.filePath);
    final controller = VideoPlayerController.file(file);
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
    });
    await _reinitializeSegment(autoPlay: wasPlaying);
  }

  Future<void> _retryInitialize() async {
    await _reinitializeSegment();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.displayTitle.trim();
    final pageTitle = title.isEmpty ? context.t.common.actions.open : title;

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          if (widget.onOpenWithSystem != null)
            IconButton(
              onPressed: () => widget.onOpenWithSystem!.call(),
              tooltip: context.t.attachments.content.openWithSystem,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final controller = _controller;
    final initializeFuture = _initializeFuture;

    if (controller == null || initializeFuture == null) {
      return _buildUnavailableView(context);
    }

    return FutureBuilder<void>(
      future: initializeFuture,
      builder: (context, snapshot) {
        if (_initError != null || snapshot.hasError) {
          return _buildUnavailableView(context);
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        final aspectRatio = controller.value.aspectRatio <= 0
            ? (16 / 9)
            : controller.value.aspectRatio;

        return Column(
          children: [
            if (_segments.length > 1) _buildSegmentSelector(),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPlayer(controller),
                      _buildTapOverlay(controller),
                    ],
                  ),
                ),
              ),
            ),
            VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSegmentSelector() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        key: const ValueKey('video_player_segment_selector'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemBuilder: (context, index) {
          return ChoiceChip(
            key: ValueKey('video_player_segment_chip_$index'),
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
        onTap: () async {
          if (controller.value.isPlaying) {
            await controller.pause();
          } else {
            await controller.play();
          }
          if (!mounted) return;
          setState(() {});
        },
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

  Widget _buildUnavailableView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_display_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              context.t.attachments.content.previewUnavailable,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _retryInitialize,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.t.common.actions.retry),
                ),
                if (widget.onOpenWithSystem != null)
                  OutlinedButton.icon(
                    onPressed: () => widget.onOpenWithSystem!.call(),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(context.t.attachments.content.openWithSystem),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
