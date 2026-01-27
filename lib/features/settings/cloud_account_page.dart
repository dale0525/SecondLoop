import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/cloud/firebase_identity_toolkit.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/subscription/cloud_subscription_controller.dart';
import '../../core/subscription/creem_billing_client.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'cloud_usage_card.dart';

class CloudAccountPage extends StatefulWidget {
  const CloudAccountPage({super.key, this.billingClient});

  final BillingClient? billingClient;

  @override
  State<CloudAccountPage> createState() => _CloudAccountPageState();
}

class _CloudAccountPageState extends State<CloudAccountPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;

  bool _userInfoBusy = false;
  Object? _userInfoError;
  String? _userInfoUid;

  bool _verificationBusy = false;

  bool _subBusy = false;
  Object? _subError;
  String? _subscriptionUid;

  bool _billingBusy = false;
  Object? _billingError;

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

    return CreemBillingClient(
      idTokenGetter: controller.getIdToken,
      cloudGatewayBaseUrl: scope?.gatewayConfig.baseUrl ?? '',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _subscriptionStatusLine(
      BuildContext context, SubscriptionStatus status) {
    final t = context.t;
    final label = switch (status) {
      SubscriptionStatus.entitled => t.settings.subscription.status.entitled,
      SubscriptionStatus.notEntitled =>
        t.settings.subscription.status.notEntitled,
      SubscriptionStatus.unknown => t.settings.subscription.status.unknown,
    };
    return Row(
      children: [
        Text(t.settings.subscription.labels.status),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _valuePropTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: scheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(body),
    );
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
        _subError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _subError = e);
    } finally {
      if (mounted) setState(() => _subBusy = false);
    }
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
    if (_verificationBusy) return;
    final controller = CloudAuthScope.of(context).controller;

    setState(() => _verificationBusy = true);
    try {
      await controller.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.settings.cloudAccount.emailVerification.messages
                .verificationEmailSent,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.settings.cloudAccount.emailVerification.messages
                .verificationEmailSendFailed(error: '$e'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _verificationBusy = false);
    }
  }

  String _formatCloudAuthError(BuildContext context, Object error) {
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
      if (!mounted) return;
      setState(() {
        _passwordController.clear();
      });
      unawaited(_refreshUserInfo());
      unawaited(_resendVerificationEmail());
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = CloudAuthScope.maybeOf(context);
    final controller = scope?.controller;
    final uid = controller?.uid;
    final email = controller?.email;

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
      if (uid != null) {
        unawaited(_refreshUserInfo());
      }
    }

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final canManageSubscription =
        _subscriptionDetailsController(context)?.canManageSubscription ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.settings.cloudAccount.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (uid == null) ...[
            SlSurface(
              key: const ValueKey('cloud_account_value_props'),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.settings.cloudAccount.benefits.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  _valuePropTile(
                    context,
                    icon: Icons.shopping_cart,
                    title: context
                        .t.settings.cloudAccount.benefits.items.purchase.title,
                    body: context
                        .t.settings.cloudAccount.benefits.items.purchase.body,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.t.settings.subscription.benefits.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  _valuePropTile(
                    context,
                    icon: Icons.flash_on,
                    title: context
                        .t.settings.subscription.benefits.items.noSetup.title,
                    body: context
                        .t.settings.subscription.benefits.items.noSetup.body,
                  ),
                  _valuePropTile(
                    context,
                    icon: Icons.cloud_sync,
                    title: context
                        .t.settings.subscription.benefits.items.cloudSync.title,
                    body: context
                        .t.settings.subscription.benefits.items.cloudSync.body,
                  ),
                  _valuePropTile(
                    context,
                    icon: Icons.manage_search,
                    title: context.t.settings.subscription.benefits.items
                        .mobileSearch.title,
                    body: context.t.settings.subscription.benefits.items
                        .mobileSearch.body,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SlSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: context.t.settings.cloudAccount.fields.email,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText:
                          context.t.settings.cloudAccount.fields.password,
                    ),
                    obscureText: true,
                    enabled: !_busy,
                    onSubmitted: (_) => _signIn(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : _signIn,
                          child: Text(
                            context.t.settings.cloudAccount.actions.signIn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _signUp,
                          child: Text(
                            context.t.settings.cloudAccount.actions.signUp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            SlSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.settings.cloudAccount
                        .signedInAs(email: email ?? '—'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _signOut,
                    child:
                        Text(context.t.settings.cloudAccount.actions.signOut),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SlSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context
                              .t.settings.cloudAccount.emailVerification.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: _userInfoBusy ? null : _refreshUserInfo,
                        icon: const Icon(Icons.refresh),
                        tooltip: context.t.common.actions.refresh,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        context.t.settings.cloudAccount.emailVerification.labels
                            .status,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        controller?.emailVerified == true
                            ? context.t.settings.cloudAccount.emailVerification
                                .status.verified
                            : controller?.emailVerified == false
                                ? context.t.settings.cloudAccount
                                    .emailVerification.status.notVerified
                                : context.t.settings.cloudAccount
                                    .emailVerification.status.unknown,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (_userInfoError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.t.settings.cloudAccount.emailVerification.labels
                          .loadFailed(error: '$_userInfoError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (controller?.emailVerified == false) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.t.settings.cloudAccount.emailVerification.labels
                          .help,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('cloud_resend_verification'),
                      onPressed:
                          _verificationBusy ? null : _resendVerificationEmail,
                      child: Text(
                        context.t.settings.cloudAccount.emailVerification
                            .actions.resend,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SlSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.t.settings.subscription.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: _subBusy ? null : _refreshSubscription,
                        icon: const Icon(Icons.refresh),
                        tooltip: context.t.common.actions.refresh,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _subscriptionStatusLine(context, subscriptionStatus),
                  const SizedBox(height: 12),
                  if (_subError != null) ...[
                    Text(
                      context.t.settings.subscription.labels.loadFailed(
                        error: '$_subError',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_billingError != null) ...[
                    Text(
                      context.t.settings.subscription.labels.loadFailed(
                        error: '$_billingError',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (subscriptionStatus != SubscriptionStatus.entitled) ...[
                    Container(
                      key: const ValueKey('cloud_subscription_value_props'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t.settings.subscription.benefits.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          _valuePropTile(
                            context,
                            icon: Icons.flash_on,
                            title: context.t.settings.subscription.benefits
                                .items.noSetup.title,
                            body: context.t.settings.subscription.benefits.items
                                .noSetup.body,
                          ),
                          _valuePropTile(
                            context,
                            icon: Icons.cloud_sync,
                            title: context.t.settings.subscription.benefits
                                .items.cloudSync.title,
                            body: context.t.settings.subscription.benefits.items
                                .cloudSync.body,
                          ),
                          _valuePropTile(
                            context,
                            icon: Icons.manage_search,
                            title: context.t.settings.subscription.benefits
                                .items.mobileSearch.title,
                            body: context.t.settings.subscription.benefits.items
                                .mobileSearch.body,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('cloud_subscribe'),
                      onPressed: _billingBusy ? null : _openCheckout,
                      child: Text(
                        context.t.settings.subscription.actions.purchase,
                      ),
                    ),
                  ] else ...[
                    if (canManageSubscription)
                      OutlinedButton(
                        key: const ValueKey('cloud_manage_subscription'),
                        onPressed: _billingBusy ? null : _openPortal,
                        child: Text(context.t.settings.subscription.subtitle),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const CloudUsageCard(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
