import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/cloud/cloud_auth_controller.dart';
import '../../core/cloud/firebase_identity_toolkit.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_usage_client.dart';
import '../../core/cloud/vault_attachments_client.dart';
import '../../core/cloud/vault_usage_client.dart';
import '../../core/subscription/cloud_subscription_controller.dart';
import '../../core/subscription/creem_billing_client.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../i18n/strings.g.dart';
import '../agent_ui/agent_ui_acceptance_driver.dart';
import 'cloud_account_auth_section.dart';
import 'cloud_account_benefits_section.dart';
import 'cloud_account_entry_mode.dart';
import 'cloud_account_email_verification_section.dart';
import 'cloud_account_identity_section.dart';
import 'cloud_account_subscription_section.dart';
import 'cloud_usage_card.dart';
import 'settings_ui.dart';
import 'vault_usage_card.dart';

typedef BillingClientFactory = BillingClient Function({
  required Future<String?> Function() idTokenGetter,
  required String cloudGatewayBaseUrl,
});

class CloudAccountPanel extends StatefulWidget {
  const CloudAccountPanel({
    super.key,
    this.billingClient,
    this.billingClientFactory,
    this.cloudUsageClient,
    this.vaultUsageClient,
    this.vaultAttachmentsClient,
    this.vaultConfigStore,
    this.isWebOverride,
    this.entryMode = CloudAccountEntryMode.settings,
    this.onEntitled,
  });

  final BillingClient? billingClient;
  final BillingClientFactory? billingClientFactory;
  final CloudUsageClient? cloudUsageClient;
  final VaultUsageClient? vaultUsageClient;
  final VaultAttachmentsClient? vaultAttachmentsClient;
  final SyncConfigStore? vaultConfigStore;
  final bool? isWebOverride;
  final CloudAccountEntryMode entryMode;
  final VoidCallback? onEntitled;

  @override
  State<CloudAccountPanel> createState() => _CloudAccountPanelState();
}

