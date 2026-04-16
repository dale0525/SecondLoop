// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'web_local_runtime_recovery_base.dart';

WebLocalRuntimeRecovery createWebLocalRuntimeRecovery() =>
    const _BrowserWebLocalRuntimeRecovery();

final class _BrowserWebLocalRuntimeRecovery implements WebLocalRuntimeRecovery {
  const _BrowserWebLocalRuntimeRecovery();

  static const _kResetAttemptPrefix = 'secondloop.web_native_reset_attempt_v1:';

  @override
  bool hasAttemptedReset({required String uid}) =>
      html.window.sessionStorage[_key(uid)] == '1';

  @override
  void markResetAttempted({required String uid}) {
    html.window.sessionStorage[_key(uid)] = '1';
  }

  @override
  void clearResetAttempted({required String uid}) {
    html.window.sessionStorage.remove(_key(uid));
  }

  @override
  Future<void> reloadPage() async {
    html.window.location.reload();
  }

  static String _key(String uid) => '$_kResetAttemptPrefix${uid.trim()}';
}
