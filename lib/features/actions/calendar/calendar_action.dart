import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ics_generator.dart';

class CalendarAction {
  static Future<File> writeEventIcsFile({
    required String uid,
    required String title,
    required DateTime startUtc,
    required DateTime endUtc,
    DateTime? dtStampUtc,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/secondloop-event-$uid.ics');
    final ics = IcsGenerator.generateEvent(
      uid: uid,
      title: title,
      startUtc: startUtc,
      endUtc: endUtc,
      dtStampUtc: dtStampUtc ?? DateTime.now().toUtc(),
    );
    await file.writeAsString(ics, flush: true);
    return file;
  }

  static Future<void> shareEventAsIcs({
    required String uid,
    required String title,
    required DateTime startUtc,
    required DateTime endUtc,
    DateTime? dtStampUtc,
  }) async {
    final file = await writeEventIcsFile(
      uid: uid,
      title: title,
      startUtc: startUtc,
      endUtc: endUtc,
      dtStampUtc: dtStampUtc,
    );
    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'text/calendar',
        ),
      ],
      subject: title,
    );
  }
}
