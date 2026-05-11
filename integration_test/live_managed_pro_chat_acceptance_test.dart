import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_store.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/core/cloud/runtime_secretary_app_service.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live managed pro chat creates and targets tasks through app state',
    (tester) async {
      final config = _LiveManagedProConfig.fromEnvironment();
      config.validate();

      final appDir = await Directory.systemTemp.createTemp(
        'secondloop-live-managed-pro-chat-',
      );
      addTearDown(() async {
        if (await appDir.exists()) {
          await appDir.delete(recursive: true);
        }
      });

      final backend = NativeAppBackend(
        appDirProvider: () async => appDir.path,
        storageScope:
            'live-managed-pro-chat-${DateTime.now().microsecondsSinceEpoch}',
        recoverInterruptedExternalImportBatchesOnInit: false,
      );
      await backend.init();
      final sessionKey =
          await backend.initMasterPassword('live-managed-pro-acceptance');
      final conversation = await backend.getOrCreateLoopHomeConversation(
        sessionKey,
      );

      final authController = CloudAuthControllerImpl(
        identityToolkit: FirebaseIdentityToolkitHttp(
          webApiKey: config.firebaseWebApiKey,
        ),
        store: _MemoryCloudAuthStore(),
      );
      await authController.signInWithEmailPassword(
        email: config.email,
        password: config.password,
      );
      final vaultId = authController.uid?.trim();
      expect(vaultId, isNotNull);
      expect(vaultId, isNotEmpty);
      final resolvedVaultId = vaultId!;
      expect(await authController.getIdToken(), isNotEmpty);

      final sender = SecretaryRuntimeConversationSender.hostedManagedPro(
        apiBaseUrl: config.cloudGatewayBaseUrl,
        hostedSessionTokenGetter: authController.getIdToken,
      );
      final service = RuntimeSecretaryAppService(
        sender: sender,
        backend: backend,
        sessionKey: sessionKey,
      );

      final createUserMessage = await backend.insertMessage(
        sessionKey,
        conversation.id,
        role: 'user',
        content: '帮我创建一个任务：完成周报。',
      );
      final createResult = await service.sendAndApply(
        vaultId: resolvedVaultId,
        conversationId: conversation.id,
        message: createUserMessage.content,
        sourceMessageId: createUserMessage.id,
      );
      expect(createResult.metadata.approvalRequired, isFalse);
      expect(
        createResult.metadata.appliedMutations
            .where((mutation) => mutation['entity_type'] == 'task')
            .where((mutation) => mutation['mutation_type'] == 'create'),
        isNotEmpty,
        reason:
            'QA-CHAT-01 must be proven by applied task mutations, not assistant text only. '
            'Runtime result: ${_runtimeResultSnapshot(createResult)}',
      );

      final createdTask = _singleTodoByTitle(
        await backend.listTodos(sessionKey),
        '完成周报',
      );
      expect(createdTask.status, isNot('done'));

      final updateUserMessage = await backend.insertMessage(
        sessionKey,
        conversation.id,
        role: 'user',
        content: '把“完成周报”改到今天 20:00',
      );
      final updateResult = await service.sendAndApply(
        vaultId: resolvedVaultId,
        conversationId: conversation.id,
        message: updateUserMessage.content,
        sourceMessageId: updateUserMessage.id,
      );
      expect(updateResult.metadata.approvalRequired, isTrue);
      expect(
        updateResult.metadata.approvalItems
            .where((item) => item.kind == 'task_mutation_confirmation')
            .where((item) => item.title.contains('完成周报')),
        isNotEmpty,
        reason:
            'QA-CHAT-02 must prove the live runtime targeted the existing task. '
            'Runtime result: ${_runtimeResultSnapshot(updateResult)}',
      );

      final beforeApprovalTask = _singleTodoByTitle(
        await backend.listTodos(sessionKey),
        '完成周报',
      );
      expect(platformIntToNullableInt(beforeApprovalTask.dueAtMs), isNull);
      expect(beforeApprovalTask.status, isNot('done'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _runtimeResultSnapshot(SecretaryRuntimeConversationResult result) {
  return jsonEncode(<String, Object?>{
    'assistant_content': result.assistantContent,
    'response_type': result.metadata.responseType,
    'run_status': result.metadata.runStatus,
    'approval_required': result.metadata.approvalRequired,
    'proposed_mutations': result.metadata.proposedMutations,
    'applied_mutations': result.metadata.appliedMutations,
    'approval_items': result.metadata.approvalItems
        .map(
          (item) => <String, Object?>{
            'id': item.id,
            'task_id': item.taskId,
            'title': item.title,
            'kind': item.kind,
            'reason': item.reason,
            'record': item.record,
          },
        )
        .toList(growable: false),
  });
}

Todo _singleTodoByTitle(List<Todo> todos, String title) {
  final matches = todos.where((todo) => todo.title == title).toList();
  expect(
    matches,
    hasLength(1),
    reason: 'Expected exactly one app task titled "$title".',
  );
  return matches.single;
}

final class _LiveManagedProConfig {
  const _LiveManagedProConfig({
    required this.enabled,
    required this.email,
    required this.password,
    required this.firebaseWebApiKey,
    required this.cloudGatewayBaseUrl,
  });

  final bool enabled;
  final String email;
  final String password;
  final String firebaseWebApiKey;
  final String cloudGatewayBaseUrl;

  factory _LiveManagedProConfig.fromEnvironment() {
    final env = Platform.environment;
    return _LiveManagedProConfig(
      enabled: env['SECONDLOOP_LIVE_MANAGED_PRO_ACCEPTANCE']?.trim() == '1',
      email: env['SECONDLOOP_LIVE_MANAGED_PRO_EMAIL']?.trim() ?? '',
      password: env['SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD']?.trim() ?? '',
      firebaseWebApiKey: _firstNonEmpty([
        env['SECONDLOOP_FIREBASE_WEB_API_KEY'],
        const String.fromEnvironment('SECONDLOOP_FIREBASE_WEB_API_KEY'),
      ]),
      cloudGatewayBaseUrl: _firstNonEmpty([
        env['SECONDLOOP_CLOUD_GATEWAY_BASE_URL'],
        const String.fromEnvironment('SECONDLOOP_CLOUD_GATEWAY_BASE_URL'),
        _envScopedGateway(env),
      ]),
    );
  }

  void validate() {
    final missing = <String>[];
    if (!enabled) missing.add('SECONDLOOP_LIVE_MANAGED_PRO_ACCEPTANCE=1');
    if (email.isEmpty) missing.add('SECONDLOOP_LIVE_MANAGED_PRO_EMAIL');
    if (password.isEmpty) missing.add('SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD');
    if (firebaseWebApiKey.isEmpty) {
      missing.add('SECONDLOOP_FIREBASE_WEB_API_KEY');
    }
    if (cloudGatewayBaseUrl.isEmpty) {
      missing.add('SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING/PROD');
    }
    if (missing.isNotEmpty) {
      fail(
          'Missing live managed pro acceptance configuration: ${missing.join(', ')}');
    }
  }
}

String _envScopedGateway(Map<String, String> env) {
  final cloudEnv = env['SECONDLOOP_CLOUD_ENV']?.trim().toLowerCase();
  if (cloudEnv == 'staging' || cloudEnv == 'stage') {
    return env['SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING']?.trim() ?? '';
  }
  if (cloudEnv == 'prod' || cloudEnv == 'production') {
    return env['SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD']?.trim() ?? '';
  }
  return '';
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

final class _MemoryCloudAuthStore implements CloudAuthStore {
  CloudAuthStoredSession? _session;

  @override
  Future<void> clear() async {
    _session = null;
  }

  @override
  Future<CloudAuthStoredSession?> load() async {
    return _session;
  }

  @override
  Future<void> save(CloudAuthStoredSession session) async {
    _session = session;
  }
}
