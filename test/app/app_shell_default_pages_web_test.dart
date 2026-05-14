import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/app_shell_default_pages_web.dart'
    as web_defaults;
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/features/inbox/inbox_page.dart';

import '../test_backend.dart';
import '../test_i18n.dart';

void main() {
  testWidgets('web default chat tab opens the Loop conversation',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: TestAppBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Builder(
                builder: (context) {
                  return web_defaults.buildDefaultChatTab(
                    context,
                    isActive: true,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AgentConversationPage), findsOneWidget);
    expect(find.byType(InboxPage), findsNothing);
    expect(find.byKey(const ValueKey('agent_conversation_workspace')),
        findsOneWidget);
  });
}
