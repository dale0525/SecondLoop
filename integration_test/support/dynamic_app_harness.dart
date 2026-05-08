import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/task_priority_ai_enhancement_prefs.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/agent_digest_settings_page.dart';
import 'package:secondloop/features/settings/ai_ask_ai_settings_page.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';

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
    String? cloudUid,
    String? cloudEmail,
    bool? cloudEmailVerified,
    String? cloudIdToken,
    String cloudGatewayBaseUrl = '',
    bool subscriptionEntitled = false,
    bool? canManageSubscription,
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
    final cloudAuthController = _HarnessCloudAuthController(
      uid: cloudUid,
      email: cloudEmail,
      emailVerified: cloudEmailVerified ?? (cloudUid == null ? null : true),
      idToken: cloudIdToken,
    );
    final subscriptionController = _HarnessSubscriptionController(
      status: subscriptionEntitled
          ? SubscriptionStatus.entitled
          : SubscriptionStatus.unknown,
      canManageSubscription:
          canManageSubscription ?? (subscriptionEntitled ? true : null),
    );
    final cloudGatewayConfig = CloudGatewayConfig(
      baseUrl: cloudGatewayBaseUrl,
      modelName: CloudGatewayConfig.defaultConfig.modelName,
    );
    final hasCloudContext = (cloudUid?.trim().isNotEmpty ?? false) ||
        (cloudEmail?.trim().isNotEmpty ?? false) ||
        (cloudIdToken?.trim().isNotEmpty ?? false) ||
        cloudGatewayBaseUrl.trim().isNotEmpty ||
        subscriptionEntitled;

    Widget appShell = SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: const AppShell(),
    );
    if (hasCloudContext) {
      appShell = CloudAuthScope(
        controller: cloudAuthController,
        gatewayConfig: cloudGatewayConfig,
        child: SubscriptionScope(
          controller: subscriptionController,
          child: appShell,
        ),
      );
    }
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
              child: appShell,
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

  Future<void> openSettings() async {
    final chatSettingsButton = find.byKey(const ValueKey('chat_open_settings'));
    if (chatSettingsButton.evaluate().isNotEmpty) {
      await tester.ensureVisible(chatSettingsButton);
      await tester.tap(chatSettingsButton);
      await tester.pump();
    } else {
      final railSettingsButton = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.settings_outlined),
      );
      await pumpUntilFound(
        railSettingsButton,
        description: 'desktop settings tab',
      );
      await tester.ensureVisible(railSettingsButton.first);
      await tester.tap(railSettingsButton.first);
      await tester.pump();
    }
    await pumpUntilFound(
      find.byType(SettingsPage),
      description: 'settings page',
    );
  }

  Future<void> openAiSettings() async {
    await tapByKey('settings_ai_source');
    await pumpUntilFound(
      find.byType(AiSettingsPage),
      description: 'AI settings page',
    );
  }

  Future<void> openAskAiSettings() async {
    await tapByKey('ai_settings_open_ask_ai_settings');
    await pumpUntilFound(
      find.byType(AiAskAiSettingsPage),
      description: 'Ask AI settings page',
    );
  }

  Future<void> openCloudAccountFromAskAi() async {
    await tapByKey('ask_ai_settings_open_cloud_account');
    await pumpUntilFound(
      find.byType(CloudAccountPage),
      description: 'cloud account page',
    );
  }

  Future<void> openAgentDigestSettings() async {
    await tapByKey('settings_agent_digest');
    await pumpUntilFound(
      find.byType(AgentDigestSettingsPage),
      description: 'agent digest settings page',
    );
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

final class _HarnessCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  _HarnessCloudAuthController({
    required String? uid,
    required String? email,
    required bool? emailVerified,
    required String? idToken,
  })  : _uid = uid,
        _email = email,
        _emailVerified = emailVerified,
        _idToken = idToken;

  String? _uid;
  String? _email;
  bool? _emailVerified;
  String? _idToken;

  @override
  String? get uid => _uid;

  @override
  String? get email => _email;

  @override
  bool? get emailVerified => _emailVerified;

  @override
  Future<String?> getIdToken() async => _idToken;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {
    _emailVerified = false;
    notifyListeners();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
  }) async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _uid ??= 'automation-user';
    _email = email;
    _emailVerified ??= true;
    _idToken ??= 'automation-id-token';
    notifyListeners();
  }

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await signInWithEmailPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _email = null;
    _emailVerified = null;
    _idToken = null;
    notifyListeners();
  }
}

final class _HarnessSubscriptionController extends ChangeNotifier
    implements SubscriptionDetailsController {
  _HarnessSubscriptionController({
    required SubscriptionStatus status,
    required this.canManageSubscription,
  }) : _status = status;

  SubscriptionStatus _status;

  @override
  final bool? canManageSubscription;

  @override
  SubscriptionStatus get status => _status;

  void setStatus(SubscriptionStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }
}
