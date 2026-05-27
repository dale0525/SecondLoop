import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_shell_style.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'cloud_account_benefits_section.dart';
import 'cloud_account_visual_theme.dart';
import 'settings_ui.dart';

class CloudAccountAuthSection extends StatefulWidget {
  const CloudAccountAuthSection({
    required this.emailController,
    required this.passwordController,
    required this.busy,
    required this.emailLabel,
    required this.passwordLabel,
    required this.signInLabel,
    required this.signUpLabel,
    required this.forgotPasswordLabel,
    required this.agreementLeadLabel,
    required this.privacyPolicyLabel,
    required this.termsOfServiceLabel,
    required this.agreementJoinLabel,
    required this.openAgreementFailedMessage,
    required this.onSignIn,
    required this.onSignUp,
    required this.onForgotPassword,
    this.title,
    this.subtitle,
    this.primaryBadgeLabel,
    this.secondaryBadgeLabel,
    this.contextTitle,
    this.contextBenefits = const [],
    this.contextKey,
    this.errorMessage,
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
  final String agreementLeadLabel;
  final String privacyPolicyLabel;
  final String termsOfServiceLabel;
  final String agreementJoinLabel;
  final String openAgreementFailedMessage;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onForgotPassword;
  final String? title;
  final String? subtitle;
  final String? primaryBadgeLabel;
  final String? secondaryBadgeLabel;
  final String? contextTitle;
  final List<CloudAccountBenefit> contextBenefits;
  final Key? contextKey;
  final String? errorMessage;

  @override
  State<CloudAccountAuthSection> createState() =>
      _CloudAccountAuthSectionState();
}

class _CloudAccountAuthSectionState extends State<CloudAccountAuthSection> {
  static final Uri _privacyPolicyUri =
      Uri.parse('https://secondloop.app/privacy');
  static final Uri _termsOfServiceUri =
      Uri.parse('https://secondloop.app/terms');

  bool _agreementAccepted = false;

  Future<void> _openLegalDocument(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (opened || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.openAgreementFailedMessage),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CloudAccountVisualTheme(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showContext = widget.contextBenefits.isNotEmpty &&
              widget.contextTitle?.trim().isNotEmpty == true;
          final wide = showContext && constraints.maxWidth >= 760;
          final form = _AuthFormSection(
            emailController: widget.emailController,
            passwordController: widget.passwordController,
            busy: widget.busy,
            agreementAccepted: _agreementAccepted,
            title: widget.title,
            subtitle: widget.subtitle,
            primaryBadgeLabel: widget.primaryBadgeLabel,
            secondaryBadgeLabel: widget.secondaryBadgeLabel,
            emailLabel: widget.emailLabel,
            passwordLabel: widget.passwordLabel,
            signInLabel: widget.signInLabel,
            signUpLabel: widget.signUpLabel,
            forgotPasswordLabel: widget.forgotPasswordLabel,
            agreementLeadLabel: widget.agreementLeadLabel,
            privacyPolicyLabel: widget.privacyPolicyLabel,
            termsOfServiceLabel: widget.termsOfServiceLabel,
            agreementJoinLabel: widget.agreementJoinLabel,
            errorMessage: widget.errorMessage,
            onAgreementChanged: widget.busy
                ? null
                : (value) {
                    setState(() => _agreementAccepted = value ?? false);
                  },
            onOpenPrivacyPolicy: () => _openLegalDocument(_privacyPolicyUri),
            onOpenTermsOfService: () => _openLegalDocument(_termsOfServiceUri),
            onSignIn: widget.onSignIn,
            onSignUp: widget.onSignUp,
            onForgotPassword: widget.onForgotPassword,
          );
          final contextRail = showContext
              ? _AuthContextSection(
                  title: widget.contextTitle!,
                  benefits: widget.contextBenefits,
                  surfaceKey: widget.contextKey,
                )
              : null;

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: form),
                const SizedBox(width: AgentDesignTokens.gapLg),
                SizedBox(width: 280, child: contextRail),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              form,
              if (contextRail != null) ...[
                const SizedBox(height: AgentDesignTokens.gapMd),
                contextRail,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AuthFormSection extends StatelessWidget {
  const _AuthFormSection({
    required this.emailController,
    required this.passwordController,
    required this.busy,
    required this.agreementAccepted,
    required this.emailLabel,
    required this.passwordLabel,
    required this.signInLabel,
    required this.signUpLabel,
    required this.forgotPasswordLabel,
    required this.agreementLeadLabel,
    required this.privacyPolicyLabel,
    required this.termsOfServiceLabel,
    required this.agreementJoinLabel,
    required this.onAgreementChanged,
    required this.onOpenPrivacyPolicy,
    required this.onOpenTermsOfService,
    required this.onSignIn,
    required this.onSignUp,
    required this.onForgotPassword,
    this.title,
    this.subtitle,
    this.primaryBadgeLabel,
    this.secondaryBadgeLabel,
    this.errorMessage,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool busy;
  final bool agreementAccepted;
  final String? title;
  final String? subtitle;
  final String? primaryBadgeLabel;
  final String? secondaryBadgeLabel;
  final String emailLabel;
  final String passwordLabel;
  final String signInLabel;
  final String signUpLabel;
  final String forgotPasswordLabel;
  final String agreementLeadLabel;
  final String privacyPolicyLabel;
  final String termsOfServiceLabel;
  final String agreementJoinLabel;
  final String? errorMessage;
  final ValueChanged<bool?>? onAgreementChanged;
  final VoidCallback onOpenPrivacyPolicy;
  final VoidCallback onOpenTermsOfService;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      children: [
        Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapXl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null || subtitle != null) ...[
                _AuthHeader(
                  title: title,
                  subtitle: subtitle,
                  primaryBadgeLabel: primaryBadgeLabel,
                  secondaryBadgeLabel: secondaryBadgeLabel,
                ),
                const SizedBox(height: AgentDesignTokens.gapLg),
              ],
              if (errorMessage != null) ...[
                SettingsInlineMessage(
                  message: errorMessage!,
                  tone: SettingsInlineMessageTone.error,
                ),
                const SizedBox(height: AgentDesignTokens.gapLg),
              ],
              _AuthTextField(
                fieldKey: const ValueKey('cloud_email_field'),
                controller: emailController,
                label: emailLabel,
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                enabled: !busy,
              ),
              const SizedBox(height: AgentDesignTokens.gapLg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      passwordLabel,
                      style: _fieldLabelStyle(context),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('cloud_forgot_password'),
                    onPressed: busy ? null : onForgotPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AgentDesignTokens.gapXs,
                        vertical: AgentDesignTokens.gapXs,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(forgotPasswordLabel),
                  ),
                ],
              ),
              const SizedBox(height: AgentDesignTokens.gapXs),
              _AuthTextField(
                fieldKey: const ValueKey('cloud_password_field'),
                controller: passwordController,
                icon: Icons.lock_outline_rounded,
                obscureText: true,
                enabled: !busy,
                onSubmitted: (_) {
                  if (!busy && agreementAccepted) onSignIn();
                },
              ),
              const SizedBox(height: AgentDesignTokens.gapLg),
              _TermsAgreement(
                accepted: agreementAccepted,
                enabled: !busy,
                leadLabel: agreementLeadLabel,
                privacyPolicyLabel: privacyPolicyLabel,
                termsOfServiceLabel: termsOfServiceLabel,
                joinLabel: agreementJoinLabel,
                onChanged: onAgreementChanged,
                onOpenPrivacyPolicy: onOpenPrivacyPolicy,
                onOpenTermsOfService: onOpenTermsOfService,
              ),
              const SizedBox(height: AgentDesignTokens.gapLg),
              _AuthActions(
                busy: busy,
                agreementAccepted: agreementAccepted,
                signInLabel: signInLabel,
                signUpLabel: signUpLabel,
                onSignIn: onSignIn,
                onSignUp: onSignUp,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({
    required this.title,
    required this.subtitle,
    required this.primaryBadgeLabel,
    required this.secondaryBadgeLabel,
  });

  final String? title;
  final String? subtitle;
  final String? primaryBadgeLabel;
  final String? secondaryBadgeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Text(
            title!,
            style: theme.textTheme.titleLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        if (subtitle != null) ...[
          const SizedBox(height: AgentDesignTokens.gapXs),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
        if (primaryBadgeLabel != null || secondaryBadgeLabel != null) ...[
          const SizedBox(height: AgentDesignTokens.gapMd),
          Wrap(
            spacing: AgentDesignTokens.gapXs,
            runSpacing: AgentDesignTokens.gapXs,
            children: [
              if (primaryBadgeLabel != null)
                _StatusPill(
                  icon: Icons.verified_user_outlined,
                  label: primaryBadgeLabel!,
                  emphasized: true,
                ),
              if (secondaryBadgeLabel != null)
                _StatusPill(
                  icon: Icons.cloud_done_outlined,
                  label: secondaryBadgeLabel!,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = SlTokens.of(context);
    final foreground = emphasized ? scheme.primary : scheme.onSurfaceVariant;
    final background = emphasized
        ? scheme.primaryContainer.withOpacity(
            theme.brightness == Brightness.dark ? 0.42 : 0.72,
          )
        : tokens.surface2.withOpacity(0.72);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.fieldKey,
    required this.controller,
    required this.icon,
    this.label,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.onSubmitted,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final IconData icon;
  final String? label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      borderSide: BorderSide(color: tokens.borderSubtle),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      borderSide: BorderSide(color: scheme.primary, width: 1.4),
    );
    final field = TextField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18),
        prefixIconColor: scheme.onSurfaceVariant,
        filled: true,
        fillColor: tokens.surface2.withOpacity(0.45),
        enabledBorder: border,
        disabledBorder: border,
        border: border,
        focusedBorder: focusedBorder,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AgentDesignTokens.gapMd,
          vertical: AgentDesignTokens.gapMd,
        ),
      ),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      enabled: enabled,
      onSubmitted: onSubmitted,
    );

    if (label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label!, style: _fieldLabelStyle(context)),
        const SizedBox(height: AgentDesignTokens.gapXs),
        field,
      ],
    );
  }
}

class _AuthActions extends StatelessWidget {
  const _AuthActions({
    required this.busy,
    required this.agreementAccepted,
    required this.signInLabel,
    required this.signUpLabel,
    required this.onSignIn,
    required this.onSignUp,
  });

  final bool busy;
  final bool agreementAccepted;
  final String signInLabel;
  final String signUpLabel;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final authButtonTheme = theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            primary: isDark ? AppShellPalette.darkInk : AppShellPalette.ink,
            onPrimary: isDark ? AppShellPalette.ink : Colors.white,
          ),
        );
        final signInButton = Theme(
          data: authButtonTheme,
          child: SlButton(
            buttonKey: const ValueKey('cloud_sign_in'),
            onPressed: busy || !agreementAccepted ? null : onSignIn,
            icon: const Icon(Icons.login_rounded, size: 18),
            child: Text(signInLabel),
          ),
        );
        final signUpButton = Theme(
          data: authButtonTheme,
          child: SlButton(
            buttonKey: const ValueKey('cloud_sign_up'),
            onPressed: busy || !agreementAccepted ? null : onSignUp,
            variant: SlButtonVariant.outline,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            child: Text(signUpLabel),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              signInButton,
              const SizedBox(height: AgentDesignTokens.gapSm),
              signUpButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: signInButton),
            const SizedBox(width: AgentDesignTokens.gapMd),
            Expanded(child: signUpButton),
          ],
        );
      },
    );
  }
}

