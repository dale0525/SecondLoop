class IcsGenerator {
  static String generateEvent({
    required String uid,
    required String title,
    required DateTime startUtc,
    required DateTime endUtc,
    required DateTime dtStampUtc,
  }) {
    const nl = '\r\n';
    final start = startUtc.toUtc();
    final end = endUtc.toUtc();
    final stamp = dtStampUtc.toUtc();

    final buf = StringBuffer();
    buf.write('BEGIN:VCALENDAR$nl');
    buf.write('VERSION:2.0$nl');
    buf.write('PRODID:-//SecondLoop//SecondLoop Actions//EN$nl');
    buf.write('CALSCALE:GREGORIAN$nl');
    buf.write('METHOD:PUBLISH$nl');
    buf.write('BEGIN:VEVENT$nl');
    buf.write('UID:$uid$nl');
    buf.write('DTSTAMP:${_formatUtc(stamp)}$nl');
    buf.write('DTSTART:${_formatUtc(start)}$nl');
    buf.write('DTEND:${_formatUtc(end)}$nl');
    buf.write('SUMMARY:${_escapeText(title)}$nl');
    buf.write('END:VEVENT$nl');
    buf.write('END:VCALENDAR$nl');
    return buf.toString();
  }

  static String _formatUtc(DateTime utc) {
    final dt = utc.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    String four(int v) => v.toString().padLeft(4, '0');
    return '${four(dt.year)}${two(dt.month)}${two(dt.day)}T'
        '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}Z';
  }

  static String _escapeText(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll(',', r'\,')
        .replaceAll(';', r'\;');
  }
}
