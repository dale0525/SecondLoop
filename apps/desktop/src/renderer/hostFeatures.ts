import type { AgentAppHostDiscovery } from "../shared/hostBootstrap";

export type DesktopHostFeatures = Readonly<{
  actions: boolean;
  accounts: boolean;
  memory: boolean;
  skillManagement: boolean;
}>;

export const CLOSED_DESKTOP_HOST_FEATURES: DesktopHostFeatures = Object.freeze({
  actions: false,
  accounts: false,
  memory: false,
  skillManagement: false,
});

export function resolveDesktopHostFeatures(
  discovery: AgentAppHostDiscovery | null,
): DesktopHostFeatures {
  if (!discovery || discovery.platform !== "desktop") {
    return CLOSED_DESKTOP_HOST_FEATURES;
  }
  const features = new Set(discovery.features);
  const capabilities = new Set(discovery.requirements.capabilities);
  const hasMail = features.has("mail-workflows")
    && capabilities.has("mail-connector")
    && discovery.requirements.connectors.length > 0;
  return Object.freeze({
    accounts: hasMail,
    actions: features.has("action-center")
      && capabilities.has("durable-actions")
      && capabilities.has("approval-engine")
      && discovery.policy.externalSideEffects !== "deny",
    memory: features.has("memory-management")
      && capabilities.has("memory-provider")
      && discovery.policy.memoryPersistence !== "disabled",
    skillManagement: discovery.policy.skillManagement !== "disabled",
  });
}
