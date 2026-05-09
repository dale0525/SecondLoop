typedef CloudflareAuthorizeFn = Future<String> Function(String accountLabel);

final class SelfManagedCloudflareAuth {
  SelfManagedCloudflareAuth({
    CloudflareAuthorizeFn? authorize,
  }) : _authorize = authorize ?? _defaultAuthorize;

  final CloudflareAuthorizeFn _authorize;

  Future<String> authorize(String accountLabel) {
    return _authorize(accountLabel);
  }
}

Future<String> _defaultAuthorize(String accountLabel) async {
  if (accountLabel.trim().isEmpty) {
    throw StateError('cloudflare_auth_failed');
  }
  return 'cloudflare-token-$accountLabel';
}
