import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('refresh dependency key changes when active BYOK profile changes',
      () async {
    final backend = _ProfileBackend(<LlmProfile>[
      const LlmProfile(
        id: 'profile-a',
        name: 'Profile A',
        providerType: 'openai-compatible',
        baseUrl: 'https://a.example',
        modelName: 'model-a',
        isActive: true,
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
      const LlmProfile(
        id: 'profile-b',
        name: 'Profile B',
        providerType: 'openai-compatible',
        baseUrl: 'https://b.example',
        modelName: 'model-b',
        isActive: false,
        createdAtMs: 2,
        updatedAtMs: 2,
      ),
    ]);
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final first = await buildTaskPriorityRefreshDependencyKey(
      backend,
      sessionKey,
      subscriptionStatus: SubscriptionStatus.notEntitled,
      gatewayBaseUrl: '',
      modelName: '',
      localeTag: 'en-US',
      cloudUid: null,
    );

    await backend.setActiveLlmProfile(sessionKey, 'profile-b');

    final second = await buildTaskPriorityRefreshDependencyKey(
      backend,
      sessionKey,
      subscriptionStatus: SubscriptionStatus.notEntitled,
      gatewayBaseUrl: '',
      modelName: '',
      localeTag: 'en-US',
      cloudUid: null,
    );

    expect(second, isNot(first));
  });

  test('refresh dependency key falls back when rust bridge is unavailable',
      () async {
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final key = await buildTaskPriorityRefreshDependencyKey(
      _RustBridgeUnavailableBackend(),
      sessionKey,
      subscriptionStatus: SubscriptionStatus.notEntitled,
      gatewayBaseUrl: 'https://fallback.example',
      modelName: 'fallback-model',
      localeTag: 'en-US',
      cloudUid: null,
    );

    expect(key, contains('fallback.example'));
    expect(key, contains('fallback-model'));
  });

  test('refresh dependency key falls back when BYOK profile lookup throws',
      () async {
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final key = await buildTaskPriorityRefreshDependencyKey(
      _ProfileLookupFailureBackend(),
      sessionKey,
      subscriptionStatus: SubscriptionStatus.notEntitled,
      gatewayBaseUrl: 'https://fallback.example',
      modelName: 'fallback-model',
      localeTag: 'en-US',
      cloudUid: null,
    );

    expect(key, contains('fallback.example'));
    expect(key, contains('fallback-model'));
  });

  test('refresh dependency key ignores unsupported active LLM profiles',
      () async {
    final backend = _ProfileBackend(const <LlmProfile>[
      LlmProfile(
        id: 'unsupported-active',
        name: 'Unsupported Active',
        providerType: 'gemini-compatible',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        modelName: 'gemini-1.5-flash',
        isActive: true,
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    ]);
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final key = await buildTaskPriorityRefreshDependencyKey(
      backend,
      sessionKey,
      subscriptionStatus: SubscriptionStatus.notEntitled,
      gatewayBaseUrl: 'https://fallback.example',
      modelName: 'fallback-model',
      localeTag: 'en-US',
      cloudUid: null,
    );

    expect(key, isNot(contains('unsupported-active')));
    expect(key, isNot(contains('gemini-compatible')));
  });
}

final class _ProfileBackend extends AppBackend {
  _ProfileBackend(this._profiles);

  final List<LlmProfile> _profiles;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      List<LlmProfile>.from(_profiles);

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {
    for (var i = 0; i < _profiles.length; i += 1) {
      final profile = _profiles[i];
      _profiles[i] = LlmProfile(
        id: profile.id,
        name: profile.name,
        providerType: profile.providerType,
        baseUrl: profile.baseUrl,
        modelName: profile.modelName,
        isActive: profile.id == profileId,
        createdAtMs: profile.createdAtMs,
        updatedAtMs: profile.updatedAtMs,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RustBridgeUnavailableBackend extends AppBackend {
  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    throw StateError('flutter_rust_bridge has not been initialized');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ProfileLookupFailureBackend extends AppBackend {
  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    throw Exception('backend unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
