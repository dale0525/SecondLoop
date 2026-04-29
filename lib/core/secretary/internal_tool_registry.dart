import 'dart:typed_data';

import '../../src/rust/db.dart';
import '../backend/secretary_backend.dart';

final class SecretaryInternalTool {
  const SecretaryInternalTool({
    required this.name,
    required this.scope,
    required this.availability,
    required this.requiresConfirmation,
    required this.auditText,
  });

  final String name;
  final String scope;
  final Set<String> availability;
  final bool requiresConfirmation;
  final String auditText;
}

final class SecretaryInternalToolRegistry {
  const SecretaryInternalToolRegistry._(this._tools);

  factory SecretaryInternalToolRegistry.defaults() {
    return const SecretaryInternalToolRegistry._({
      'memory.search': SecretaryInternalTool(
        name: 'memory.search',
        scope: 'read',
        availability: {'local', 'byok', 'cloud'},
        requiresConfirmation: false,
        auditText: 'Search memory pages',
      ),
      'memory.propose': SecretaryInternalTool(
        name: 'memory.propose',
        scope: 'write',
        availability: {'local', 'byok', 'cloud'},
        requiresConfirmation: false,
        auditText: 'Create a pending memory proposal',
      ),
      'memory.update': SecretaryInternalTool(
        name: 'memory.update',
        scope: 'write',
        availability: {'local', 'byok', 'cloud'},
        requiresConfirmation: true,
        auditText: 'Update confirmed memory',
      ),
      'todo.list': SecretaryInternalTool(
        name: 'todo.list',
        scope: 'read',
        availability: {'local', 'byok', 'cloud'},
        requiresConfirmation: false,
        auditText: 'List open todos for planning',
      ),
      'todo.create': SecretaryInternalTool(
        name: 'todo.create',
        scope: 'write',
        availability: {'local', 'byok', 'cloud'},
        requiresConfirmation: true,
        auditText: 'Create a todo',
      ),
      'todo.update': SecretaryInternalTool(
        name: 'todo.update',
        scope: 'write',
        availability: {'local', 'byok', 'cloud'},
        requiresConfirmation: true,
        auditText: 'Update a todo',
      ),
      'reminder.suggest': SecretaryInternalTool(
        name: 'reminder.suggest',
        scope: 'write',
        availability: {'local', 'byok', 'cloud'},
        requiresConfirmation: true,
        auditText: 'Suggest a reminder',
      ),
      'plan.generate': SecretaryInternalTool(
        name: 'plan.generate',
        scope: 'write',
        availability: {'local', 'byok', 'cloud'},
        requiresConfirmation: false,
        auditText: 'Generate a planning draft',
      ),
    });
  }

  final Map<String, SecretaryInternalTool> _tools;

  SecretaryInternalTool? tryGet(String name) => _tools[name];

  SecretaryInternalTool require(String name) {
    final tool = tryGet(name);
    if (tool == null) {
      throw ArgumentError.value(name, 'name', 'Unknown secretary tool');
    }
    return tool;
  }

  List<SecretaryInternalTool> get tools =>
      List<SecretaryInternalTool>.unmodifiable(_tools.values);
}

final class SecretaryToolCallDraft {
  const SecretaryToolCallDraft({
    required this.toolName,
    required this.status,
    required this.requiresConfirmation,
    this.inputJson,
    this.outputJson,
  });

  final String toolName;
  final String status;
  final bool requiresConfirmation;
  final String? inputJson;
  final String? outputJson;
}

final class SecretaryAuditRunDraft {
  const SecretaryAuditRunDraft({
    required this.triggerKind,
    required this.route,
    required this.status,
    required this.nowMs,
    this.inputSummary,
    this.outputSummary,
    this.error,
    this.toolCalls = const <SecretaryToolCallDraft>[],
  });

  final String triggerKind;
  final String route;
  final String status;
  final int nowMs;
  final String? inputSummary;
  final String? outputSummary;
  final String? error;
  final List<SecretaryToolCallDraft> toolCalls;
}

final class SecretaryAuditTrail {
  const SecretaryAuditTrail({
    required this.run,
    required this.toolCalls,
  });

  final SecretaryRunRecord run;
  final List<SecretaryToolCallRecord> toolCalls;
}

abstract interface class SecretaryAuditRecorder {
  Future<void> recordRun(SecretaryAuditRunDraft draft);
}

final class BackendSecretaryAuditRecorder implements SecretaryAuditRecorder {
  const BackendSecretaryAuditRecorder({
    required this.backend,
    required this.sessionKey,
  });

  final SecretaryBackend backend;
  final Uint8List sessionKey;

  @override
  Future<void> recordRun(SecretaryAuditRunDraft draft) async {
    final run = await backend.createSecretaryRun(
      sessionKey,
      triggerKind: draft.triggerKind,
      route: draft.route,
      status: draft.status,
      inputSummary: draft.inputSummary,
      outputSummary: draft.outputSummary,
      error: draft.error,
      nowMs: draft.nowMs,
    );
    for (final call in draft.toolCalls) {
      await backend.createSecretaryToolCall(
        sessionKey,
        runId: run.id,
        toolName: call.toolName,
        status: call.status,
        requiresConfirmation: call.requiresConfirmation,
        inputJson: call.inputJson,
        outputJson: call.outputJson,
        nowMs: draft.nowMs,
      );
    }
  }
}
