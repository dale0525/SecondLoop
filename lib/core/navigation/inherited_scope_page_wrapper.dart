import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../backend/app_backend.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../platform/app_platform_capabilities.dart';
import '../platform/app_platform_capability_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';
import '../sync/sync_key_manager.dart';
import '../../web_app/web_formal_settings_scope.dart';

const double _kWebFormalSettingsRouteMaxWidth = 1120;

final class InheritedScopeCapture {
  const InheritedScopeCapture({
    this.backend,
    this.sessionKey,
    this.lock,
    this.platformCapabilities,
    this.subscriptionController,
    this.cloudAuthController,
    this.cloudGatewayConfig,
    this.syncEngine,
    this.webFormalSettingsDependencies,
    this.theme,
  });

  final AppBackend? backend;
  final Uint8List? sessionKey;
  final VoidCallback? lock;
  final AppPlatformCapabilities? platformCapabilities;
  final SubscriptionStatusController? subscriptionController;
  final CloudAuthController? cloudAuthController;
  final CloudGatewayConfig? cloudGatewayConfig;
  final SyncEngine? syncEngine;
  final WebFormalSettingsDependencies? webFormalSettingsDependencies;
  final ThemeData? theme;

  bool get isEmpty =>
      backend == null &&
      sessionKey == null &&
      lock == null &&
      platformCapabilities == null &&
      subscriptionController == null &&
      cloudAuthController == null &&
      cloudGatewayConfig == null &&
      syncEngine == null &&
      webFormalSettingsDependencies == null &&
      theme == null;
}

InheritedScopeCapture captureInheritedScopes(BuildContext context) {
  final sessionScope = SessionScope.maybeOf(context);
  final cloudAuthScope = CloudAuthScope.maybeOf(context);
  return InheritedScopeCapture(
    backend: AppBackendScope.maybeOf(context),
    sessionKey: sessionScope == null
        ? null
        : Uint8List.fromList(sessionScope.sessionKey),
    lock: sessionScope?.lock,
    platformCapabilities: AppPlatformCapabilityScope.maybeOf(context),
    subscriptionController: SubscriptionScope.maybeOf(context),
    cloudAuthController: cloudAuthScope?.controller,
    cloudGatewayConfig: cloudAuthScope?.gatewayConfig,
    syncEngine: SyncEngineScope.maybeOf(context),
    webFormalSettingsDependencies:
        WebFormalSettingsScope.maybeOf(context)?.dependencies,
    theme: Theme.of(context),
  );
}

InheritedScopeCapture? maybeCaptureInheritedScopes(BuildContext? context) {
  if (context == null || !context.mounted) {
    return null;
  }
  final captured = captureInheritedScopes(context);
  return captured.isEmpty ? null : captured;
}

InheritedScopeCapture? filterCapturedScopesForActiveSession(
  InheritedScopeCapture? capturedScopes,
) {
  if (capturedScopes == null || capturedScopes.isEmpty) {
    return null;
  }
  final sessionKey = capturedScopes.sessionKey;
  if (sessionKey != null && !SyncKeyManager.matchesSessionKey(sessionKey)) {
    return null;
  }
  return capturedScopes;
}

Widget wrapPushedPageWithInheritedScopeCapture(
  InheritedScopeCapture? capturedScopes,
  Widget child,
) {
  if (capturedScopes == null || capturedScopes.isEmpty) {
    return child;
  }

  Widget wrapped = child;

  final syncEngine = capturedScopes.syncEngine;
  if (syncEngine != null) {
    wrapped = SyncEngineScope(engine: syncEngine, child: wrapped);
  }

  final cloudAuthController = capturedScopes.cloudAuthController;
  final cloudGatewayConfig = capturedScopes.cloudGatewayConfig;
  if (cloudAuthController != null && cloudGatewayConfig != null) {
    wrapped = CloudAuthScope(
      controller: cloudAuthController,
      gatewayConfig: cloudGatewayConfig,
      child: wrapped,
    );
  }

  final subscriptionController = capturedScopes.subscriptionController;
  if (subscriptionController != null) {
    wrapped = SubscriptionScope(
      controller: subscriptionController,
      child: wrapped,
    );
  }

  final webFormalSettingsDependencies =
      capturedScopes.webFormalSettingsDependencies;
  if (webFormalSettingsDependencies != null) {
    wrapped = WebFormalSettingsScope(
      dependencies: webFormalSettingsDependencies,
      child: wrapped,
    );
  }

  final sessionKey = capturedScopes.sessionKey;
  final lock = capturedScopes.lock;
  if (sessionKey != null && lock != null) {
    wrapped = SessionScope(
      sessionKey: Uint8List.fromList(sessionKey),
      lock: lock,
      child: wrapped,
    );
  }

  final backend = capturedScopes.backend;
  if (backend != null) {
    wrapped = AppBackendScope(backend: backend, child: wrapped);
  }

  final platformCapabilities = capturedScopes.platformCapabilities;
  if (platformCapabilities != null) {
    wrapped = AppPlatformCapabilityScope(
      capabilities: platformCapabilities,
      child: wrapped,
    );
    if (platformCapabilities.usesCloudSessionModel) {
      wrapped = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _kWebFormalSettingsRouteMaxWidth,
          ),
          child: wrapped,
        ),
      );
    }
  }

  final theme = capturedScopes.theme;
  if (theme != null) {
    wrapped = Theme(data: theme, child: wrapped);
  }

  return wrapped;
}

MaterialPageRoute<T> pageRouteWithInheritedScopes<T>(
  BuildContext context,
  Widget child,
) {
  return MaterialPageRoute<T>(
    builder: (_) => wrapPushedPageWithInheritedScopes(context, child),
  );
}

MaterialPageRoute<T> pageRouteWithInheritedScopeCapture<T>(
  InheritedScopeCapture? capturedScopes,
  Widget child,
) {
  return MaterialPageRoute<T>(
    builder: (_) => wrapPushedPageWithInheritedScopeCapture(
      capturedScopes,
      child,
    ),
  );
}

Future<T?> pushPageWithInheritedScopes<T>(
  NavigatorState navigator,
  BuildContext context,
  Widget child,
) {
  return navigator.push<T>(pageRouteWithInheritedScopes<T>(context, child));
}

Future<T?> pushPageWithCapturedInheritedScopes<T>(
  NavigatorState navigator,
  BuildContext? capturedContext,
  Widget child,
) {
  if (capturedContext == null || !capturedContext.mounted) {
    return Future<T?>.value(null);
  }
  return pushPageWithInheritedScopes<T>(navigator, capturedContext, child);
}

Future<T?> pushPageWithCapturedInheritedScopesOrFallback<T>(
  NavigatorState navigator,
  BuildContext? capturedContext,
  Widget child, {
  InheritedScopeCapture? capturedScopes,
}) {
  final snapshot =
      capturedScopes ?? maybeCaptureInheritedScopes(capturedContext);
  return navigator.push<T>(
    pageRouteWithInheritedScopeCapture<T>(snapshot, child),
  );
}

Future<T?> pushReplacementPageWithInheritedScopes<T, TO>(
  NavigatorState navigator,
  BuildContext context,
  Widget child,
) {
  return navigator.pushReplacement<T, TO>(
    pageRouteWithInheritedScopes<T>(context, child),
  );
}

Widget wrapPushedPageWithInheritedScopes(BuildContext context, Widget child) {
  return wrapPushedPageWithInheritedScopeCapture(
    captureInheritedScopes(context),
    child,
  );
}
