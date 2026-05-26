import 'dart:convert';
import 'dart:io';

import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';

typedef CloudflareAuthorizeFn = Future<SelfManagedCloudflareAuthorization>
    Function(String accountLabel);

final class SelfManagedCloudflareAuthorization {
  const SelfManagedCloudflareAuthorization({
    required this.accessToken,
    required this.accountId,
    this.accountName = '',
    this.userEmail = '',
    this.canManageResources = true,
  });

  factory SelfManagedCloudflareAuthorization.placeholder({
    required String accessToken,
    required String accountLabel,
  }) {
    return SelfManagedCloudflareAuthorization(
      accessToken: accessToken,
      accountId: accountLabel,
      accountName: accountLabel,
      canManageResources: false,
    );
  }

  final String accessToken;
  final String accountId;
  final String accountName;
  final String userEmail;
  final bool canManageResources;
}

final class SelfManagedCloudflareAuth {
  SelfManagedCloudflareAuth({
    CloudflareAuthorizeFn? authorize,
  }) : _authorize = authorize ?? _defaultAuthorize;

  final CloudflareAuthorizeFn _authorize;

  Future<SelfManagedCloudflareAuthorization> authorize(String accountLabel) {
    return _authorize(accountLabel);
  }
}

const _wranglerVersion = '4.94.0';
const _oauthScopes = <String>[
  'account:read',
  'user:read',
  'workers:write',
  'workers_kv:write',
  'workers_scripts:write',
  'd1:write',
  'containers:write',
];

Future<SelfManagedCloudflareAuthorization> _defaultAuthorize(
  String accountLabel,
) async {
  final workingDirectory = Directory.current.path;
  final configHome = _wranglerConfigHome(workingDirectory);
  await Directory(configHome).create(recursive: true);
  final existing = await _readExistingOAuthAuthorization(
    accountLabel,
    workingDirectory: workingDirectory,
    configHome: configHome,
  );
  if (existing != null) {
    return existing;
  }

  final loginArgs = <String>[
    'login',
    '--callback-host',
    'localhost',
    for (final scope in _oauthScopes) ...['--scopes', scope],
  ];
  final login = await _runWrangler(
    loginArgs,
    workingDirectory: workingDirectory,
    configHome: configHome,
  );
  if (login.exitCode != 0) {
    throw LocalRuntimeHelperException(
      'cloudflare_oauth_failed',
      _processMessage(login, fallback: 'Cloudflare OAuth login failed.'),
    );
  }

  final afterLogin = await _readExistingOAuthAuthorization(
    accountLabel,
    workingDirectory: workingDirectory,
    configHome: configHome,
  );
  if (afterLogin == null) {
    throw const LocalRuntimeHelperException(
      'cloudflare_oauth_token_unavailable',
      'Cloudflare OAuth token was not available after login.',
    );
  }
  return afterLogin;
}

Future<SelfManagedCloudflareAuthorization?> _readExistingOAuthAuthorization(
  String accountLabel, {
  required String workingDirectory,
  required String configHome,
}) async {
  final tokenResult = await _runWrangler(
    const ['auth', 'token', '--json'],
    workingDirectory: workingDirectory,
    configHome: configHome,
  );
  if (tokenResult.exitCode != 0) {
    return null;
  }
  final tokenJson = _decodeJsonObject(tokenResult.stdout);
  if (tokenJson['type'] != 'oauth') {
    throw const LocalRuntimeHelperException(
      'cloudflare_oauth_required',
      'Cloudflare authorization must come from the OAuth login flow.',
    );
  }
  final token = '${tokenJson['token'] ?? ''}'.trim();
  if (token.isEmpty) {
    throw const LocalRuntimeHelperException(
      'cloudflare_oauth_token_unavailable',
      'Cloudflare OAuth token was empty after login.',
    );
  }

  final whoamiResult = await _runWrangler(
    const ['whoami', '--json'],
    workingDirectory: workingDirectory,
    configHome: configHome,
  );
  if (whoamiResult.exitCode != 0) {
    throw LocalRuntimeHelperException(
      'cloudflare_account_lookup_failed',
      _processMessage(
        whoamiResult,
        fallback: 'Cloudflare account lookup failed after OAuth login.',
      ),
    );
  }
  final whoami = _decodeJsonObject(whoamiResult.stdout);
  final selected = _selectAccount(
    whoami['accounts'],
    accountLabel: accountLabel,
  );
  if (selected == null) {
    throw const LocalRuntimeHelperException(
      'cloudflare_account_not_found',
      'Cloudflare OAuth login did not return an account.',
    );
  }
  return SelfManagedCloudflareAuthorization(
    accessToken: token,
    accountId: selected.id,
    accountName: selected.name,
    userEmail: '${whoami['email'] ?? ''}'.trim(),
  );
}

