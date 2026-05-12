import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';
import 'package:secondloop/features/conversation_cards/approval_preview_card.dart';
import 'package:secondloop/features/conversation_cards/calendar_email_card.dart';
import 'package:secondloop/features/conversation_cards/daily_brief_card.dart';
import 'package:secondloop/features/conversation_cards/media_summary_card.dart';
import 'package:secondloop/features/conversation_cards/research_brief_card.dart';
import 'package:secondloop/features/conversation_cards/research_models.dart';
import 'package:secondloop/features/conversation_context/conversation_context_rail.dart';
import 'package:secondloop/features/memory/memory_page.dart';
import 'package:secondloop/features/review/review_page.dart';
import 'package:secondloop/features/settings/agent_settings_page.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/ui/sl_background.dart';

import '../test/test_i18n.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
  });

  testWidgets('managed pro agent UI acceptance screenshots', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final screenshotKey = GlobalKey(debugLabel: 'managed_pro_acceptance_root');

    await tester.pumpWidget(
      _ManagedProAcceptanceApp(screenshotKey: screenshotKey),
    );
    await tester.pumpAndSettle();

    final outputDir = _acceptanceOutputDirectory();
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '01-conversation-home',
    );

    await tester.tap(find.text('Fields'));
    await tester.pumpAndSettle();
    expect(find.text('Extracted fields'), findsOneWidget);
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '02-conversation-media-fields',
    );

    await tester.tap(find.text('Review').first);
    await tester.pumpAndSettle();
    expect(find.text('Needs your OK queue'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Move passport renewal'), findsNothing);
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '03-review-approve-flow',
    );

    await tester.tap(find.text('Memory').first);
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '04-memory-preferences',
    );

    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '05-settings-account',
    );

    await _writeReport(outputDir);
  });
}

Directory _acceptanceOutputDirectory() {
  final raw =
      Platform.environment['SECONDLOOP_MANAGED_PRO_ACCEPTANCE_OUTPUT_DIR'];
  final path = raw == null || raw.trim().isEmpty
      ? 'build/managed_pro_acceptance/local_${DateTime.now().millisecondsSinceEpoch}'
      : raw.trim();
  return Directory(path)..createSync(recursive: true);
}

Future<void> _writeScreenshot({
  required GlobalKey rootKey,
  required Directory outputDir,
  required String name,
}) async {
  final bytes = await _captureRepaintBoundaryPng(rootKey);
  expect(bytes.length, greaterThan(1000));
  await File('${outputDir.path}/$name.png').writeAsBytes(bytes);
}

Future<Uint8List> _captureRepaintBoundaryPng(GlobalKey rootKey) async {
  final renderObject = rootKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError('Acceptance screenshot root is not ready');
  }

  final image = await renderObject.toImage();
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Could not encode acceptance screenshot');
    }
    return byteData.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<void> _writeReport(Directory outputDir) async {
  final report = <String, Object?>{
    'schema': 'managed_pro_agent_ui_acceptance_v1',
    'appId': Platform.environment['SECONDLOOP_APP_ID'],
    'appName': Platform.environment['SECONDLOOP_APP_NAME'],
    'managedProEmailSet':
        (Platform.environment['SECONDLOOP_MANAGED_PRO_EMAIL'] ?? '').isNotEmpty,
    'screenshots': [
      '01-conversation-home.png',
      '02-conversation-media-fields.png',
      '03-review-approve-flow.png',
      '04-memory-preferences.png',
      '05-settings-account.png',
    ],
  };
  const encoder = JsonEncoder.withIndent('  ');
  await File('${outputDir.path}/managed_pro_agent_ui_acceptance_report.json')
      .writeAsString('${encoder.convert(report)}\n');
}

final class _ManagedProAcceptanceApp extends StatelessWidget {
  const _ManagedProAcceptanceApp({required this.screenshotKey});

  final GlobalKey screenshotKey;

  @override
  Widget build(BuildContext context) {
    return wrapWithI18n(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(
          locale: LocaleSettings.currentLocale.flutterLocale,
        ),
        home: RepaintBoundary(
          key: screenshotKey,
          child: SlBackground(
            child: AppShell(
              conversationTabBuilder: (_, __) =>
                  const _AcceptanceConversation(),
              memoryTabBuilder: (_, __) => const MemoryPage(),
              reviewTabBuilder: (_, __) => const ReviewPage(),
              settingsTabBuilder: (_, __) => const AgentSettingsPage(),
            ),
          ),
        ),
      ),
    );
  }
}

final class _AcceptanceConversation extends StatelessWidget {
  const _AcceptanceConversation();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
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
          ),
        ),
        SizedBox(
          width: 320,
          child: ConversationContextRail(
            snapshot: ConversationContextSnapshot.demo(),
          ),
        ),
      ],
    );
  }
}
