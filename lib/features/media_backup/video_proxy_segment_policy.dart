import 'video_transcode_worker.dart';

final class VideoProxySegmentSelection {
  const VideoProxySegmentSelection({
    required this.segments,
    required this.totalBytes,
    required this.isTruncated,
  });

  final List<VideoTranscodeSegment> segments;
  final int totalBytes;
  final bool isTruncated;

  bool get hasSegments => segments.isNotEmpty;
}

VideoProxySegmentSelection selectVideoProxySegments(
  List<VideoTranscodeSegment> sourceSegments,
) {
  final selected = <VideoTranscodeSegment>[];
  var totalBytes = 0;

  for (final segment in sourceSegments) {
    if (segment.bytes.isEmpty) continue;
    selected.add(segment);
    totalBytes += segment.bytes.lengthInBytes;
  }

  return VideoProxySegmentSelection(
    segments: List<VideoTranscodeSegment>.unmodifiable(selected),
    totalBytes: totalBytes,
    isTruncated: false,
  );
}
