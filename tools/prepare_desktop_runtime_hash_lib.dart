String? extractSha256FromCommandOutput(String rawOutput) {
  final normalized = rawOutput.replaceAll('\r', '\n');

  final contiguous = _sha256Contiguous.firstMatch(normalized);
  if (contiguous != null) {
    return contiguous.group(1)!.toLowerCase();
  }

  final grouped = _sha256Grouped.firstMatch(normalized);
  if (grouped != null) {
    return grouped.group(1)!.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  for (final line in normalized.split('\n')) {
    final compact = line.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(compact)) {
      return compact.toLowerCase();
    }
  }

  return null;
}

final RegExp _sha256Contiguous = RegExp(
  r'(?:^|[^0-9a-f])\\?([0-9a-f]{64})(?=$|[^0-9a-f])',
  caseSensitive: false,
  multiLine: true,
);

final RegExp _sha256Grouped = RegExp(
  r'(?:^|[^0-9a-f])\\?((?:[0-9a-f]{2}[ \t]+){31}[0-9a-f]{2})(?=$|[^0-9a-f])',
  caseSensitive: false,
  multiLine: true,
);
