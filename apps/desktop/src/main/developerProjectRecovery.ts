import { createHash } from "node:crypto";

import {
  validateAgentWeaveProjectData,
  validateProjectMatchesRuntime,
} from "../../../../scripts/agentweave-project.mjs";
import type { DeveloperProjectSnapshot } from "../shared/developerProject";

export function loadRecoverySnapshot(options: {
  allowRecovery: boolean;
  appRoot: string;
  manifest: Record<string, unknown>;
  project: Record<string, unknown>;
}): DeveloperProjectSnapshot | null {
  try {
    validateAgentWeaveProjectData(options.project);
    validateProjectMatchesRuntime(options.project, options.manifest);
    return null;
  } catch (error) {
    if (!options.allowRecovery) throw error;
    return {
      appRoot: options.appRoot,
      revision: hash(JSON.stringify([options.manifest, options.project])),
      desiredHash: `sha256:${hash(JSON.stringify(options.project))}`,
      manifest: options.manifest,
      project: options.project,
      deploymentStatus: "stale",
      deploymentMessage: "Repair and save the provider configuration before deploying.",
      recoveryReason: safeMessage(error),
      verifiedDeployment: null,
      verifiedBundle: null,
    };
  }
}

function hash(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function safeMessage(error: unknown): string {
  return error instanceof Error && error.message.trim()
    ? error.message
    : "Agent App provider configuration is invalid.";
}
