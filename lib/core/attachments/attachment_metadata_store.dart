import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/models/app_models.dart';

abstract class AttachmentMetadataStore {
  Future<AttachmentMetadata?> read(
    Uint8List key, {
    required String attachmentSha256,
  });

  Future<void> upsert(
    Uint8List key, {
    required String attachmentSha256,
    String? title,
    List<String> filenames = const <String>[],
    List<String> sourceUrls = const <String>[],
  });
}

final class DartAttachmentMetadataStore implements AttachmentMetadataStore {
  const DartAttachmentMetadataStore();

  static final Map<String, String> _memoryStore = <String, String>{};

  @override
  Future<AttachmentMetadata?> read(
    Uint8List key, {
    required String attachmentSha256,
  }) async {
    final encoded = await _read(_preferenceKey(key, attachmentSha256));
    if (encoded == null) return null;
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return null;
    final json = decoded.map((key, value) => MapEntry('$key', value));
    return AttachmentMetadata(
      title: json['title'] as String?,
      filenames: _stringList(json['filenames']),
      sourceUrls: _stringList(json['source_urls']),
      titleUpdatedAtMs: (json['title_updated_at_ms'] as num?)?.toInt() ?? 0,
      createdAtMs: (json['created_at_ms'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updated_at_ms'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> upsert(
    Uint8List key, {
    required String attachmentSha256,
    String? title,
    List<String> filenames = const <String>[],
    List<String> sourceUrls = const <String>[],
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final existing = await read(key, attachmentSha256: attachmentSha256);
    final createdAtMs = existing?.createdAtMs ?? nowMs;
    final titleUpdatedAtMs = title == existing?.title
        ? (existing?.titleUpdatedAtMs ?? nowMs)
        : nowMs;
    await _write(
      _preferenceKey(key, attachmentSha256),
      jsonEncode(<String, Object?>{
        'title': title,
        'filenames': filenames,
        'source_urls': sourceUrls,
        'title_updated_at_ms': titleUpdatedAtMs,
        'created_at_ms': createdAtMs,
        'updated_at_ms': nowMs,
      }),
    );
  }

  static String _preferenceKey(Uint8List key, String attachmentSha256) {
    final session = base64Url.encode(key.take(12).toList());
    return 'secondloop.attachment_metadata.$session.${Uri.encodeComponent(attachmentSha256)}';
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.map((item) => '$item').toList(growable: false);
  }

  static Future<String?> _read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return _memoryStore[key];
    }
  }

  static Future<void> _write(String key, String value) async {
    _memoryStore[key] = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }
}
