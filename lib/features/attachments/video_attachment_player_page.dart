import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../i18n/strings.g.dart';

final class VideoAttachmentPlayerPage extends StatefulWidget {
  const VideoAttachmentPlayerPage({
    required this.filePath,
    required this.displayTitle,
    this.onOpenWithSystem,
    super.key,
  });

  final String filePath;
  final String displayTitle;
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

  @override
  void initState() {
    super.initState();
    _initializeController();
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

  void _initializeController() {
    final file = File(widget.filePath);
    final controller = VideoPlayerController.file(file);
    final future = controller.initialize().then((_) {
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

  Future<void> _retryInitialize() async {
    final controller = _controller;
    if (controller != null) {
      await controller.dispose();
    }
    if (!mounted) return;
    _initializeController();
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
