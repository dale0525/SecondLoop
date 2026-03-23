import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../backend/app_backend.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';

final class InheritedScopeCapture {
  const InheritedScopeCapture({
    this.backend,
    this.sessionKey,
    this.lock,
    this.subscriptionController,
    this.cloudAuthController,
    this.cloudGatewayConfig,
    this.syncEngine,
  });

  final AppBackend? backend;
  final Uint8List? sessionKey;
  final VoidCallback? lock;
  final SubscriptionStatusController? subscriptionController;
  final CloudAuthController? cloudAuthController;
  final CloudGatewayConfig? cloudGatewayConfig;
  final SyncEngine? syncEngine;

  bool get isEmpty =>
      backend == null &&
      sessionKey == null &&
      lock == null &&
      subscriptionController == null &&
      cloudAuthController == null &&
      cloudGatewayConfig == null &&
      syncEngine == null;
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
    subscriptionController: SubscriptionScope.maybeOf(context),
    cloudAuthController: cloudAuthScope?.controller,
    cloudGatewayConfig: cloudAuthScope?.gatewayConfig,
    syncEngine: SyncEngineScope.maybeOf(context),
  );
}

InheritedScopeCapture? maybeCaptureInheritedScopes(BuildContext? context) {
  if (context == null || !context.mounted) {
    return null;
  }
  final captured = captureInheritedScopes(context);
  return captured.isEmpty ? null : captured;
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
