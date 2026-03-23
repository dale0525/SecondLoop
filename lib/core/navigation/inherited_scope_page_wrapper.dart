import 'package:flutter/material.dart';

import '../backend/app_backend.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine_gate.dart';

MaterialPageRoute<T> pageRouteWithInheritedScopes<T>(
  BuildContext context,
  Widget child,
) {
  return MaterialPageRoute<T>(
    builder: (_) => wrapPushedPageWithInheritedScopes(context, child),
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
  Widget wrapped = child;

  final syncEngine = SyncEngineScope.maybeOf(context);
  if (syncEngine != null) {
    wrapped = SyncEngineScope(engine: syncEngine, child: wrapped);
  }

  final cloudAuthScope = CloudAuthScope.maybeOf(context);
  if (cloudAuthScope != null) {
    wrapped = CloudAuthScope(
      controller: cloudAuthScope.controller,
      gatewayConfig: cloudAuthScope.gatewayConfig,
      child: wrapped,
    );
  }

  final subscriptionController = SubscriptionScope.maybeOf(context);
  if (subscriptionController != null) {
    wrapped = SubscriptionScope(
      controller: subscriptionController,
      child: wrapped,
    );
  }

  final sessionScope = SessionScope.maybeOf(context);
  if (sessionScope != null) {
    wrapped = SessionScope(
      sessionKey: sessionScope.sessionKey,
      lock: sessionScope.lock,
      child: wrapped,
    );
  }

  final backend = AppBackendScope.maybeOf(context);
  if (backend != null) {
    wrapped = AppBackendScope(backend: backend, child: wrapped);
  }

  return wrapped;
}
