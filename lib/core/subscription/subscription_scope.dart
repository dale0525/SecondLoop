import 'package:flutter/widgets.dart';

import '../ai/ai_routing.dart';

abstract interface class SubscriptionStatusController extends Listenable {
  SubscriptionStatus get status;
}

abstract interface class SubscriptionDetailsController
    extends SubscriptionStatusController {
  bool? get canManageSubscription;
}

final class SubscriptionScope
    extends InheritedNotifier<SubscriptionStatusController> {
  const SubscriptionScope({
    required SubscriptionStatusController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  SubscriptionStatusController get controller => notifier!;

  static SubscriptionStatusController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SubscriptionScope>()
        ?.notifier;
  }

  static SubscriptionStatusController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No SubscriptionScope found in widget tree');
    return controller!;
  }
}
