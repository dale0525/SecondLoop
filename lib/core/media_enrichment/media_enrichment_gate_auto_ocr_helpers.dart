part of 'media_enrichment_gate.dart';

String _firstNonEmptyForAutoOcr(List<String> values) {
  for (final raw in values) {
    final value = raw.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _joinNonEmptyBlocksForAutoOcr(List<String> parts) {
  final values = parts
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (values.isEmpty) return '';
  return values.join('\n\n');
}

String _truncateUtf8ForAutoOcr(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return text;
  if (maxBytes <= 0) return '';
  var end = maxBytes;
  while (end > 0 && (bytes[end - 1] & 0xC0) == 0x80) {
    end -= 1;
  }
  if (end <= 0) return '';
  return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
}

String _dominantStringForAutoOcr(List<String> values) {
  if (values.isEmpty) return '';
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  String winner = '';
  var bestCount = -1;
  counts.forEach((value, count) {
    if (count > bestCount) {
      winner = value;
      bestCount = count;
    }
  });
  return winner;
}
