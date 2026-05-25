import 'package:flutter/material.dart';

import '../../ui/sl_button.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'settings_ui.dart';

class CloudAccountAuthSection extends StatelessWidget {
  const CloudAccountAuthSection({
    required this.emailController,
    required this.passwordController,
    required this.busy,
    required this.emailLabel,
    required this.passwordLabel,
    required this.signInLabel,
    required this.signUpLabel,
    required this.forgotPasswordLabel,
    required this.onSignIn,
    required this.onSignUp,
    required this.onForgotPassword,
    super.key,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool busy;
  final String emailLabel;
  final String passwordLabel;
  final String signInLabel;
  final String signUpLabel;
  final String forgotPasswordLabel;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      children: [
        Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('cloud_email_field'),
                controller: emailController,
                decoration: InputDecoration(labelText: emailLabel),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                enabled: !busy,
              ),
              const SizedBox(height: AgentDesignTokens.gapMd),
              TextField(
                key: const ValueKey('cloud_password_field'),
                controller: passwordController,
                decoration: InputDecoration(labelText: passwordLabel),
                obscureText: true,
                enabled: !busy,
                onSubmitted: (_) => onSignIn(),
              ),
              const SizedBox(height: AgentDesignTokens.gapLg),
              Row(
                children: [
                  Expanded(
                    child: SlButton(
                      buttonKey: const ValueKey('cloud_sign_in'),
                      onPressed: busy ? null : onSignIn,
                      child: Text(signInLabel),
                    ),
                  ),
                  const SizedBox(width: AgentDesignTokens.gapMd),
                  Expanded(
                    child: SlButton(
                      buttonKey: const ValueKey('cloud_sign_up'),
                      onPressed: busy ? null : onSignUp,
                      variant: SlButtonVariant.outline,
                      child: Text(signUpLabel),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AgentDesignTokens.gapSm),
              Align(
                alignment: Alignment.centerLeft,
                child: SlButton(
                  buttonKey: const ValueKey('cloud_forgot_password'),
                  onPressed: busy ? null : onForgotPassword,
                  variant: SlButtonVariant.secondary,
                  child: Text(forgotPasswordLabel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
