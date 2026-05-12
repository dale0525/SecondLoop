import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';
import 'package:secondloop/features/conversation_cards/approval_preview_card.dart';
import 'package:secondloop/features/conversation_cards/calendar_email_card.dart';
import 'package:secondloop/features/conversation_cards/daily_brief_card.dart';
import 'package:secondloop/features/conversation_cards/media_summary_card.dart';
import 'package:secondloop/features/conversation_cards/research_brief_card.dart';
import 'package:secondloop/features/conversation_cards/research_models.dart';
import 'package:secondloop/features/conversation_context/conversation_context_rail.dart';

import '../test_i18n.dart';

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

    await tester.pumpWidget(_AgentMvpGoldenApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('agent_mvp_golden_root')),
      matchesGoldenFile('agent_mvp/actual/agent_mvp_desktop.png'),
    );
  });

  testWidgets('mobile agent MVP demo matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_AgentMvpGoldenApp());
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

final class _AgentMvpGoldenApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return wrapWithI18n(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: RepaintBoundary(
          key: const ValueKey('agent_mvp_golden_root'),
          child: AppShell(
            conversationTabBuilder: (_, __) => const _ConversationDemo(),
            memoryTabBuilder: (_, __) => const SizedBox.shrink(),
            reviewTabBuilder: (_, __) => const SizedBox.shrink(),
            settingsTabBuilder: (_, __) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

final class _ConversationDemo extends StatelessWidget {
  const _ConversationDemo();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = constraints.maxWidth >= 1040;
        final conversation = SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ApprovalPreviewCard(change: ApprovalPreviewChange.demo()),
              const SizedBox(height: 16),
              MediaSummaryCard(data: MediaSummaryData.demo()),
              const SizedBox(height: 16),
              DailyBriefCard(data: DailyBriefData.demo()),
              const SizedBox(height: 16),
              CalendarEmailCard(data: CalendarEmailData.demo()),
              const SizedBox(height: 16),
              ResearchBudgetConfirmationCard(
                estimate: ResearchBudgetEstimate.demo(),
              ),
              const SizedBox(height: 16),
              ResearchResultCard(result: ResearchResult.demo()),
            ],
          ),
        );

        if (!showRail) return conversation;

        return Row(
          children: [
            Expanded(child: conversation),
            SizedBox(
              width: 320,
              child: ConversationContextRail(
                snapshot: ConversationContextSnapshot.demo(),
              ),
            ),
          ],
        );
      },
    );
  }
}
