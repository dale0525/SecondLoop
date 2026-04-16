import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/app_shell_default_pages_shared.dart'
    as shared_defaults;
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('shared chat tab shows stage label when loop home load fails',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _HomeLoadFailingBackend(
              loopHomeError:
                  UnsupportedError('operation not supported on this platform'),
            ),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Builder(
                builder: (context) => shared_defaults.buildSharedDefaultChatTab(
                  context,
                  isActive: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('home.loopHomeConversation.initial'),
      findsOneWidget,
    );
  });

  testWidgets('chat page shows stage label when initial message load fails',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _HomeLoadFailingBackend(
              listMessagesPageError:
                  UnsupportedError('operation not supported on this platform'),
            ),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('chat.listMessagesPage.initial'),
      findsOneWidget,
    );
  });
}

final class _HomeLoadFailingBackend extends TestAppBackend {
  _HomeLoadFailingBackend({
    this.loopHomeError,
    this.listMessagesPageError,
  });

  final Object? loopHomeError;
  final Object? listMessagesPageError;

  @override
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) async {
    if (loopHomeError != null) throw loopHomeError!;
    return const Conversation(
      id: 'loop_home',
      title: 'Loop',
      createdAtMs: 0,
      updatedAtMs: 0,
    );
  }

  @override
  Future<List<Message>> listMessagesPage(
    Uint8List key,
    String conversationId, {
    int? beforeCreatedAtMs,
    String? beforeId,
    int limit = 60,
  }) async {
    if (listMessagesPageError != null) throw listMessagesPageError!;
    return const <Message>[];
  }
}
