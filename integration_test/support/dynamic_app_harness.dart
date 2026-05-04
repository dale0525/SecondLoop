import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/ai/task_priority_ai_enhancement_prefs.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';

import '../../test/test_i18n.dart';
import 'dynamic_test_backend.dart';

final class DynamicAppHarness {
  DynamicAppHarness._({
    required this.tester,
    required this.backend,
  });

  final WidgetTester tester;
  final DynamicTestBackend backend;

  static Future<DynamicAppHarness> launch(
    WidgetTester tester, {
    required DynamicTestBackend backend,
    Size surfaceSize = const Size(900, 720),
  }) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': true,
      'welcome_guide_seen_v1': true,
      TaskPriorityAiEnhancementPrefs.prefsKey: false,
    });
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = DynamicAppHarness._(
      tester: tester,
      backend: backend,
    );
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppPlatformCapabilityScope(
            capabilities: const AppPlatformCapabilities(
              supportsDesktopHotkey: false,
              supportsBiometricUnlock: false,
              supportsMigrationArchive: false,
              supportsAudioRecording: false,
              supportsDesktopDrop: true,
              supportsExternalImport: false,
              supportsDesktopBootSettings: false,
              supportsCameraCapture: false,
              usesCloudSessionModel: false,
            ),
            child: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AppShell(),
              ),
            ),
          ),
        ),
      ),
    );

    await harness.pumpUntilFound(
      find.byKey(const ValueKey('chat_input')),
      description: 'chat input',
    );
    await harness.waitForBackend(
      'initial task priority load',
      () => backend.listTodosCalls > 0,
    );
    await tester.pump();
    return harness;
  }

  Future<void> sendChatMessage(String text) async {
    await tester.enterText(find.byKey(const ValueKey('chat_input')), text);
    await tester.pump();
    await tapByKey('chat_send');
    await waitForBackend(
      'message "$text" inserted',
      () => backend.insertedUserMessages.any((message) {
        return message.content == text;
      }),
    );
    await tester.pump();
  }

  Future<void> waitForTodoCommandCard(String commandId) {
    return pumpUntilFound(
      find.byKey(ValueKey('secretary_todo_command_card_$commandId')),
      description: 'todo command card $commandId',
    );
  }

  Future<void> waitForMemoryCard(String sourceMessageId) {
    return pumpUntilFound(
      find.byKey(ValueKey('secretary_memory_card_$sourceMessageId')),
      description: 'memory card $sourceMessageId',
    );
  }

  Future<void> tapByKey(String key) async {
    final finder = find.byKey(ValueKey(key));
    await pumpUntilFound(finder, description: 'tap target $key');
    await tester.ensureVisible(finder);
    await tester.pump();
    final viewSize = tester.binding.renderView.size;
    if (_shouldNudgeChatListForKey(key)) {
      for (final delta in const [260.0, -260.0, 520.0, -520.0]) {
        final rect = tester.getRect(finder);
        if (rect.bottom <= viewSize.height - 260) break;
        await _jumpChatListBy(delta);
      }
    }
    await tester.tap(finder);
    await tester.pump();
  }

  bool _shouldNudgeChatListForKey(String key) {
    return key.startsWith('secretary_') ||
        key.startsWith('todo_command_review_');
  }

  Future<bool> _jumpChatListBy(double delta) async {
    final chatList = find.byKey(const ValueKey('chat_message_list'));
    if (chatList.evaluate().isEmpty) return false;
    var scrollable = find.descendant(
      of: chatList,
      matching: find.byType(Scrollable),
    );
    if (scrollable.evaluate().isEmpty) {
      scrollable = find.byType(Scrollable);
    }
    if (scrollable.evaluate().isEmpty) return false;
    final state = tester.state<ScrollableState>(scrollable.first);
    final position = state.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) return false;
    position.jumpTo(next);
    await tester.pump();
    return true;
  }

  Future<void> pumpUntilFound(
    Finder finder, {
    required String description,
    Duration timeout = const Duration(seconds: 5),
    Duration step = const Duration(milliseconds: 50),
  }) async {
    await _pumpUntil(
      description,
      () => finder.evaluate().isNotEmpty,
      timeout: timeout,
      step: step,
    );
  }

  Future<void> waitForBackend(
    String description,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
    Duration step = const Duration(milliseconds: 50),
  }) async {
    await _pumpUntil(
      description,
      condition,
      timeout: timeout,
      step: step,
    );
  }

  Future<void> _pumpUntil(
    String description,
    bool Function() condition, {
    required Duration timeout,
    required Duration step,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await tester.pump(step);
    }
    if (condition()) return;
    throw TestFailure(
      'Timed out waiting for $description.\n'
      'Backend trace:\n${backend.debugTrace.join('\n')}',
    );
  }
}
