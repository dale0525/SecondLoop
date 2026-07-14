import { parseHostDiscovery, type AgentAppHostDiscovery } from "../src/shared/hostBootstrap";

export function hostDiscoveryFixture(
  overrides: {
    externalSideEffects?: "deny" | "require_approval" | "allow_by_policy";
    features?: string[];
    memoryPersistence?: "disabled" | "local_only" | "configured_provider";
    skillManagement?: "disabled" | "owner_only" | "runtime_policy";
  } = {},
): AgentAppHostDiscovery {
  return parseHostDiscovery({
    schemaVersion: 1,
    manifestSha256: "a".repeat(64),
    runtimeVersion: "0.1.0",
    platform: "desktop",
    identity: {
      appId: "com.example.secretary",
      packageId: "com.example.secretary.app",
      version: "0.1.0",
      displayName: "Secretary",
      shortName: "Sec",
      description: "A bounded assistant",
      accentColor: "#315C49",
    },
    features: overrides.features ?? ["action-center", "mail-workflows", "memory-management"],
    requirements: {
      packages: [
        { id: "agentweave.foundation.mail", version: "=0.1.0" },
        { id: "agentweave.foundation.memory", version: "=0.1.0" },
      ],
      capabilities: [
        "approval-engine",
        "durable-actions",
        "mail-connector",
        "memory-provider",
      ],
      runtimeTools: ["mail_accounts_list", "memory_search"],
      connectors: ["agentweave-mail"],
    },
    policy: {
      externalSideEffects: overrides.externalSideEffects ?? "require_approval",
      network: "declared_only",
      backgroundExecution: "disabled",
      memoryPersistence: overrides.memoryPersistence ?? "local_only",
      skillManagement: overrides.skillManagement ?? "runtime_policy",
    },
  });
}

export function installHostBootstrap(
  discovery: AgentAppHostDiscovery = hostDiscoveryFixture(),
): void {
  const current = window.agentWeave;
  window.agentWeave = {
    owner: current?.owner ?? unavailableOwnerApi,
    approval: current?.approval ?? {
      open: async () => {
        throw new Error("Approval is unavailable in this test");
      },
    },
    ...current,
    hostBootstrap: {
      load: async () => discovery,
    },
  };
}

const unavailableOwnerApi: NonNullable<Window["agentWeave"]>["owner"] = {
  principal: unavailableOwnerCall,
  listSkills: unavailableOwnerCall,
  skillDetail: unavailableOwnerCall,
  createDraft: unavailableOwnerCall,
  updateDraft: unavailableOwnerCall,
  validateDraft: unavailableOwnerCall,
  requestActivation: unavailableOwnerCall,
  rollback: unavailableOwnerCall,
  disable: unavailableOwnerCall,
  requestRemoval: unavailableOwnerCall,
};

async function unavailableOwnerCall(): Promise<never> {
  throw new Error("Owner API is unavailable in this test");
}