Future<ProcessResult> _runWrangler(
  List<String> args, {
  required String workingDirectory,
  required String configHome,
}) {
  final command = Platform.environment['SECONDLOOP_WRANGLER_COMMAND'];
  final env = Map<String, String>.from(Platform.environment)
    ..putIfAbsent(
      'npm_config_cache',
      () => '$workingDirectory/.tool/npm-cache',
    )
    ..['WRANGLER_SEND_METRICS'] = 'false'
    ..['XDG_CONFIG_HOME'] = configHome;
  if (command != null && command.trim().isNotEmpty) {
    final shellCommand = [
      command,
      ...args.map(_shellQuote),
    ].join(' ');
    if (Platform.isWindows) {
      return Process.run(
        'cmd.exe',
        ['/c', shellCommand],
        workingDirectory: workingDirectory,
        environment: env,
      );
    }
    return Process.run(
      '/bin/sh',
      ['-lc', shellCommand],
      workingDirectory: workingDirectory,
      environment: env,
    );
  }
  final localWrangler = Platform.isWindows
      ? '$workingDirectory\\.tool\\wrangler\\node_modules\\.bin\\wrangler.cmd'
      : '$workingDirectory/.tool/wrangler/node_modules/.bin/wrangler';
  if (File(localWrangler).existsSync()) {
    return Process.run(
      localWrangler,
      args,
      workingDirectory: workingDirectory,
      environment: env,
    );
  }
  return Process.run(
    'npx',
    ['--yes', 'wrangler@$_wranglerVersion', ...args],
    workingDirectory: workingDirectory,
    environment: env,
  );
}

String _wranglerConfigHome(String workingDirectory) {
  final override =
      Platform.environment['SECONDLOOP_CLOUDFLARE_OAUTH_CONFIG_HOME'];
  if (override != null && override.trim().isNotEmpty) {
    return override.trim();
  }
  return '$workingDirectory/.tool/self-managed-cloudflare-oauth';
}

Map<String, Object?> _decodeJsonObject(Object? output) {
  final raw = _stripAnsi('$output');
  final jsonText = _extractFirstJsonObject(raw);
  if (jsonText == null) {
    throw const LocalRuntimeHelperException(
      'cloudflare_oauth_invalid_output',
      'Cloudflare OAuth helper did not return JSON output.',
    );
  }
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const LocalRuntimeHelperException(
      'cloudflare_oauth_invalid_output',
      'Cloudflare OAuth helper returned non-object JSON output.',
    );
  }
  return decoded.map((key, value) => MapEntry('$key', value));
}

String? _extractFirstJsonObject(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < raw.length; i += 1) {
    final char = raw.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == 0x5c) {
        escaped = true;
      } else if (char == 0x22) {
        inString = false;
      }
      continue;
    }
    if (char == 0x22) {
      inString = true;
    } else if (char == 0x7b) {
      depth += 1;
    } else if (char == 0x7d) {
      depth -= 1;
      if (depth == 0) {
        return raw.substring(start, i + 1);
      }
    }
  }
  return null;
}

_CloudflareAccount? _selectAccount(
  Object? rawAccounts, {
  required String accountLabel,
}) {
  if (rawAccounts is! List || rawAccounts.isEmpty) return null;
  final accounts = <_CloudflareAccount>[
    for (final value in rawAccounts)
      if (value is Map)
        _CloudflareAccount(
          id: '${value['id'] ?? ''}'.trim(),
          name: '${value['name'] ?? ''}'.trim(),
        ),
  ].where((account) => account.id.isNotEmpty).toList(growable: false);
  if (accounts.isEmpty) return null;
  final selector = accountLabel.trim().toLowerCase();
  if (selector.isNotEmpty && selector != 'personal-vault') {
    for (final account in accounts) {
      if (account.id.toLowerCase() == selector ||
          account.name.toLowerCase() == selector) {
        return account;
      }
    }
  }
  if (accounts.length == 1) {
    return accounts.single;
  }
  throw const LocalRuntimeHelperException(
    'cloudflare_account_selection_required',
    'Multiple Cloudflare accounts are available. Enter the target account id or name before retrying OAuth.',
  );
}

String _processMessage(ProcessResult result, {required String fallback}) {
  final stderr = _stripAnsi('${result.stderr}').trim();
  if (stderr.isNotEmpty) return stderr;
  final stdout = _stripAnsi('${result.stdout}').trim();
  if (stdout.isNotEmpty) return stdout;
  return fallback;
}

String _stripAnsi(String value) {
  return value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
}

String _shellQuote(String value) {
  if (value.isEmpty) return "''";
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

final class _CloudflareAccount {
  const _CloudflareAccount({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}
