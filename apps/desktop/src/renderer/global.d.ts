/// <reference types="vite/client" />

import type { ApprovalObservationResult } from "../shared/approvalObservation";
import type { AttachmentMetadata } from "../shared/attachments";
import type { BillingStatus, CommerceOpenReceipt } from "../shared/commerce";
import type {
  BackupExportReceipt,
  BackupRestoreReceipt,
  DataProtectionStatus,
} from "../shared/dataProtection";
import type { AgentAppHostDiscovery } from "../shared/hostBootstrap";
import type {
  IdentityAuthorizationStart,
  IdentityPasswordRequest,
  IdentitySessionStatus,
} from "../shared/identity";
import type {
  DeveloperPackageReceipt,
  DeveloperProjectSaveRequest,
  DeveloperProjectSnapshot,
} from "../shared/developerProject";
import type { SidecarStatus } from "../shared/sidecarStatus";
import type { SidecarApiOperation } from "../shared/sidecarApi";
import type { DeveloperAccessOperation } from "../shared/developerAccess";

export {};

declare global {
  const __AGENTWEAVE_APPEARANCE__: import("./appearance/types").DesktopAppearanceBundle;
  const __AGENTWEAVE_LOCALIZATION__: import("./i18n/types").DesktopLocalizationBundle;

  interface Window {
    agentWeave?: {
      attachments?: {
        pickAndImport(): Promise<AttachmentMetadata | null>;
      };
      dataProtection?: {
        exportBackup(): Promise<BackupExportReceipt | null>;
        restoreBackup(): Promise<BackupRestoreReceipt | null>;
        status(): Promise<DataProtectionStatus>;
      };
      commerce?: {
        checkout(planId: string): Promise<CommerceOpenReceipt>;
        customerPortal(): Promise<CommerceOpenReceipt>;
        status(): Promise<BillingStatus>;
      };
      developerProject?: {
        load(): Promise<DeveloperProjectSnapshot>;
        packageApp(): Promise<DeveloperPackageReceipt>;
        save(request: DeveloperProjectSaveRequest): Promise<DeveloperProjectSnapshot>;
        showOutput(): Promise<void>;
      };
      developerAccess?: {
        request(operation: DeveloperAccessOperation, input?: unknown): Promise<unknown>;
      };
      hostBootstrap?: {
        load(): Promise<AgentAppHostDiscovery>;
      };
      identity?: {
        logout(): Promise<IdentitySessionStatus>;
        password(request: IdentityPasswordRequest): Promise<IdentitySessionStatus>;
        start(): Promise<IdentityAuthorizationStart>;
        status(): Promise<IdentitySessionStatus>;
      };
      sidecar?: {
        ensureRunning(): Promise<SidecarStatus>;
        status(): Promise<SidecarStatus>;
      };
      server?: {
        request(operation: SidecarApiOperation, input?: unknown): Promise<unknown>;
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
        startSessionTurn(sessionId: string, requestId: string, content: string): Promise<unknown>;
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