class _TermsAgreement extends StatefulWidget {
  const _TermsAgreement({
    required this.accepted,
    required this.enabled,
    required this.leadLabel,
    required this.privacyPolicyLabel,
    required this.termsOfServiceLabel,
    required this.joinLabel,
    required this.onChanged,
    required this.onOpenPrivacyPolicy,
    required this.onOpenTermsOfService,
  });

  final bool accepted;
  final bool enabled;
  final String leadLabel;
  final String privacyPolicyLabel;
  final String termsOfServiceLabel;
  final String joinLabel;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback onOpenPrivacyPolicy;
  final VoidCallback onOpenTermsOfService;

  @override
  State<_TermsAgreement> createState() => _TermsAgreementState();
}

class _TermsAgreementState extends State<_TermsAgreement> {
  late final TapGestureRecognizer _privacyRecognizer;
  late final TapGestureRecognizer _termsRecognizer;

  @override
  void initState() {
    super.initState();
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = widget.onOpenPrivacyPolicy;
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = widget.onOpenTermsOfService;
  }

  @override
  void didUpdateWidget(covariant _TermsAgreement oldWidget) {
    super.didUpdateWidget(oldWidget);
    _privacyRecognizer.onTap = widget.onOpenPrivacyPolicy;
    _termsRecognizer.onTap = widget.onOpenTermsOfService;
  }

