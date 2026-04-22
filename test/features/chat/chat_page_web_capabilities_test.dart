import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import '../../test_backend.dart';
import '../../test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ChatPage disables native-only affordances for web capabilities',
      (tester) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final backend = TestAppBackend();
    try {
      final conversation = await backend.getOrCreateLoopHomeConversation(
        Uint8List.fromList(List<int>.filled(32, 1)),
      );

      await tester.pumpWidget(
        _buildApp(
          backend: backend,
          capabilities: AppPlatformCapabilities.webCloud(),
          conversation: conversation,
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('chat_desktop_drop_target')), findsNothing);
      expect(find.byKey(const ValueKey('chat_record_audio')), findsNothing);
      expect(find.byKey(const ValueKey('chat_attach')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('ChatPage opens settings without web appearance controls',
      (tester) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final backend = TestAppBackend();
    try {
      final conversation = await backend.getOrCreateLoopHomeConversation(
        Uint8List.fromList(List<int>.filled(32, 1)),
      );

      await tester.pumpWidget(
        _buildApp(
          backend: backend,
          capabilities: AppPlatformCapabilities.webCloud(),
          conversation: conversation,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chat_open_settings')));
      await tester.pumpAndSettle();

      expect(find.text('Theme'), findsNothing);
      expect(
          find.byKey(const ValueKey('settings_theme_palette')), findsNothing);
      expect(find.text('Language'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });
}

Widget _buildApp({
  required AppBackend backend,
  required AppPlatformCapabilities capabilities,
  required Conversation conversation,
}) {
  return AppPlatformCapabilityScope(
    capabilities: capabilities,
    child: wrapWithI18n(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: ChatPage(conversation: conversation),
          ),
        ),
      ),
    ),
  );
}
