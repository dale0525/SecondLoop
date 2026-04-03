import 'dart:io';

import 'package:secondloop/core/update/app_update_models.dart';

import 'generate_update_manifest_lib.dart';

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);
  final inputDir = _requiredArg(parsed, 'input-dir');
  final outputDir = _requiredArg(parsed, 'output-dir');
  final version = _requiredArg(parsed, 'version');
  final baseDownloadUrl = _requiredArg(parsed, 'base-download-url');
  final releasePageUrl = parsed['release-page-url'] ??
      _releasePageUrlFromRepo(
        repo: parsed['repo'],
        version: version,
      );
  final windowsAppId = parsed['windows-app-id'] ??
      Platform.environment['SECONDLOOP_APP_ID'] ??
      'com.secondloop.secondloop';
  final windowsChannel = parsed['windows-channel'];
  final signingPrivateKey = parsed['signing-private-key'] ??
      Platform.environment['SECONDLOOP_UPDATE_SIGNING_PRIVATE_KEY'];
  final publishedAt = parsed['published-at'];

  final generated = await generateUpdateManifest(
    inputDirPath: inputDir,
    version: version,
    baseDownloadUrl: baseDownloadUrl,
    releasePageUrl: releasePageUrl,
    windowsAppId: windowsAppId,
    windowsChannel: windowsChannel,
    publishedAt: publishedAt == null || publishedAt.trim().isEmpty
        ? null
        : DateTime.parse(publishedAt).toUtc(),
    signingPrivateKeyBase64: signingPrivateKey,
  );

  final output = Directory(outputDir);
  await output.create(recursive: true);

  final manifestFile =
      File('${output.path}${Platform.pathSeparator}latest.json');
  await manifestFile.writeAsString(generated.jsonText);
  stdout.writeln(manifestFile.path);

  final signature = generated.signatureBase64;
  if (signature != null) {
    final signatureFile =
        File('${output.path}${Platform.pathSeparator}latest.json.sig');
    await signatureFile.writeAsString('$signature\n');
    stdout.writeln(signatureFile.path);
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final parsed = <String, String>{};
  for (var index = 0; index < args.length; index += 1) {
    final token = args[index];
    if (!token.startsWith('--')) {
      throw ArgumentError('unexpected_argument:$token');
    }
    final key = token.substring(2);
    if (index + 1 >= args.length) {
      throw ArgumentError('missing_value_for:$token');
    }
    parsed[key] = args[index + 1];
    index += 1;
  }
  return parsed;
}

String _requiredArg(Map<String, String> parsed, String key) {
  final value = parsed[key]?.trim();
  if (value == null || value.isEmpty) {
    throw ArgumentError('missing_required_argument:--$key');
  }
  return value;
}

String? _releasePageUrlFromRepo({
  required String? repo,
  required String version,
}) {
  final trimmedRepo = repo?.trim();
  if (trimmedRepo == null || trimmedRepo.isEmpty) {
    return null;
  }
  final normalizedVersion = normalizeStrictAppVersion(
    version,
    argumentName: 'version',
  );
  return 'https://github.com/$trimmedRepo/releases/tag/v$normalizedVersion';
}

String? releasePageUrlFromRepoForTest({
  required String? repo,
  required String version,
}) =>
    _releasePageUrlFromRepo(repo: repo, version: version);
