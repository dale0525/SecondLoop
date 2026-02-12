import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';

void main() {
  test('Android scheduler icon uses a standalone drawable asset', () {
    const iconName = FlutterLocalNotificationsReviewReminderScheduler
        .androidNotificationIcon;

    expect(iconName, isNotEmpty);
    expect(iconName.contains('/'), isFalse);
    expect(iconName.startsWith('@'), isFalse);

    final xmlIconFile = File('android/app/src/main/res/drawable/$iconName.xml');
    final pngIconFile = File('android/app/src/main/res/drawable/$iconName.png');

    expect(xmlIconFile.existsSync() || pngIconFile.existsSync(), isTrue);

    if (xmlIconFile.existsSync()) {
      final xml = xmlIconFile.readAsStringSync();
      expect(xml, isNot(contains('@mipmap/')));
    }
  });
}
