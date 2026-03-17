import '../cloud/cloud_auth_scope.dart';
import 'ai_routing.dart';

bool supportsTodoFollowupWebSearch({
  required AskAiRouteKind route,
  required CloudGatewayConfig gatewayConfig,
}) {
  if (route != AskAiRouteKind.cloudGateway) return false;
  return gatewayConfig.supportsWebSearch;
}
