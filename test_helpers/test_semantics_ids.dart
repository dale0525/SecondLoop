import 'package:flutter/widgets.dart';

final class TestSemanticsIds {
  const TestSemanticsIds._();

  static const String runtimeModeSelfManaged = 'runtime_mode_self_managed';
  static const String runtimeModeManagedPro = 'runtime_mode_managed_pro';
  static const String runtimeModeStatusTitle = 'runtime_mode_status_title';
  static const String runtimeModePageRoot = 'runtime_mode_page_root';
  static const String selfManagedSetupRoot = 'self_managed_setup_root';
  static const String selfManagedAuthorize = 'self_managed_cloudflare_oauth';
  static const String selfManagedDeploy = 'self_managed_verify_connection';
  static const String selfManagedRetry = 'self_managed_retry';
  static const String selfManagedReset = 'self_managed_reset';
  static const String cloudAccountPageRoot = 'cloud_account_page_root';
  static const String chatComposerInput = 'chat_input';
  static const String chatComposerSend = 'chat_send';

  static ValueKey<String> key(String value) => ValueKey<String>(value);
}
