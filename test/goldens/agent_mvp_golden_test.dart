import 'package:flutter_test/flutter_test.dart';

const agentMvpGoldenReferenceNames = <String>[
  '01-permanent-conversation-home.png',
  '02-conversation-review-approval.png',
  '03-memory-preferences.png',
  '03-memory-people.png',
  '03-memory-projects.png',
  '03-memory-sources.png',
  '03-memory-suggestions.png',
  '04-conversation-files-media.png',
  '05-conversation-daily-brief-reminders.png',
  '06-conversation-calendar-email.png',
  '07-conversation-research-citations.png',
  '08-settings-account.png',
  '08-settings-connection.png',
  '08-settings-permissions.png',
  '08-settings-memory.png',
  '08-settings-activity.png',
];

void main() {
  test('agent MVP golden harness tracks canonical references only', () {
    expect(agentMvpGoldenReferenceNames, hasLength(16));
    expect(
      agentMvpGoldenReferenceNames,
      isNot(contains('03-long-term-memory.png')),
    );
    expect(
      agentMvpGoldenReferenceNames,
      isNot(contains('08-settings-activity-transparency.png')),
    );
  });
}
