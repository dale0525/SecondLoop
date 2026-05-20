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
      );
      await backend.init();
      final sessionKey =
          await backend.initMasterPassword('live-managed-pro-acceptance');
      final conversation = await backend.createConversation(
        sessionKey,
        'Live managed pro task acceptance',
      );
      final taskTitle = '完成周报 ${DateTime.now().microsecondsSinceEpoch}';

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
        content: '帮我创建一个任务：$taskTitle。',
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
      expect(
        createResult.metadata.appliedMutations
            .where((mutation) => mutation['entity_type'] == 'task')
            .where((mutation) => mutation['mutation_type'] == 'create')
            .where((mutation) {
          final record = mutation['record'];
          return record is Map && record['title'] == taskTitle;
        }),
        isNotEmpty,
        reason:
            'Managed pro task creation must be proven from runtime metadata. '
            'Runtime result: ${_runtimeResultSnapshot(createResult)}',
      );

      final updateUserMessage = await backend.insertMessage(
        sessionKey,
        conversation.id,
        role: 'user',
        content: '把“$taskTitle”改到今天 20:00',
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
            .where((item) => item.title.contains(taskTitle)),
        isNotEmpty,
        reason:
            'QA-CHAT-02 must prove the live runtime targeted the existing task. '
            'Runtime result: ${_runtimeResultSnapshot(updateResult)}',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'live managed pro chat uses web research citations and carries follow-up context',
    (tester) async {
      final config = _LiveManagedProConfig.fromEnvironment();
      config.validate();

      final appDir = await Directory.systemTemp.createTemp(
        'secondloop-live-managed-pro-chat-search-',
      );
      addTearDown(() async {
        if (await appDir.exists()) {
          await appDir.delete(recursive: true);
        }
      });

      final backend = NativeAppBackend(
        appDirProvider: () async => appDir.path,
        storageScope:
            'live-managed-pro-chat-search-${DateTime.now().microsecondsSinceEpoch}',
      );
      await backend.init();
      final sessionKey =
          await backend.initMasterPassword('live-managed-pro-acceptance');
      final conversation = await backend.createConversation(
        sessionKey,
        'Live managed pro search acceptance',
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
      final resolvedVaultId = authController.uid?.trim();
      expect(resolvedVaultId, isNotNull);
      expect(resolvedVaultId, isNotEmpty);

      final sender = SecretaryRuntimeConversationSender.hostedManagedPro(
        apiBaseUrl: config.cloudGatewayBaseUrl,
        hostedSessionTokenGetter: authController.getIdToken,
      );
      final service = RuntimeSecretaryAppService(
        sender: sender,
        backend: backend,
        sessionKey: sessionKey,
      );

      final searchUserMessage = await backend.insertMessage(
        sessionKey,
        conversation.id,
        role: 'user',
        content: '查一下最近 Apple 发布会有哪些新产品，给我带来源。',
      );
      final searchResult = await service.sendAndApply(
        vaultId: resolvedVaultId!,
        conversationId: conversation.id,
        message: searchUserMessage.content,
        sourceMessageId: searchUserMessage.id,
      );
      expect(
        searchResult.metadata.webResearchDrafts,
        isNotEmpty,
        reason:
            'QA-CHAT-05B must prove the runtime returned cited web research metadata. '
            'Runtime result: ${_runtimeResultSnapshot(searchResult)}',
      );
      expect(
        _webResearchCitationUrls(searchResult),
        isNotEmpty,
        reason:
            'QA-CHAT-05B must include traceable citations, not only assistant text. '
            'Runtime result: ${_runtimeResultSnapshot(searchResult)}',
      );
      expect(
        _webResearchQueries(searchResult),
        everyElement(
          allOf(
            contains(
              RegExp(r'Apple|iPhone|AirPods|Apple Watch|WWDC|苹果|蘋果|アップル'),
            ),
          ),
        ),
        reason:
            'QA-CHAT-05B must execute concise Apple-related search queries. '
            'Runtime result: ${_runtimeResultSnapshot(searchResult)}',
      );
      expect(
        _webResearchCitationDomains(searchResult),
        isNot(
          contains(
            anyOf(
              contains('dictionary'),
              contains('collins'),
              contains('egrammarbook'),
              contains('merriam'),
              contains('cambridge'),
            ),
          ),
        ),
        reason:
            'QA-CHAT-05B must not accept generic dictionary-style search results. '
            'Runtime result: ${_runtimeResultSnapshot(searchResult)}',
      );

      final followUpUserMessage = await backend.insertMessage(
        sessionKey,
        conversation.id,
        role: 'user',
        content: '介绍一下新的手机产品参数。',
      );
      final followUpResult = await service.sendAndApply(
        vaultId: resolvedVaultId,
        conversationId: conversation.id,
        message: followUpUserMessage.content,
        sourceMessageId: followUpUserMessage.id,
      );

      expect(
        followUpResult.assistantContent,
        contains(RegExp(r'iPhone|手机')),
        reason:
            'QA-CHAT-05C must carry the Apple launch phone context into the follow-up. '
            'Runtime result: ${_runtimeResultSnapshot(followUpResult)}',
      );
      expect(
        followUpResult.assistantContent,
        isNot(contains(RegExp(r'重新说明|再说明|哪.*手机'))),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
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
    'web_research_drafts': result.metadata.webResearchDrafts,
    'tool_trace_ids': result.metadata.toolTraceIds,
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

List<String> _webResearchCitationUrls(
    SecretaryRuntimeConversationResult result) {
  final urls = <String>[];
  for (final draft in result.metadata.webResearchDrafts) {
    final rawCitations = draft['citations'];
    if (rawCitations is! List) continue;
    for (final citation in rawCitations.whereType<Map>()) {
      final url = citation['url'];
      if (url is String && url.trim().isNotEmpty) {
        urls.add(url.trim());
      }
    }
  }
  return urls;
}

List<String> _webResearchQueries(SecretaryRuntimeConversationResult result) {
  return result.metadata.webResearchDrafts
      .map((draft) => draft['query'])
      .whereType<String>()
      .map((query) => query.trim())
      .where((query) => query.isNotEmpty)
      .toList(growable: false);
}

List<String> _webResearchCitationDomains(
    SecretaryRuntimeConversationResult result) {
  return _webResearchCitationUrls(result)
      .map((url) => Uri.tryParse(url)?.host ?? '')
      .map((host) => host.replaceFirst(RegExp(r'^www\.'), '').toLowerCase())
      .where((host) => host.isNotEmpty)
      .toList(growable: false);
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
