/// <reference types="vite/client" />

import type { ApprovalObservationResult } from "../shared/approvalObservation";
import type { AgentAppHostDiscovery } from "../shared/hostBootstrap";
import type { SidecarStatus } from "../shared/sidecarStatus";

export {};

declare global {
  const __AGENTWEAVE_APPEARANCE__: import("./appearance/types").DesktopAppearanceBundle;
  const __AGENTWEAVE_LOCALIZATION__: import("./i18n/types").DesktopLocalizationBundle;

  interface Window {
    agentWeave?: {
      hostBootstrap?: {
        load(): Promise<AgentAppHostDiscovery>;
      };
      sidecar?: {
        ensureRunning(): Promise<SidecarStatus>;
        status(): Promise<SidecarStatus>;
      };
      owner: {
        principal(): Promise<unknown>;
        listSkills(): Promise<unknown>;
        skillDetail(packageId: string): Promise<unknown>;
        createDraft(request: unknown): Promise<unknown>;
        updateDraft(revisionId: string, files: unknown): Promise<unknown>;
        validateDraft(revisionId: string): Promise<unknown>;
        requestActivation(revisionId: string): Promise<unknown>;
        rollback(packageId: string, revisionId: string): Promise<unknown>;
        disable(packageId: string): Promise<unknown>;
        requestRemoval(packageId: string): Promise<unknown>;
      };
      approval: {
        open(approvalId: string): Promise<ApprovalObservationResult>;
      };
      modelSettings?: {
        clearApiKey(): Promise<unknown>;
        load(): Promise<unknown>;
        postSessionMessage(sessionId: string, content: string): Promise<unknown>;
        save(settings: unknown): Promise<unknown>;
        testConnection(): Promise<unknown>;
      };
    };
    agentWeaveApproval?: {
      principal(): Promise<unknown>;
      approval(approvalId: string): Promise<unknown>;
      resolve(approvalId: string, decision: "approve" | "reject"): Promise<unknown>;
      complete(result: unknown): Promise<unknown>;
      close(approvalId: string): Promise<unknown>;
    };
  }
}
