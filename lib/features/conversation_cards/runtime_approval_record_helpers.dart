List<Map<String, Object?>> runtimeApprovalObjectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map((item) =>
          item.map((key, value) => MapEntry('$key', value as Object?)))
      .toList(growable: false);
}

Map<String, Object?> runtimeApprovalObjectMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return raw.map((key, value) => MapEntry('$key', value as Object?));
}

String? runtimeApprovalFirstString(List<Object?> values) {
  for (final value in values) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    } else if (value is num) {
      return '$value';
    }
  }
  return null;
}

int? runtimeApprovalFirstInt(List<Object?> values) {
  for (final value in values) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

List<String> runtimeApprovalStringList(Object? raw) {
  if (raw is List) {
    return raw
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final single = runtimeApprovalFirstString([raw]);
  if (single == null) return const <String>[];
  return single
      .split(RegExp(r'[,;，、]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