  @override
  void dispose() {
    _privacyRecognizer.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = SlTokens.of(context);
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.35,
    );
    final linkStyle = bodyStyle?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface2.withOpacity(0.42),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        onTap: widget.enabled
            ? () => widget.onChanged?.call(!widget.accepted)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AgentDesignTokens.gapSm,
            vertical: AgentDesignTokens.gapXs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                key: const ValueKey('cloud_terms_consent'),
                value: widget.accepted,
                onChanged: widget.enabled ? widget.onChanged : null,
                activeColor: scheme.primary,
                checkColor: Colors.white,
                side: BorderSide(color: scheme.onSurfaceVariant, width: 1.4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: AgentDesignTokens.gapXs),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: bodyStyle,
                    children: [
                      TextSpan(text: '${widget.leadLabel} '),
                      TextSpan(
                        text: widget.privacyPolicyLabel,
                        style: linkStyle,
                        recognizer: _privacyRecognizer,
                      ),
                      TextSpan(text: ' ${widget.joinLabel} '),
                      TextSpan(
                        text: widget.termsOfServiceLabel,
                        style: linkStyle,
                        recognizer: _termsRecognizer,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthContextSection extends StatelessWidget {
  const _AuthContextSection({
    required this.title,
    required this.benefits,
    this.surfaceKey,
  });

  final String title;
  final List<CloudAccountBenefit> benefits;
  final Key? surfaceKey;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: title,
      surfaceKey: surfaceKey,
      children: [
        for (final benefit in benefits)
          SettingsRow(
            leading: Icon(benefit.icon),
            title: benefit.title,
            body: benefit.body,
            dense: true,
          ),
      ],
    );
  }
}

TextStyle? _fieldLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelMedium?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
    fontWeight: FontWeight.w700,
  );
}
