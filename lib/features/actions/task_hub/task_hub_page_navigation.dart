part of 'task_hub_page.dart';

extension _TaskHubPageStateNavigation on _TaskHubPageState {
  Widget _wrapPushedPageWithScopes(BuildContext context, Widget child) {
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
}
