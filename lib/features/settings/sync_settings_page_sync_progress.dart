part of 'sync_settings_page.dart';

Future<int> _consumeRustProgressStream(
  Stream<String> stream, {
  required void Function(int done, int total) onProgress,
}) async {
  var count = 0;
  await for (final msg in stream) {
    Map<String, dynamic>? ev;
    try {
      final decoded = jsonDecode(msg);
      ev = decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      ev = null;
    }
    if (ev == null) continue;

    final type = ev['type'];
    if (type == 'progress') {
      final done = (ev['done'] as num?)?.toInt();
      final total = (ev['total'] as num?)?.toInt();
      if (done != null && total != null) {
        onProgress(done, total);
      }
    } else if (type == 'result') {
      final v = (ev['count'] as num?)?.toInt();
      if (v != null) count = v;
    }
  }
  return count;
}
