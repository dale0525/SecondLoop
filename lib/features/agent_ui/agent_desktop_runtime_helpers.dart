import 'package:flutter/material.dart';

extension DesktopIterableNullable<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;

  T? get lastOrNull => isEmpty ? null : last;
}

Map<String, Object?> desktopRuntimeMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return raw.map((key, value) => MapEntry('$key', value as Object?));
}

List<Map<String, Object?>> desktopRuntimeObjectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry('$key', value)))
      .toList(growable: false);
}

String? desktopRuntimeString(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    } else if (value is num || value is bool) {
      return '$value';
    }
  }
  return null;
}

int? desktopRuntimeInt(Iterable<Object?> values) {
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

String desktopRuntimeDateLabel(int ms) {
  if (ms <= 0) return 'not recorded';
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes >= 0 && diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes >= 0 && diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inHours >= 0 && diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays >= 0 && diff.inDays < 7) return '${diff.inDays}d ago';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

bool desktopRuntimeLooksLikeKind(
  Map<String, Object?> item,
  List<String> tokens,
) {
  final haystack = [
    item['kind'],
    item['type'],
    item['title'],
    item['status'],
    item['reason'],
    ...desktopRuntimeMap(item['record']).values,
  ].join(' ').toLowerCase();
  return tokens.any((token) => haystack.contains(token.toLowerCase()));
}

String desktopRuntimeTitleCase(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return '';
  return normalized
      .split(RegExp(r'\s+'))
      .map((part) => part.isEmpty
          ? part
          : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

Color desktopStatusColor(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('refused') ||
      normalized.contains('blocked') ||
      normalized.contains('unavailable')) {
    return const Color(0xFFBA1A1A);
  }
  if (normalized.contains('need') || normalized.contains('pending')) {
    return const Color(0xFF76777D);
  }
  return const Color(0xFF0051D5);
}
