import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/update_badge_prefs.dart';
import 'package:secondloop/ui/sl_background.dart';
import 'package:secondloop/ui/sl_tokens.dart';

import 'agent_mvp_golden_test_harness.dart';

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
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/inter/Inter-Variable.ttf')))
        .load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
  });

  test('agent MVP golden harness tracks canonical references only', () async {
    expect(agentMvpGoldenReferenceNames, hasLength(16));
    expect(
      agentMvpGoldenReferenceNames,
      isNot(contains('03-long-term-memory.png')),
    );
    expect(
      agentMvpGoldenReferenceNames,
      isNot(contains('08-settings-activity-transparency.png')),
    );

    for (final name in agentMvpGoldenReferenceNames) {
      final file = File('test/goldens/agent_mvp/references/$name');
      expect(file.existsSync(), isTrue, reason: name);

      final image = await _decodeImage(file);
      expect(image.width, 2048, reason: name);
      expect(image.height, isIn(<int>{1365, 1366}), reason: name);
      image.dispose();
    }
  });

  testWidgets('desktop agent MVP demo matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_mvp_golden_root')),
      matchesGoldenFile('agent_mvp/actual/agent_mvp_desktop.png'),
    );
  });

  testWidgets('conversation home reference includes the full storyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpGoldenApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('agent_home_desktop_workspace')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('agent_home_mobile_mock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_home_interaction_notes')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_home_account_footer')),
        findsOneWidget);
    expect(find.text('Conversation'), findsWidgets);
    expect(find.text('Ready'), findsOneWidget);
    expect(
      find.text("Good morning! Here's your brief for today."),
      findsOneWidget,
    );
    expect(find.text('Your context'), findsWidgets);
    expect(
      find.text('Ask, capture, search, or attach a file...'),
      findsOneWidget,
    );
    expect(find.text('Interaction Notes'), findsOneWidget);
  });

  testWidgets('review approval storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpReviewGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_review_golden_root')),
      matchesGoldenFile('agent_mvp/actual/review_approval_desktop.png'),
    );
  });

  testWidgets('review approval reference includes queue detail and notes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpReviewGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_review_desktop_workspace')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('agent_review_mobile_mock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_review_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Review'), findsWidgets);
    expect(find.text('Needs your OK'), findsOneWidget);
    expect(find.text('Task change'), findsWidgets);
    expect(find.text('Change preview'), findsOneWidget);
    expect(find.text('Nothing is applied until you approve.'), findsOneWidget);
    expect(find.text('Approve'), findsWidgets);
    expect(find.text('Reject'), findsWidgets);
  });

  testWidgets('memory preferences storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemoryPreferencesGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_memory_preferences_golden_root')),
      matchesGoldenFile('agent_mvp/actual/memory_preferences_desktop.png'),
    );
  });

  testWidgets('memory preferences reference includes table candidate and notes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemoryPreferencesGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_memory_preferences_workspace')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('agent_memory_mobile_mock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_memory_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Memory'), findsWidgets);
    expect(find.text('Preferences'), findsWidgets);
    expect(find.text('All memory is private and editable.'), findsOneWidget);
    expect(find.text('Add preference'), findsOneWidget);
    expect(find.text('Pending preference candidate (1)'), findsWidgets);
    expect(find.text('Do not schedule meetings after 18:00'), findsWidgets);
    expect(
      find.text(
          'Your preferences are used only to personalize responses and suggestions.'),
      findsWidgets,
    );
  });

  testWidgets('memory people storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemoryPeopleGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_memory_people_golden_root')),
      matchesGoldenFile('agent_mvp/actual/memory_people_desktop.png'),
    );
  });

  testWidgets('memory people reference includes person detail and candidate',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemoryPeopleGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_memory_people_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_memory_people_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_memory_people_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Memory'), findsWidgets);
    expect(find.text('People'), findsWidgets);
    expect(find.text('Add person'), findsOneWidget);
    expect(find.text('Alex - Project'), findsWidgets);
    expect(find.text('Known preferences'), findsOneWidget);
    expect(find.text('Pending people memory candidate (1)'), findsWidgets);
    expect(find.text('Alex prefers written follow-up'), findsWidgets);
  });

  testWidgets('memory projects storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemoryProjectsGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_memory_projects_golden_root')),
      matchesGoldenFile('agent_mvp/actual/memory_projects_desktop.png'),
    );
  });

  testWidgets('memory projects reference includes project detail and candidate',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemoryProjectsGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_memory_projects_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_memory_projects_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_memory_projects_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Memory'), findsWidgets);
    expect(find.text('Projects'), findsWidgets);
    expect(find.text('Add project'), findsOneWidget);
    expect(find.text('Cloudflare Agent MVP'), findsWidgets);
    expect(find.text('Objective'), findsWidgets);
    expect(find.text('Active documents'), findsWidgets);
    expect(find.text('Pending project memory candidate (1)'), findsWidgets);
    expect(find.text('Cloudflare Agent MVP excludes shell automation'),
        findsWidgets);
  });

  testWidgets('memory sources storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemorySourcesGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_memory_sources_golden_root')),
      matchesGoldenFile('agent_mvp/actual/memory_sources_desktop.png'),
    );
  });

  testWidgets(
      'memory sources reference includes source table and detach action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemorySourcesGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_memory_sources_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_memory_sources_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_memory_sources_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Memory'), findsWidgets);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('All sources'), findsWidgets);
    expect(find.text('Conversation - May 20'), findsWidgets);
    expect(find.text('Extracted memory references'), findsWidgets);
    expect(find.text('Linked memory'), findsOneWidget);
    expect(find.text('Source summary'), findsOneWidget);
    expect(find.text('Open source'), findsWidgets);
    expect(find.text('Detach memory'), findsWidgets);
  });

  testWidgets('memory suggestions storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemorySuggestionsGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_memory_suggestions_golden_root')),
      matchesGoldenFile('agent_mvp/actual/memory_suggestions_desktop.png'),
    );
  });

  testWidgets('memory suggestions reference includes candidate groups',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpMemorySuggestionsGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_memory_suggestions_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_memory_suggestions_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_memory_suggestions_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Memory'), findsWidgets);
    expect(find.text('Suggestions'), findsWidgets);
    expect(find.text('Review memory candidates before they become permanent.'),
        findsWidgets);
    expect(find.text('All types'), findsWidgets);
    expect(find.text('Review selected (0)'), findsOneWidget);
    expect(find.textContaining('From your message'), findsWidgets);
    expect(find.text('No meetings before 9 AM'), findsWidgets);
    expect(find.text('Reply to tasks in Chinese'), findsWidgets);
    expect(find.text('Alex prefers afternoon meetings'), findsWidgets);
    expect(find.textContaining('Nothing is saved until you accept.'),
        findsWidgets);
    expect(find.text('Accept'), findsWidgets);
    expect(find.text('Ignore'), findsWidgets);
  });

  testWidgets('settings account storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsAccountGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_settings_account_golden_root')),
      matchesGoldenFile('agent_mvp/actual/settings_account_desktop.png'),
    );
  });

  testWidgets('settings account reference includes plan billing and security',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsAccountGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_settings_account_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_settings_account_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_settings_account_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Account'), findsWidgets);
    expect(find.text('Plan, profile, billing, and security.'), findsOneWidget);
    expect(find.text('Ada Lin'), findsWidgets);
    expect(find.text('Pro Plan'), findsWidgets);
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('Email & account security'), findsWidgets);
    expect(find.text('Your data'), findsWidgets);
    expect(find.text('Manage billing'), findsWidgets);
    expect(find.text('Delete account'), findsWidgets);
  });

  testWidgets('settings connection storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsConnectionGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_settings_connection_golden_root')),
      matchesGoldenFile('agent_mvp/actual/settings_connection_desktop.png'),
    );
  });

  testWidgets('settings connection reference includes modes health and notes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsConnectionGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_settings_connection_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_settings_connection_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_settings_connection_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Connection'), findsWidgets);
    expect(find.text('Choose how SecondLoop runs for you.'), findsWidgets);
    expect(find.text('Managed Pro'), findsWidgets);
    expect(find.text('Self-managed / Open-source'), findsWidgets);
    expect(find.text('Ready to use'), findsWidgets);
    expect(find.text('No Cloudflare setup'), findsWidgets);
    expect(find.text('No BYOK required'), findsWidgets);
    expect(find.text('Connect Cloudflare'), findsWidgets);
    expect(find.text('Add model keys'), findsWidgets);
    expect(find.text('Check assistant abilities'), findsWidgets);
    expect(find.text('Save connection'), findsWidgets);
    expect(find.text('Connection health'), findsWidgets);
    expect(find.text('Test connection'), findsWidgets);
    expect(find.text('Both modes keep the same UX.'), findsOneWidget);
  });

  testWidgets('settings permissions storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsPermissionsGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_settings_permissions_golden_root')),
      matchesGoldenFile('agent_mvp/actual/settings_permissions_desktop.png'),
    );
  });

  testWidgets('settings permissions reference includes table states and notes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsPermissionsGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_settings_permissions_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_settings_permissions_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('agent_settings_permissions_interaction_notes'),
      ),
      findsOneWidget,
    );
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Permissions'), findsWidgets);
    expect(
      find.text('Manage what SecondLoop can read, draft, or do with approval.'),
      findsWidgets,
    );
    expect(find.text('External side effects require approval.'), findsWidgets);
    expect(find.text('Vault read'), findsWidgets);
    expect(find.text('Read your saved memories and notes.'), findsWidgets);
    expect(find.text('Calendar availability'), findsWidgets);
    expect(find.text('Email drafts'), findsWidgets);
    expect(find.text('Email send requires approval'), findsWidgets);
    expect(find.text('Needs approval'), findsWidgets);
    expect(find.text('Files you attach'), findsWidgets);
    expect(find.text('Notifications'), findsWidgets);
    expect(find.text('Off'), findsWidgets);
    expect(find.text('You can change any permission at any time.'),
        findsOneWidget);
    expect(find.text('Permissions describe allowed actions.'), findsOneWidget);
  });

  testWidgets('settings memory storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsMemoryGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_settings_memory_golden_root')),
      matchesGoldenFile('agent_mvp/actual/settings_memory_desktop.png'),
    );
  });

  testWidgets('settings memory reference includes toggles danger and notes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsMemoryGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_settings_memory_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_settings_memory_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_settings_memory_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Memory'), findsWidgets);
    expect(
      find.text('Control how SecondLoop remembers and uses saved context.'),
      findsWidgets,
    );
    expect(find.text('Memory suggestions'), findsWidgets);
    expect(
      find.text('Suggest new memories from your messages and context.'),
      findsWidgets,
    );
    expect(find.text('Use memories in conversation'), findsWidgets);
    expect(find.text('People memory'), findsWidgets);
    expect(find.text('Project memory'), findsWidgets);
    expect(find.text('Review before saving'), findsWidgets);
    expect(find.text('Forget all memory'), findsWidgets);
    expect(
      find.text('Permanently remove all saved memories and context.'),
      findsWidgets,
    );
    expect(
      find.text(
          'Long-term memory is editable and requires approval before new facts are saved.'),
      findsWidgets,
    );
    expect(find.text('Learn more about memory'), findsWidgets);
    expect(find.text('This tab controls memory behavior.'), findsOneWidget);
  });

  testWidgets('settings activity storyboard matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsActivityGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_settings_activity_golden_root')),
      matchesGoldenFile('agent_mvp/actual/settings_activity_desktop.png'),
    );
  });

  testWidgets('settings activity reference includes timeline export and notes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpSettingsActivityGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_settings_activity_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_settings_activity_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_settings_activity_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Activity transparency'), findsWidgets);
    expect(
      find.text('See what SecondLoop did, in plain language.'),
      findsWidgets,
    );
    expect(find.text('Read calendar availability'), findsWidgets);
    expect(find.text('Drafted email'), findsWidgets);
    expect(find.text('Prepared task change'), findsWidgets);
    expect(find.text('Saved research draft'), findsWidgets);
    expect(find.text('Created reminder candidate'), findsWidgets);
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Needs your OK'), findsWidgets);
    expect(find.text('View details'), findsWidgets);
    expect(
        find.text('Activity shows what SecondLoop did and why.'), findsWidgets);
    expect(find.text('Nothing is applied until you approve.'), findsWidgets);
    expect(find.text('Export diagnostic summary'), findsWidgets);
    expect(
      find.text(
          'Get a human-readable summary of recent activity, approvals, and system health.'),
      findsWidgets,
    );
    expect(find.text('Activity shows what happened.'), findsOneWidget);
  });

  testWidgets('conversation files media storyboard matches golden',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpFilesMediaGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_files_media_golden_root')),
      matchesGoldenFile('agent_mvp/actual/files_media_desktop.png'),
    );
  });

  testWidgets('conversation files media reference includes file summary flow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpFilesMediaGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_files_media_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_files_media_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_files_media_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Conversation'), findsWidgets);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('meeting_audio.mp3'), findsWidgets);
    expect(find.text('invoice.pdf'), findsWidgets);
    expect(find.text('passport_scan.jpg'), findsWidgets);
    expect(
      find.text(
          "I processed your files. Here's a summary, key points, extracted details, and suggested actions."),
      findsWidgets,
    );
    expect(find.text('Summary'), findsWidgets);
    expect(find.text('Transcript'), findsWidgets);
    expect(find.text('Extracted fields'), findsWidgets);
    expect(find.text('Suggested actions'), findsWidgets);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Meeting summary'), findsWidgets);
    expect(find.text('Decisions'), findsWidgets);
    expect(find.text('Action items'), findsWidgets);
    expect(find.text('Key topics covered'), findsWidgets);
    expect(find.text('Suggested review items'), findsWidgets);
    expect(
      find.text('Files enter through the conversation composer.'),
      findsOneWidget,
    );
  });

  testWidgets('conversation daily brief storyboard matches golden',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpDailyBriefGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_daily_brief_golden_root')),
      matchesGoldenFile('agent_mvp/actual/daily_brief_desktop.png'),
    );
  });

  testWidgets('conversation daily brief reference includes reminder flow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpDailyBriefGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_daily_brief_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_daily_brief_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_daily_brief_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Conversation'), findsWidgets);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text("Good morning. Here's your daily brief."), findsWidgets);
    expect(find.text('Top priorities'), findsWidgets);
    expect(find.text('Calendar windows'), findsWidgets);
    expect(find.text('Reminders'), findsWidgets);
    expect(find.text('Commitments owed'), findsWidgets);
    expect(find.text('Pending reviews'), findsWidgets);
    expect(find.text('Memory candidate: child birthday'), findsWidgets);
    expect(
      find.text('Recurring reminder candidate: buy gift before birthday'),
      findsWidgets,
    );
    expect(find.text('Missing facts trigger follow-up questions.'),
        findsOneWidget);
  });

  testWidgets('conversation calendar email storyboard matches golden',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpCalendarEmailGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_calendar_email_golden_root')),
      matchesGoldenFile('agent_mvp/actual/calendar_email_desktop.png'),
    );
  });

  testWidgets('conversation calendar email reference gates side effects',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpCalendarEmailGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_calendar_email_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_calendar_email_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_calendar_email_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Conversation'), findsWidgets);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Recommended evening times'), findsWidgets);
    expect(find.text('Calendar read is safe'), findsWidgets);
    expect(find.text('Dinner invite draft'), findsWidgets);
    expect(find.text('Needs your approval to send'), findsWidgets);
    expect(find.text('Follow-up email draft'), findsWidgets);
    expect(find.text('Email not connected'), findsWidgets);
    expect(find.text('Configure Email'), findsWidgets);
    expect(find.text('Save draft'), findsWidgets);
    expect(find.text('Sending email or invites needs confirmation.'),
        findsOneWidget);
  });

  testWidgets('conversation research citations storyboard matches golden',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpResearchGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_research_golden_root')),
      matchesGoldenFile('agent_mvp/actual/research_desktop.png'),
    );
  });

  testWidgets('conversation research reference includes citations and draft',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpResearchGoldenApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_research_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent_research_mobile_mock')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent_research_interaction_notes')),
      findsOneWidget,
    );
    expect(find.text('Conversation'), findsWidgets);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('High-cost research'), findsWidgets);
    expect(find.text('Search up to 20 pages'), findsWidgets);
    expect(find.text('Estimated tokens 120K'), findsWidgets);
    expect(find.text(r'Estimated cost $1.24'), findsWidgets);
    expect(find.text('Start research'), findsWidgets);
    expect(find.text('Reduce scope'), findsWidgets);
    expect(find.text('Brief'), findsWidgets);
    expect(find.text('Key points'), findsWidgets);
    expect(find.text('Sources (5)'), findsWidgets);
    expect(find.text('Draft note'), findsWidgets);
    expect(find.text('Saved as draft note'), findsWidgets);
    expect(find.text('Open draft'), findsWidgets);
    expect(find.text('Sources stay visible.'), findsOneWidget);
  });

  testWidgets('golden demo uses the production light app theme',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpGoldenApp());
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const ValueKey('agent_mvp_golden_root')),
    );
    expect(Theme.of(context).brightness, Brightness.light);
    expect(SlTokens.of(context).surface, const Color(0xFFFFFFFF));
    expect(SlTokens.of(context).background, const Color(0xFFF6F7FB));
  });

  testWidgets('golden demo uses deterministic project fonts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpGoldenApp());
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const ValueKey('agent_mvp_golden_root')),
    );
    expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(
      Theme.of(context).navigationRailTheme.selectedLabelTextStyle?.fontFamily,
      'Inter',
    );
  });

  testWidgets('golden demo includes the production app background',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpGoldenApp());
    await tester.pumpAndSettle();

    expect(find.byType(SlBackground), findsOneWidget);
  });

  testWidgets('mobile agent MVP demo matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AgentMvpGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_mvp_golden_root')),
      matchesGoldenFile('agent_mvp/actual/agent_mvp_mobile.png'),
    );
  });
}

Future<ui.Image> _decodeImage(File file) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(file.readAsBytesSync(), completer.complete);
  return completer.future;
}