class _CloudAccountPanelState extends State<CloudAccountPanel> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;

  bool _userInfoBusy = false;
  Object? _userInfoError;
  String? _userInfoUid;

  bool _verificationBusy = false;
  String? _verificationHint;
  static const Duration _verificationResendCooldown = Duration(seconds: 60);
  Timer? _verificationCooldownTimer;
  int _verificationCooldownSeconds = 0;

  bool _subBusy = false;
  Object? _subError;
  String? _subscriptionUid;

  bool _billingBusy = false;
  Object? _billingError;
  BillingClient? _ownedBillingClient;
  DisposableBillingClient? _ownedDisposableBillingClient;
  CloudAuthController? _ownedBillingAuthController;
  String? _ownedBillingGatewayBaseUrl;
  BillingClientFactory? _ownedBillingClientFactory;
  bool _onboardingCompletionScheduled = false;

  bool get _verificationCooldownActive => _verificationCooldownSeconds > 0;

  static final RegExp _jsonStringErrorPattern =
      RegExp(r'"error"\s*:\s*"([^"]+)"');
  static final RegExp _jsonCodeErrorPattern = RegExp(r'"code"\s*:\s*"([^"]+)"');

  CloudSubscriptionController? _subscriptionController(BuildContext context) {
    final controller = SubscriptionScope.maybeOf(context);
    return controller is CloudSubscriptionController ? controller : null;
  }

  SubscriptionDetailsController? _subscriptionDetailsController(
      BuildContext context) {
    final controller = SubscriptionScope.maybeOf(context);
    return controller is SubscriptionDetailsController ? controller : null;
  }

  BillingClient? _billingClient(BuildContext context) {
    final override = widget.billingClient;
    if (override != null) return override;

    final scope = CloudAuthScope.maybeOf(context);
    final controller = scope?.controller;
    if (controller == null) return null;

    final gatewayBaseUrl = scope?.gatewayConfig.baseUrl ?? '';
    if (_ownedBillingClient != null &&
        identical(_ownedBillingAuthController, controller) &&
        _ownedBillingGatewayBaseUrl == gatewayBaseUrl &&
        identical(_ownedBillingClientFactory, widget.billingClientFactory)) {
      return _ownedBillingClient;
    }

    _disposeOwnedBillingClient();

    final factory = widget.billingClientFactory;
    final client = factory == null
        ? CreemBillingClient(
            idTokenGetter: controller.getIdToken,
            cloudGatewayBaseUrl: gatewayBaseUrl,
          )
        : factory(
            idTokenGetter: controller.getIdToken,
            cloudGatewayBaseUrl: gatewayBaseUrl,
          );

    _ownedBillingClient = client;
    _ownedDisposableBillingClient =
        client is DisposableBillingClient ? client : null;
    _ownedBillingAuthController = controller;
    _ownedBillingGatewayBaseUrl = gatewayBaseUrl;
    _ownedBillingClientFactory = widget.billingClientFactory;
    return client;
  }

  void _disposeOwnedBillingClient() {
    _ownedDisposableBillingClient?.dispose();
    _ownedBillingClient = null;
    _ownedDisposableBillingClient = null;
    _ownedBillingAuthController = null;
    _ownedBillingGatewayBaseUrl = null;
    _ownedBillingClientFactory = null;
  }

  @override
  void didUpdateWidget(covariant CloudAccountPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
            oldWidget.billingClientFactory, widget.billingClientFactory) ||
        oldWidget.billingClient != widget.billingClient) {
      _disposeOwnedBillingClient();
    }
  }

  @override
  void dispose() {
    _verificationCooldownTimer?.cancel();
    _disposeOwnedBillingClient();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _refreshSubscription() async {
    if (_subBusy) return;
    final controller = _subscriptionController(context);
    if (controller == null) return;

    setState(() => _subBusy = true);
    try {
      await controller.refresh();
      if (!mounted) return;
      setState(() {
        _subError = controller.lastRefreshError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _subError = e);
    } finally {
      if (mounted) setState(() => _subBusy = false);
    }
  }

  void _startVerificationCooldown(
      [Duration duration = _verificationResendCooldown]) {
    _verificationCooldownTimer?.cancel();

    final totalSeconds = duration.inSeconds;
    if (!mounted || totalSeconds <= 0) return;

    setState(() => _verificationCooldownSeconds = totalSeconds);

    _verificationCooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_verificationCooldownSeconds <= 1) {
          timer.cancel();
          setState(() {
            _verificationCooldownSeconds = 0;
            _verificationCooldownTimer = null;
          });
          return;
        }

        setState(() => _verificationCooldownSeconds -= 1);
      },
    );
  }

  String _extractErrorCode(Object error) {
    String normalize(String value) {
      return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    }

    if (error is FirebaseAuthException) {
      return normalize(error.code);
    }

    final message = error.toString();
    final stringMatch = _jsonStringErrorPattern.firstMatch(message);
    if (stringMatch != null) {
      return normalize(stringMatch.group(1) ?? '');
    }

    final codeMatch = _jsonCodeErrorPattern.firstMatch(message);
    if (codeMatch != null) {
      return normalize(codeMatch.group(1) ?? '');
    }

    final tokenMatch = RegExp(r'\b([A-Z][A-Z0-9_]{2,})\b').firstMatch(message);
    if (tokenMatch != null) {
      return normalize(tokenMatch.group(1) ?? '');
    }

    return normalize(message);
  }

  bool _isEmailAlreadyVerifiedError(Object error) {
    const knownCodes = <String>{
      'email_already_verified',
      'already_verified',
      'email_verified',
    };

    final code = _extractErrorCode(error);
    if (knownCodes.contains(code)) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('already verified') ||
        message.contains('已验证') ||
        message.contains('not needed');
  }

  String _formatCloudSubscriptionError(BuildContext context, Object error) {
    final t = context.t;
    final status = parseHttpStatusFromError(error);
    final code = parseCloudErrorCodeFromError(error);
    if (status == 402 || code == 'payment_required') {
      return t.sync.cloudManagedVault.paymentRequired;
    }
    if (status == 403 && code == 'email_not_verified') {
      return t.chat.cloudGateway.emailNotVerified;
    }

    if (error is FirebaseAuthException) {
      if (error.code == 'missing_web_api_key' ||
          error.code == 'missing_wwb_api_key') {
        return t.settings.cloudAccount.errors.missingWebApiKey;
      }
    }

    final message = error.toString();
    if (message.contains('missing_web_api_key') ||
        message.contains('missing_wwb_api_key')) {
      return t.settings.cloudAccount.errors.missingWebApiKey;
    }

    return message;
  }

  Future<void> _openCheckout() async {
    if (_billingBusy) return;
    final client = _billingClient(context);
    if (client == null) return;

    setState(() {
      _billingBusy = true;
      _billingError = null;
    });

    try {
      await client.openCheckout();
      if (!mounted) return;
      setState(() => _billingError = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _billingError = e);
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _openPortal() async {
    if (_billingBusy) return;
    final client = _billingClient(context);
    if (client == null) return;

    setState(() {
      _billingBusy = true;
      _billingError = null;
    });

    try {
      await client.openPortal();
      if (!mounted) return;
      setState(() => _billingError = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _billingError = e);
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _refreshUserInfo() async {
    if (_userInfoBusy) return;
    final controller = CloudAuthScope.of(context).controller;
    if (controller.uid == null) return;

    setState(() => _userInfoBusy = true);
    try {
      await controller.refreshUserInfo();
      if (!mounted) return;
      setState(() => _userInfoError = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _userInfoError = e);
    } finally {
      if (mounted) setState(() => _userInfoBusy = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (_verificationBusy || _verificationCooldownActive) return;
    final controller = CloudAuthScope.of(context).controller;

    setState(() {
      _verificationBusy = true;
      _verificationHint = null;
    });
    try {
      await controller.sendEmailVerification();
      _startVerificationCooldown();
      await controller.refreshUserInfo();
      if (!mounted) return;
      final verified = controller.emailVerified == true;
      final message = verified
          ? context.t.settings.cloudAccount.emailVerification.messages
              .verificationAlreadyDone
          : context.t.settings.cloudAccount.emailVerification.messages
              .verificationEmailSent;
      if (verified) {
        setState(() {
          _verificationHint = context
              .t.settings.cloudAccount.emailVerification.labels.verifiedHelp;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (_isEmailAlreadyVerifiedError(e)) {
        await controller.refreshUserInfo();
        if (!mounted) return;
        setState(() {
          _verificationHint = context
              .t.settings.cloudAccount.emailVerification.labels.verifiedHelp;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t.settings.cloudAccount.emailVerification.messages
                  .verificationAlreadyDone,
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.settings.cloudAccount.emailVerification.messages
                .verificationEmailSendFailed(
              error: _formatCloudAuthError(context, e),
            ),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _verificationBusy = false);
    }
  }

  String _formatCloudAuthError(BuildContext context, Object error) {
    final code = _extractErrorCode(error);
    if (code == 'missing_email') {
      return _passwordResetMissingEmailMessage(context);
    }
    if (code == 'password_reset_not_supported') {
      return _passwordResetNotSupportedMessage(context);
    }

    if (error is FirebaseAuthException) {
      if (error.code == 'missing_web_api_key' ||
          error.code == 'missing_wwb_api_key') {
        return context.t.settings.cloudAccount.errors.missingWebApiKey;
      }
    }
    final message = error.toString();
    if (message.contains('missing_web_api_key') ||
        message.contains('missing_wwb_api_key')) {
      return context.t.settings.cloudAccount.errors.missingWebApiKey;
    }
    return message;
  }

  String _forgotPasswordLabel(BuildContext context) {
    return context.t.settings.cloudAccount.passwordReset.forgotPassword;
  }

  String _passwordResetSentMessage(BuildContext context) {
    return context.t.settings.cloudAccount.passwordReset.sent;
  }

  String _passwordResetMissingEmailMessage(BuildContext context) {
    return context.t.settings.cloudAccount.passwordReset.missingEmail;
  }

  String _passwordResetNotSupportedMessage(BuildContext context) {
    return context.t.settings.cloudAccount.passwordReset.notSupported;
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final controller = CloudAuthScope.of(context).controller;
      await controller.signInWithEmailPassword(
          email: email, password: password);
      if (!mounted) return;
      setState(() {
        _passwordController.clear();
      });
      unawaited(_refreshUserInfo());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatCloudAuthError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_passwordResetMissingEmailMessage(context)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final controller = CloudAuthScope.of(context).controller;
      await sendCloudPasswordResetEmail(controller: controller, email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_passwordResetSentMessage(context)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatCloudAuthError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final controller = CloudAuthScope.of(context).controller;
      await controller.signUpWithEmailPassword(
          email: email, password: password);
      await controller.refreshUserInfo();
      await controller.sendEmailVerification();
      _startVerificationCooldown();
      if (!mounted) return;
      setState(() {
        _passwordController.clear();
        _verificationHint = context.t.settings.cloudAccount.emailVerification
            .messages.signUpVerificationPrompt;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.settings.cloudAccount.emailVerification.messages
                .signUpVerificationPrompt,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      unawaited(_refreshUserInfo());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatCloudAuthError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = CloudAuthScope.of(context).controller;
      await controller.signOut();
      if (!mounted) return;
      _verificationCooldownTimer?.cancel();
      setState(() {
        _verificationHint = null;
        _verificationCooldownSeconds = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _completeOnboardingIfEntitled({
    required String? uid,
    required SubscriptionStatus subscriptionStatus,
  }) {
    if (widget.entryMode != CloudAccountEntryMode.onboarding ||
        uid == null ||
        subscriptionStatus != SubscriptionStatus.entitled) {
      _onboardingCompletionScheduled = false;
      return;
    }
    if (_onboardingCompletionScheduled) return;
    _onboardingCompletionScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onEntitled?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final scope = CloudAuthScope.maybeOf(context);
    final controller = scope?.controller;
    final uid = controller?.uid;
    final email = controller?.email;
    final displayEmail =
        AgentUiAcceptanceScope.maybeOf(context)?.redactedCloudAccountEmail ??
            email;

    if (uid != _subscriptionUid) {
      _subscriptionUid = uid;
      _subError = null;
      if (uid != null) {
        unawaited(_refreshSubscription());
      }
    }

    if (uid != _userInfoUid) {
      _userInfoUid = uid;
      _userInfoError = null;
      _verificationHint = null;
      _verificationCooldownTimer?.cancel();
      _verificationCooldownTimer = null;
      _verificationCooldownSeconds = 0;
      if (uid != null) {
        unawaited(_refreshUserInfo());
      }
    }

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final isOnboarding = widget.entryMode == CloudAccountEntryMode.onboarding;
    _completeOnboardingIfEntitled(
      uid: uid,
      subscriptionStatus: subscriptionStatus,
    );
    final canManageSubscription =
        _subscriptionDetailsController(context)?.canManageSubscription ?? true;
    final resendLabel = _verificationCooldownActive
        ? t.settings.cloudAccount.emailVerification.actions
            .resendCooldown(seconds: _verificationCooldownSeconds)
        : t.settings.cloudAccount.emailVerification.actions.resend;
    final subscriptionStatusValue = switch (subscriptionStatus) {
      SubscriptionStatus.entitled => t.settings.subscription.status.entitled,
      SubscriptionStatus.notEntitled =>
        t.settings.subscription.status.notEntitled,
      SubscriptionStatus.unknown => t.settings.subscription.status.unknown,
    };
    final emailVerificationStatusValue = controller?.emailVerified == true
        ? t.settings.cloudAccount.emailVerification.status.verified
        : controller?.emailVerified == false
            ? t.settings.cloudAccount.emailVerification.status.notVerified
            : t.settings.cloudAccount.emailVerification.status.unknown;
    final purchaseBenefit = CloudAccountBenefit(
      icon: Icons.shopping_cart_rounded,
      title: t.settings.cloudAccount.benefits.items.purchase.title,
      body: t.settings.cloudAccount.benefits.items.purchase.body,
    );
    final subscriptionBenefits = [
      CloudAccountBenefit(
        icon: Icons.flash_on_rounded,
        title: t.settings.subscription.benefits.items.noSetup.title,
        body: t.settings.subscription.benefits.items.noSetup.body,
      ),
      CloudAccountBenefit(
        icon: Icons.cloud_sync_rounded,
        title: t.settings.subscription.benefits.items.cloudSync.title,
        body: t.settings.subscription.benefits.items.cloudSync.body,
      ),
      CloudAccountBenefit(
        icon: Icons.manage_search_rounded,
        title: t.settings.subscription.benefits.items.mobileSearch.title,
        body: t.settings.subscription.benefits.items.mobileSearch.body,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (uid == null) ...[
          if (!isOnboarding) ...[
            CloudAccountBenefitsSection(
              surfaceKey: const ValueKey('cloud_account_value_props'),
              title: t.settings.cloudAccount.benefits.title,
              benefits: [purchaseBenefit],
            ),
            const SizedBox(height: 16),
            CloudAccountBenefitsSection(
              title: t.settings.subscription.benefits.title,
              benefits: subscriptionBenefits,
            ),
            const SizedBox(height: 16),
          ],
          CloudAccountAuthSection(
            emailController: _emailController,
            passwordController: _passwordController,
            busy: _busy,
            emailLabel: t.settings.cloudAccount.fields.email,
            passwordLabel: t.settings.cloudAccount.fields.password,
            signInLabel: t.settings.cloudAccount.actions.signIn,
            signUpLabel: t.settings.cloudAccount.actions.signUp,
            forgotPasswordLabel: _forgotPasswordLabel(context),
            onSignIn: _signIn,
            onSignUp: _signUp,
            onForgotPassword: _forgotPassword,
          ),
        ] else ...[
          CloudAccountIdentitySection(
            signedInLabel:
                t.settings.cloudAccount.signedInAs(email: displayEmail ?? '—'),
            signOutLabel: t.settings.cloudAccount.actions.signOut,
            busy: _busy,
            onSignOut: _signOut,
          ),
          if (!isOnboarding || controller?.emailVerified != true) ...[
            const SizedBox(height: 16),
            CloudAccountEmailVerificationSection(
              title: t.settings.cloudAccount.emailVerification.title,
              statusLabel:
                  t.settings.cloudAccount.emailVerification.labels.status,
              statusValue: emailVerificationStatusValue,
              helpText: t.settings.cloudAccount.emailVerification.labels.help,
              resendLabel: resendLabel,
              refreshTooltip: t.common.actions.refresh,
              userInfoBusy: _userInfoBusy,
              verificationBusy: _verificationBusy,
              verificationCooldownActive: _verificationCooldownActive,
              emailVerified: controller?.emailVerified,
              onRefresh: _refreshUserInfo,
              onResend: _resendVerificationEmail,
              loadFailedText: _userInfoError == null
                  ? null
                  : t.settings.cloudAccount.emailVerification.labels
                      .loadFailed(error: '$_userInfoError'),
              verificationHint: _verificationHint,
            ),
          ],
          const SizedBox(height: 16),
          CloudAccountSubscriptionSection(
            status: subscriptionStatus,
            canManageSubscription: canManageSubscription,
            subBusy: _subBusy,
            billingBusy: _billingBusy,
            statusLabel: t.settings.subscription.labels.status,
            statusValue: subscriptionStatusValue,
            title: t.settings.subscription.title,
            refreshTooltip: t.common.actions.refresh,
            purchaseLabel: t.settings.subscription.actions.purchase,
            manageLabel: t.settings.subscription.subtitle,
            benefitsTitle: t.settings.subscription.benefits.title,
            benefits: subscriptionBenefits,
            onboarding: isOnboarding,
            subscriptionRequiredBody:
                t.settings.cloudAccount.onboarding.subscriptionRequiredBody,
            onRefresh: _refreshSubscription,
            onSubscribe: _openCheckout,
            onManage: _openPortal,
            subscriptionErrorText: _subError == null
                ? null
                : t.settings.subscription.labels.loadFailed(
                    error: _formatCloudSubscriptionError(context, _subError!),
                  ),
            billingErrorText: _billingError == null
                ? null
                : t.settings.subscription.labels.loadFailed(
                    error:
                        _formatCloudSubscriptionError(context, _billingError!),
                  ),
          ),
          if (!isOnboarding) ...[
            const SizedBox(height: 16),
            CloudUsageCard(client: widget.cloudUsageClient),
            const SizedBox(height: 16),
            VaultUsageCard(
              client: widget.vaultUsageClient,
              attachmentsClient: widget.vaultAttachmentsClient,
              configStore: widget.vaultConfigStore,
              isWebOverride: widget.isWebOverride,
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          SettingsInlineMessage(
            message: _error!,
            tone: SettingsInlineMessageTone.error,
          ),
        ],
      ],
    );
  }
}
