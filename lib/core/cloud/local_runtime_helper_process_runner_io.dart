import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_runtime_helper_process.dart';
import 'runtime_manifest.dart';
import 'self_managed_setup_models.dart';

Future<SelfManagedSetupResult> runLocalRuntimeSetupHelper(
  SelfManagedSetupRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  final result = await _runHelper(
    <String, Object?>{
      'action': 'deploy',
      'stream_events': true,
      'cloudflare_account_label': request.cloudflareAccountLabel,
      'provider': request.provider,
      'api_key': request.apiKey,
      'embedding_api_key': request.embeddingApiKey,
      'multimodal_api_key': request.multimodalApiKey,
      'requires_multimodal_llm': request.requiresMultimodalLlm,
      'cloudflare_authorization_method':
          request.cloudflareAuthorizationMethod.name,
      'cloudflare_account_id': request.cloudflareAccountId,
      'cloudflare_api_token': request.cloudflareApiToken,
    },
    onProgress,
  );
  final manifestJson = Map<String, dynamic>.from(
    result['manifest'] as Map? ?? const <String, Object?>{},
  );
  final verificationJson = result['verification'] is Map
      ? Map<String, dynamic>.from(result['verification'] as Map)
      : null;
  return SelfManagedSetupResult(
    manifest: CloudRuntimeManifest.fromJson(manifestJson),
    authToken: '${result['auth_token'] ?? ''}',
    capabilityManifestId: '${result['capability_manifest_id'] ?? ''}',
    verification: verificationJson == null
        ? null
        : ModelCapabilityVerificationResult.fromJson(verificationJson),
  );
}

Future<SelfManagedCloudflareAuthorizationResult>
    runLocalRuntimeCloudflareAuthorizationHelper(
  String accountLabel,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  final result = await _runHelper(
    <String, Object?>{
      'action': 'authorize_cloudflare',
      'stream_events': true,
      'cloudflare_account_label': accountLabel,
    },
    onProgress,
  );
  return SelfManagedCloudflareAuthorizationResult.fromJson(
    Map<String, dynamic>.from(result),
  );
}

Future<SelfManagedRuntimeUninstallResult> runLocalRuntimeUninstallHelper(
  SelfManagedRuntimeUninstallRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  final result = await _runHelper(
    <String, Object?>{
      'action': 'uninstall',
      'stream_events': true,
      'cloudflare_account_label': request.cloudflareAccountLabel,
      'cloudflare_authorization_method':
          request.cloudflareAuthorizationMethod.name,
      'cloudflare_account_id': request.cloudflareAccountId,
      'cloudflare_api_token': request.cloudflareApiToken,
      'runtime_id': request.runtimeId,
    },
    onProgress,
  );
  return SelfManagedRuntimeUninstallResult(
    ok: result['ok'] == true,
    runtimeMode: '${result['runtime_mode'] ?? ''}',
    cloudflareAccountId: '${result['cloudflare_account_id'] ?? ''}',
    removedWorkers: _stringList(result['removed_workers']),
    removedBindings: _stringList(result['removed_bindings']),
    removedSecrets: _stringList(result['removed_secrets']),
  );
}

Future<Map<String, Object?>> _runHelper(
  Map<String, Object?> input,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  final process = await _startHelperProcess();
  process.stdin.writeln(jsonEncode(input));
  await process.stdin.close();

  Map<String, Object?>? result;
  LocalRuntimeHelperException? helperError;
  final stderr = StringBuffer();
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (line.trim().isEmpty) return;
    final decoded = _tryDecodeJsonObject(line);
    if (decoded is! Map) return;
    final event = '${decoded['event'] ?? ''}';
    if (event == 'progress') {
      final progress = Map<String, dynamic>.from(
        decoded['progress'] as Map? ?? const <String, Object?>{},
      );
      final step = _stepFromName('${progress['step'] ?? ''}');
      if (step != null) {
        onProgress(
          SelfManagedSetupProgress(
            step: step,
            message: '${progress['message'] ?? step.name}',
          ),
        );
      }
    } else if (event == 'result') {
      result = Map<String, Object?>.from(
        decoded['result'] as Map? ?? const <String, Object?>{},
      );
    } else if (event == 'error') {
      final error = Map<String, dynamic>.from(
        decoded['error'] as Map? ?? const <String, Object?>{},
      );
      final code = '${error['code'] ?? ''}'.trim();
      final message = '${error['message'] ?? code}'.trim();
      if (code.isNotEmpty) {
        helperError = LocalRuntimeHelperException(
          code,
          message.isEmpty ? code : message,
        );
      }
    }
  }).asFuture<void>();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .listen(stderr.write)
      .asFuture<void>();
  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  if (exitCode != 0) {
    final structuredError = helperError;
    if (structuredError != null) {
      throw structuredError;
    }
    throw LocalRuntimeHelperException(
      'self_managed_helper_failed',
      stderr.toString().trim().isEmpty
          ? 'Self-managed runtime helper failed with exit code $exitCode.'
          : stderr.toString().trim(),
    );
  }
  final payload = result;
  if (payload == null) {
    throw const LocalRuntimeHelperException(
      'self_managed_helper_invalid_output',
      'Self-managed runtime helper did not return a result payload.',
    );
  }
  return payload;
}

Object? _tryDecodeJsonObject(String line) {
  try {
    return jsonDecode(line);
  } on FormatException {
    return null;
  }
}

Future<Process> _startHelperProcess() async {
  final workingDirectory =
      Platform.environment['SECONDLOOP_SELF_MANAGED_HELPER_ROOT'] ??
          Platform.environment['PIXI_PROJECT_ROOT'] ??
          Directory.current.path;
  final command =
      Platform.environment['SECONDLOOP_SELF_MANAGED_HELPER_COMMAND'];
  try {
    if (command != null && command.trim().isNotEmpty) {
      if (Platform.isWindows) {
        return await Process.start(
          'cmd.exe',
          ['/c', command],
          workingDirectory: workingDirectory,
        );
      }
      return await Process.start(
        '/bin/sh',
        ['-lc', command],
        workingDirectory: workingDirectory,
      );
    }
    return await Process.start(
      _defaultDartExecutable(workingDirectory),
      ['run', 'tools/self_managed_runtime_helper.dart'],
      workingDirectory: workingDirectory,
    );
  } on ProcessException catch (error) {
    throw LocalRuntimeHelperException(
      'self_managed_helper_unavailable',
      'Self-managed runtime helper could not start: ${error.message}',
    );
  }
}

String _defaultDartExecutable(String workingDirectory) {
  final fvmDartPath = Platform.isWindows
      ? '$workingDirectory\\.fvm\\flutter_sdk\\bin\\dart.bat'
      : '$workingDirectory/.fvm/flutter_sdk/bin/dart';
  if (File(fvmDartPath).existsSync()) {
    return fvmDartPath;
  }
  return 'dart';
}

SelfManagedSetupStep? _stepFromName(String name) {
  for (final step in SelfManagedSetupStep.values) {
    if (step.name == name) return step;
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => '$item').toList(growable: false);
}
