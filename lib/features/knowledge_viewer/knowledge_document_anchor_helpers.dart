import '../../src/rust/knowledge/models.dart';

String formatKnowledgeAnchorTimeRange(KnowledgeAnchorSet anchors) {
  final start = anchors.startMs?.toInt();
  final end = anchors.endMs?.toInt();
  if (start == null && end == null) return '';
  if (start != null && end != null) {
    return '${_formatKnowledgeClock(start)}–${_formatKnowledgeClock(end)}';
  }
  if (start != null) return _formatKnowledgeClock(start);
  return _formatKnowledgeClock(end!);
}

String _formatKnowledgeClock(int ms) {
  final totalSeconds = (ms / 1000).floor();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

List<String> knowledgeAnchorLabels(KnowledgeAnchorSet anchors) {
  final labels = <String>[];
  final sectionLabel = anchors.sectionLabel?.trim() ?? '';
  final speaker = anchors.speaker?.trim() ?? '';
  if (sectionLabel.isNotEmpty) labels.add(sectionLabel);
  if (speaker.isNotEmpty) labels.add(speaker);
  if (anchors.pageIndex != null) {
    labels.add('P${anchors.pageIndex!.toInt() + 1}');
  }
  if (anchors.frameIndex != null) {
    labels.add('F${anchors.frameIndex!.toInt() + 1}');
  }
  final timeRange = formatKnowledgeAnchorTimeRange(anchors);
  if (timeRange.isNotEmpty) labels.add(timeRange);
  return labels;
}
