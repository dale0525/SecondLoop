import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';

void main() {
  test('Android scheduler icon points to drawable resource name', () {
    const iconName = FlutterLocalNotificationsReviewReminderScheduler
        .androidNotificationIcon;

    expect(iconName, isNotEmpty);
    expect(iconName.contains('/'), isFalse);
    expect(iconName.startsWith('@'), isFalse);

    final iconFile = File('android/app/src/main/res/drawable/$iconName.xml');
    expect(iconFile.existsSync(), isTrue);
  });
}
