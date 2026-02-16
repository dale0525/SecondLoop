import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'video_attachment_inline_player.dart';
import 'video_proxy_open_helper.dart';

typedef VideoManifestBytesLoader = Future<Uint8List?> Function(String sha256);

enum VideoManifestGalleryEntryType {
  proxy,
  keyframe,
}

final class VideoManifestGalleryEntry {
  const VideoManifestGalleryEntry.proxy({
    required this.playbackFuture,
    this.posterSha256,
  })  : type = VideoManifestGalleryEntryType.proxy,
        keyframeSha256 = null;

  const VideoManifestGalleryEntry.keyframe({
    required this.keyframeSha256,
  })  : type = VideoManifestGalleryEntryType.keyframe,
        playbackFuture = null,
        posterSha256 = null;

  final VideoManifestGalleryEntryType type;
  final Future<PreparedVideoProxyPlayback>? playbackFuture;
  final String? posterSha256;
  final String? keyframeSha256;
}

Future<void> showVideoManifestGalleryDialog(
  BuildContext context, {
  required List<VideoManifestGalleryEntry> entries,
  required int initialIndex,
  required VideoManifestBytesLoader loadBytes,
}) async {
  if (entries.isEmpty) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.82),
    builder: (dialogContext) {
      return VideoManifestGalleryDialog(
        entries: entries,
        initialIndex: initialIndex,
        loadBytes: loadBytes,
      );
    },
  );
}

class VideoManifestGalleryDialog extends StatefulWidget {
  const VideoManifestGalleryDialog({
    required this.entries,
    required this.initialIndex,
    required this.loadBytes,
    super.key,
  });

  final List<VideoManifestGalleryEntry> entries;
  final int initialIndex;
  final VideoManifestBytesLoader loadBytes;

  @override
  State<VideoManifestGalleryDialog> createState() =>
      _VideoManifestGalleryDialogState();
}

class _VideoManifestGalleryDialogState
    extends State<VideoManifestGalleryDialog> {
  static const int _loopFactor = 10000;
  static const Duration _pageAnimationDuration = Duration(milliseconds: 240);
  static const Curve _pageAnimationCurve = Curves.easeOutCubic;

  final Map<String, Future<Uint8List?>> _bytesBySha =
      <String, Future<Uint8List?>>{};

  late final PageController _controller;
  late int _rawPage;

  int get _entryCount => widget.entries.length;

  int get _normalizedIndex {
    if (_entryCount <= 0) return 0;
    final value = _rawPage % _entryCount;
    return value < 0 ? value + _entryCount : value;
  }

  Future<Uint8List?> _loadBytesBySha(String sha256) {
    final normalizedSha = sha256.trim();
    if (normalizedSha.isEmpty) {
      return Future<Uint8List?>.value(null);
    }

    return _bytesBySha.putIfAbsent(
      normalizedSha,
      () => widget.loadBytes(normalizedSha),
    );
  }

  @override
  void initState() {
    super.initState();
    final safeInitial =
        _entryCount <= 0 ? 0 : widget.initialIndex.clamp(0, _entryCount - 1);
    _rawPage = _entryCount <= 0 ? 0 : _entryCount * _loopFactor + safeInitial;
    _controller = PageController(initialPage: _rawPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _navigateByOffset(int offset) async {
    if (_entryCount <= 1 || !_controller.hasClients) return;
    final targetPage = _rawPage + offset;
    await _controller.animateToPage(
      targetPage,
      duration: _pageAnimationDuration,
      curve: _pageAnimationCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_entryCount <= 0) return const SizedBox.shrink();

    final mediaSize = MediaQuery.of(context).size;

    return Dialog(
      key: const ValueKey('video_manifest_gallery_dialog'),
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: GestureDetector(
        onTap: () {},
        child: SizedBox(
          width: mediaSize.width,
          height: mediaSize.height * 0.82,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  key: const ValueKey('video_manifest_gallery_page_view'),
                  controller: _controller,
                  onPageChanged: (page) {
                    if (!mounted) return;
                    setState(() {
                      _rawPage = page;
                    });
                  },
                  itemBuilder: (context, page) {
                    final entry = widget.entries[page % _entryCount];
                    return _buildGalleryEntry(entry);
                  },
                ),
              ),
              if (_entryCount > 1)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildNavButton(
                      key: const ValueKey('video_manifest_gallery_prev_button'),
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _navigateByOffset(-1),
                    ),
                  ),
                ),
              if (_entryCount > 1)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildNavButton(
                      key: const ValueKey('video_manifest_gallery_next_button'),
                      icon: Icons.chevron_right_rounded,
                      onTap: () => _navigateByOffset(1),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  key: const ValueKey('video_manifest_gallery_close_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Text(
                        _buildIndexLabel(),
                        key: const ValueKey(
                          'video_manifest_gallery_index_indicator',
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildIndexLabel() {
    final current = _normalizedIndex + 1;
    return '$current/$_entryCount';
  }

  Widget _buildNavButton({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withOpacity(0.42),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryEntry(VideoManifestGalleryEntry entry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 28, 8, 36),
        child: switch (entry.type) {
          VideoManifestGalleryEntryType.proxy => _buildProxyEntry(entry),
          VideoManifestGalleryEntryType.keyframe => _buildKeyframeEntry(entry),
        },
      ),
    );
  }

  Widget _buildProxyEntry(VideoManifestGalleryEntry entry) {
    final playbackFuture = entry.playbackFuture;
    if (playbackFuture == null) {
      return _buildGalleryFrame(_buildProxyFallback(posterBytes: null));
    }

    final posterSha = (entry.posterSha256 ?? '').trim();
    final posterFuture = posterSha.isEmpty
        ? Future<Uint8List?>.value(null)
        : _loadBytesBySha(posterSha);

    return FutureBuilder<PreparedVideoProxyPlayback>(
      future: playbackFuture,
      builder: (context, playbackSnapshot) {
        return FutureBuilder<Uint8List?>(
          future: posterFuture,
          builder: (context, posterSnapshot) {
            final playback = playbackSnapshot.data;
            if (playback != null && playback.hasSegments) {
              return _buildGalleryFrame(
                VideoAttachmentInlinePlayer(
                  playback: playback,
                  posterBytes: posterSnapshot.data,
                ),
              );
            }
            return _buildGalleryFrame(
              _buildProxyFallback(
                posterBytes: posterSnapshot.data,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildKeyframeEntry(VideoManifestGalleryEntry entry) {
    final sha256 = (entry.keyframeSha256 ?? '').trim();
    if (sha256.isEmpty) {
      return _buildGalleryFrame(
        const Center(child: Icon(Icons.image_not_supported_outlined, size: 36)),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _loadBytesBySha(sha256),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _buildGalleryFrame(
            const Center(child: Icon(Icons.image_outlined, size: 36)),
          );
        }

        return _buildGalleryFrame(
          Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }

  Widget _buildProxyFallback({Uint8List? posterBytes}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (posterBytes != null && posterBytes.isNotEmpty)
          Image.memory(
            posterBytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          )
        else
          const ColoredBox(color: Colors.black26),
        Container(color: Colors.black.withOpacity(0.22)),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryFrame(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black.withOpacity(0.16),
        child: Center(child: child),
      ),
    );
  }
}
