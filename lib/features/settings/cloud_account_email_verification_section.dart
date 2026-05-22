import 'package:flutter/material.dart';

import '../../ui/sl_button.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'settings_ui.dart';

class CloudAccountEmailVerificationSection extends StatelessWidget {
  const CloudAccountEmailVerificationSection({
    required this.title,
    required this.statusLabel,
    required this.statusValue,
    required this.helpText,
    required this.resendLabel,
    required this.refreshTooltip,
    required this.userInfoBusy,
    required this.verificationBusy,
    required this.verificationCooldownActive,
    required this.emailVerified,
    required this.onRefresh,
    required this.onResend,
    super.key,
    this.loadFailedText,
    this.verificationHint,
  });

  final String title;
  final String statusLabel;
  final String statusValue;
  final String helpText;
  final String resendLabel;
  final String refreshTooltip;
  final bool userInfoBusy;
  final bool verificationBusy;
  final bool verificationCooldownActive;
  final bool? emailVerified;
  final VoidCallback onRefresh;
  final VoidCallback onResend;
  final String? loadFailedText;
  final String? verificationHint;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: title,
      trailing: IconButton(
        onPressed: userInfoBusy ? null : onRefresh,
        icon: const Icon(Icons.refresh_rounded),
        tooltip: refreshTooltip,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(statusLabel),
                  const SizedBox(width: AgentDesignTokens.gapSm),
                  Text(
                    statusValue,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (loadFailedText != null) ...[
                const SizedBox(height: AgentDesignTokens.gapMd),
                SettingsInlineMessage(
                  message: loadFailedText!,
                  tone: SettingsInlineMessageTone.error,
                ),
              ],
              if (verificationHint != null) ...[
                const SizedBox(height: AgentDesignTokens.gapMd),
                SettingsInlineMessage(
                  message: verificationHint!,
                  tone: SettingsInlineMessageTone.success,
                ),
              ],
              if (emailVerified == false) ...[
                const SizedBox(height: AgentDesignTokens.gapMd),
                Text(helpText),
                const SizedBox(height: AgentDesignTokens.gapMd),
                SlButton(
                  buttonKey: const ValueKey('cloud_resend_verification'),
                  onPressed: (verificationBusy || verificationCooldownActive)
                      ? null
                      : onResend,
                  variant: SlButtonVariant.outline,
                  child: Text(resendLabel),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
