import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_answer_evidence_models.dart';
import 'package:secondloop/features/chat/chat_answer_evidence_sheet.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  test('ChatAnswerEvidenceMemoryCard.copyWith can clear nullable fields', () {
    const original = ChatAnswerEvidenceMemoryCard(
      documentId: 'generated:preference:response-language',
      title: 'Response language',
      summary: 'Use Chinese',
      body: 'Use Chinese for replies.',
      sourceKind: 'summary',
      role: 'summary',
      createdAtMs: 1,
      updatedAtMs: 2,
      status: 'confirmed',
      sourceCount: 1,
      whyUsed: 'latest query',
    );

    final updated = original.copyWith(
      title: null,
      summary: null,
      body: null,
      whyUsed: null,
    );

    expect(updated.title, isNull);
    expect(updated.summary, isNull);
    expect(updated.body, isNull);
    expect(updated.whyUsed, isNull);
  });

  testWidgets('ChatAnswerEvidencePanel renders both tabs and actions',
      (tester) async {
    var openedDirectSource = '';
    var openedMemoryDocument = '';
    var correctedMemoryDocument = '';
    var correctedTitle = '';
    var correctedSummary = '';
    var disabledMemoryDocument = '';
    var deletedMemoryDocument = '';

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: ChatAnswerEvidencePanel(
            evidence: const ChatAnswerEvidence(
              directSources: [
                ChatAnswerEvidenceDirectSource(
                  id: 'message:history-1',
                  href: 'secondloop://message/history-1',
                  sourceType: 'message',
                  label: 'History',
                  sourceTypeLabel: 'chat_message',
                  scopeLabel: 'this_thread',
                  confidenceLabel: 'high_relevance',
                  title: 'Kickoff notes',
                  snippet: 'Kickoff moved to Friday afternoon.',
                  highlightedText: 'Kickoff moved to Friday afternoon.',
                  createdAtMs: 1,
                  updatedAtMs: 2,
                  documentId: null,
                  unitId: null,
                ),
              ],
              memoryCards: [
                ChatAnswerEvidenceMemoryCard(
                  documentId: 'generated:preference:response-language',
                  title: 'Response language',
                  summary: 'User prefers Chinese.',
                  sourceKind: 'summary',
                  role: 'summary',
                  createdAtMs: 3,
                  updatedAtMs: 4,
                  status: 'confirmed',
                  sourceCount: 2,
                  whyUsed: '用中文总结一下最近变化',
                ),
              ],
            ),
            initialTab: ChatAnswerEvidenceTab.directSources,
            onOpenDirectSource: (href) async => openedDirectSource = href,
            onOpenMemoryCard: (documentId) async =>
                openedMemoryDocument = documentId,
            onCorrectMemoryCard: (card, title, summary) async {
              correctedMemoryDocument = card.documentId;
              correctedTitle = title;
              correctedSummary = summary;
              return card.copyWith(
                title: title,
                summary: summary,
                status: 'confirmed',
              );
            },
            onDisableMemoryCard: (documentId) async =>
                disabledMemoryDocument = documentId,
            onDeleteMemoryCard: (documentId) async =>
                deletedMemoryDocument = documentId,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kickoff notes'), findsOneWidget);
    expect(find.text('Chat message'), findsOneWidget);
    expect(find.text('This thread'), findsOneWidget);
    expect(find.text('High relevance'), findsOneWidget);
    await tester.tap(find.text('View original'));
    await tester.pumpAndSettle();
    expect(openedDirectSource, 'secondloop://message/history-1');

    await tester.tap(find.textContaining('Knowledge pages'));
    await tester.pumpAndSettle();
    expect(find.text('Response language'), findsOneWidget);
    await tester.tap(find.text('Inspect page'));
    await tester.pumpAndSettle();
    expect(openedMemoryDocument, 'generated:preference:response-language');
    await tester.tap(find.text('Correct'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_title_field')),
      'Preferred reply language',
    );
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_summary_field')),
      'Always reply in Chinese unless another language is requested.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(correctedMemoryDocument, 'generated:preference:response-language');
    expect(correctedTitle, 'Preferred reply language');
    expect(
      correctedSummary,
      'Always reply in Chinese unless another language is requested.',
    );
    expect(find.text('Preferred reply language'), findsOneWidget);
    expect(
      find.text(
        'Always reply in Chinese unless another language is requested.',
      ),
      findsOneWidget,
    );
    expect(find.text('Confirmed'), findsOneWidget);
    await tester.tap(find.text('Stop using in answers'));
    await tester.pumpAndSettle();
    expect(disabledMemoryDocument, 'generated:preference:response-language');
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(deletedMemoryDocument, 'generated:preference:response-language');
  });

  testWidgets('ChatAnswerEvidencePanel localizes stable evidence codes', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: ChatAnswerEvidencePanel(
            evidence: ChatAnswerEvidence(
              directSources: [
                ChatAnswerEvidenceDirectSource(
                  id: 'message:history-1',
                  href: 'secondloop://message/history-1',
                  sourceType: 'message',
                  label: 'History',
                  sourceTypeLabel: 'chat_message',
                  scopeLabel: 'this_thread',
                  confidenceLabel: 'high_relevance',
                  title: 'Kickoff notes',
                  snippet: 'Kickoff moved to Friday afternoon.',
                  highlightedText: 'Kickoff moved to Friday afternoon.',
                  createdAtMs: 1,
                  updatedAtMs: 2,
                  documentId: null,
                  unitId: null,
                ),
              ],
              memoryCards: [
                ChatAnswerEvidenceMemoryCard(
                  documentId: 'generated:preference:response-language',
                  title: 'Response language',
                  summary: 'User prefers Chinese.',
                  sourceKind: 'summary',
                  role: 'summary',
                  createdAtMs: 3,
                  updatedAtMs: 4,
                  status: 'confirmed',
                  sourceCount: 2,
                  whyUsed: '用中文总结一下最近变化',
                ),
              ],
            ),
            initialTab: ChatAnswerEvidenceTab.directSources,
            onOpenDirectSource: _noopOpenDirectSource,
            onOpenMemoryCard: _noopOpenMemoryCard,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('聊天消息'), findsOneWidget);
    expect(find.text('当前线程'), findsOneWidget);
    expect(find.text('高相关性'), findsOneWidget);

    await tester.tap(find.textContaining('知识页'));
    await tester.pumpAndSettle();

    expect(find.text('因与这个问题相关而被使用：用中文总结一下最近变化'), findsOneWidget);
  });

  testWidgets('showChatAnswerEvidenceSheet uses right drawer on wide layouts',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1200, 800)),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showChatAnswerEvidenceSheet(
                      context,
                      evidence: const ChatAnswerEvidence(
                        directSources: [
                          ChatAnswerEvidenceDirectSource(
                            id: 'message:history-1',
                            href: 'secondloop://message/history-1',
                            sourceType: 'message',
                            label: 'History',
                            sourceTypeLabel: 'Chat message',
                            scopeLabel: 'This thread',
                            confidenceLabel: 'High relevance',
                            title: 'Kickoff notes',
                            snippet: 'Kickoff moved to Friday afternoon.',
                            highlightedText:
                                'Kickoff moved to Friday afternoon.',
                            createdAtMs: 1,
                            updatedAtMs: 2,
                            documentId: null,
                            unitId: null,
                          ),
                        ],
                        memoryCards: [],
                      ),
                      onOpenDirectSource: (_) async {},
                      onOpenMemoryCard: (_) async {},
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('answer_evidence_desktop_drawer')),
        findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'ChatAnswerEvidencePanel prefills correction from memory body when available',
    (tester) async {
      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:pattern:active-task-focus',
                    title: 'Active task focus',
                    summary:
                        'User is actively working across these task threads:',
                    body:
                        'User is actively working across these task threads:\n- Draft roadmap [in_progress]\n- Review launch notes [open]',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 4,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: 'Summarize the current focus',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
              onOpenMemoryCard: _noopOpenMemoryCard,
              onCorrectMemoryCard: _returnUpdatedCard,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Correct'));
      await tester.pumpAndSettle();

      final summaryField = tester.widget<TextField>(
        find.byKey(const ValueKey('memory_correction_summary_field')),
      );
      expect(
        summaryField.controller?.text,
        'User is actively working across these task threads:\n- Draft roadmap [in_progress]\n- Review launch notes [open]',
      );
    },
  );

  testWidgets(
    'ChatAnswerEvidencePanel uses updated body for subsequent corrections',
    (tester) async {
      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:pattern:active-task-focus',
                    title: 'Active task focus',
                    summary: 'Initial summary',
                    body: 'Initial body',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 4,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: 'Summarize the current focus',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
              onOpenMemoryCard: _noopOpenMemoryCard,
              onCorrectMemoryCard: _returnUpdatedCard,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Correct'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('memory_correction_summary_field')),
        'Updated body from correction',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Correct'));
      await tester.pumpAndSettle();

      final summaryField = tester.widget<TextField>(
        find.byKey(const ValueKey('memory_correction_summary_field')),
      );
      expect(summaryField.controller?.text, 'Updated body from correction');
    },
  );

  testWidgets(
    'ChatAnswerEvidencePanel refreshes memory card state on load',
    (tester) async {
      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:preference:response-language',
                    title: 'Response language',
                    summary: 'User prefers Chinese.',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 4,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: '用中文总结一下最近变化',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
              onOpenMemoryCard: _noopOpenMemoryCard,
              onRefreshMemoryCard: _refreshDisabledDeletedCard,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('This memory was deleted after the answer was generated.'),
        findsOneWidget,
      );
      expect(find.text('User prefers Chinese.'), findsNothing);
    },
  );

  testWidgets(
    'ChatAnswerEvidencePanel starts memory refreshes concurrently',
    (tester) async {
      final started = <String>[];
      final completers = <String, Completer<ChatAnswerEvidenceMemoryCard?>>{
        'generated:preference:response-language':
            Completer<ChatAnswerEvidenceMemoryCard?>(),
        'generated:project:launch-work':
            Completer<ChatAnswerEvidenceMemoryCard?>(),
      };

      Future<ChatAnswerEvidenceMemoryCard?> refresh(
        ChatAnswerEvidenceMemoryCard card,
      ) {
        started.add(card.documentId);
        return completers[card.documentId]!.future;
      }

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: const ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:preference:response-language',
                    title: 'Response language',
                    summary: 'User prefers Chinese.',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 4,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: '用中文总结一下最近变化',
                  ),
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:project:launch-work',
                    title: 'Launch work',
                    summary: 'Ship the release companion.',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 5,
                    updatedAtMs: 6,
                    status: 'confirmed',
                    sourceCount: 1,
                    whyUsed: '整理当前工作重点',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
              onOpenMemoryCard: _noopOpenMemoryCard,
              onRefreshMemoryCard: refresh,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(
        started,
        containsAll(<String>[
          'generated:preference:response-language',
          'generated:project:launch-work',
        ]),
      );

      for (final completer in completers.values) {
        completer.complete();
      }
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'ChatAnswerEvidencePanel ignores stale refresh results after evidence updates',
    (tester) async {
      final staleRefresh = Completer<ChatAnswerEvidenceMemoryCard?>();
      final freshRefresh = Completer<ChatAnswerEvidenceMemoryCard?>();

      Future<ChatAnswerEvidenceMemoryCard?> refresh(
        ChatAnswerEvidenceMemoryCard card,
      ) {
        if (card.title == 'Old title') {
          return staleRefresh.future;
        }
        return freshRefresh.future;
      }

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: const ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:preference:response-language',
                    title: 'Old title',
                    summary: 'Old summary',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 4,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: 'latest query',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
              onOpenMemoryCard: _noopOpenMemoryCard,
              onRefreshMemoryCard: refresh,
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: const ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:preference:response-language',
                    title: 'New title',
                    summary: 'New summary',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 5,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: 'latest query',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
              onOpenMemoryCard: _noopOpenMemoryCard,
              onRefreshMemoryCard: refresh,
            ),
          ),
        ),
      );

      await tester.pump();

      freshRefresh.complete(
        const ChatAnswerEvidenceMemoryCard(
          documentId: 'generated:preference:response-language',
          title: 'Fresh title',
          summary: 'Fresh summary',
          sourceKind: 'summary',
          role: 'summary',
          createdAtMs: 3,
          updatedAtMs: 6,
          status: 'confirmed',
          sourceCount: 2,
          whyUsed: 'latest query',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fresh title'), findsOneWidget);
      expect(find.text('Old title'), findsNothing);

      staleRefresh.complete(
        const ChatAnswerEvidenceMemoryCard(
          documentId: 'generated:preference:response-language',
          title: 'Stale title',
          summary: 'Stale summary',
          sourceKind: 'summary',
          role: 'summary',
          createdAtMs: 3,
          updatedAtMs: 4,
          status: 'confirmed',
          sourceCount: 2,
          whyUsed: 'latest query',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fresh title'), findsOneWidget);
      expect(find.text('Stale title'), findsNothing);
    },
  );

  testWidgets(
    'ChatAnswerEvidencePanel shows an error and keeps state when correction fails',
    (tester) async {
      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:preference:response-language',
                    title: 'Response language',
                    summary: 'User prefers Chinese.',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 4,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: '用中文总结一下最近变化',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
              onOpenMemoryCard: _noopOpenMemoryCard,
              onCorrectMemoryCard: _throwOnCorrect,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Correct'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('correct failed'), findsOneWidget);
      expect(find.text('Response language'), findsOneWidget);
    },
  );

  testWidgets(
    'ChatAnswerEvidencePanel shows an error and keeps memory enabled when disable fails',
    (tester) async {
      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:preference:response-language',
                    title: 'Response language',
                    summary: 'User prefers Chinese.',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 4,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: '用中文总结一下最近变化',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
              onOpenMemoryCard: _noopOpenMemoryCard,
              onDisableMemoryCard: _throwOnDisable,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Used in answers'), findsOneWidget);

      await tester.tap(find.text('Stop using in answers'));
      await tester.pump();

      expect(find.textContaining('disable failed'), findsOneWidget);
      expect(find.text('Used in answers'), findsOneWidget);
      expect(find.text('Not used in answers'), findsNothing);
    },
  );

  testWidgets(
    'ChatAnswerEvidencePanel hides memory actions when memory backends are unavailable',
    (tester) async {
      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            home: ChatAnswerEvidencePanel(
              evidence: ChatAnswerEvidence(
                directSources: [],
                memoryCards: [
                  ChatAnswerEvidenceMemoryCard(
                    documentId: 'generated:preference:response-language',
                    title: 'Response language',
                    summary: 'User prefers Chinese.',
                    sourceKind: 'summary',
                    role: 'summary',
                    createdAtMs: 3,
                    updatedAtMs: 4,
                    status: 'confirmed',
                    sourceCount: 2,
                    whyUsed: '用中文总结一下最近变化',
                  ),
                ],
              ),
              initialTab: ChatAnswerEvidenceTab.memoryCards,
              onOpenDirectSource: _noopOpenDirectSource,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Inspect page'), findsNothing);
      expect(find.text('Correct'), findsNothing);
      expect(find.text('Stop using in answers'), findsNothing);
      expect(find.text('Archive'), findsNothing);
    },
  );
}

Future<void> _noopOpenDirectSource(String _) async {}

Future<void> _noopOpenMemoryCard(String _) async {}

Future<ChatAnswerEvidenceMemoryCard?> _returnUpdatedCard(
  ChatAnswerEvidenceMemoryCard card,
  String title,
  String summary,
) async =>
    card.copyWith(title: title, summary: summary, body: summary);

Future<ChatAnswerEvidenceMemoryCard?> _refreshDisabledDeletedCard(
  ChatAnswerEvidenceMemoryCard card,
) async =>
    card.copyWith(
      summary: 'This memory was deleted after the answer was generated.',
      body: 'This memory was deleted after the answer was generated.',
      isDeleted: true,
      useForAskAi: false,
    );

Future<ChatAnswerEvidenceMemoryCard?> _throwOnCorrect(
  ChatAnswerEvidenceMemoryCard card,
  String title,
  String summary,
) async =>
    throw StateError('correct failed');

Future<void> _throwOnDisable(String _) async =>
    throw StateError('disable failed');
