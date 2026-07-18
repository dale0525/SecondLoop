import {
  securityProvisioningFailure,
  type DesktopSecurityProvisioner,
  type DesktopSecurityProvisioningFailure,
} from "./desktopSecurityProvisioner";
import { credentialVaultStartupPolicy } from "./desktopSecurityKeys";
import type { DesktopSidecarController } from "./sidecarController";
import type { DesktopSidecarResolution } from "./sidecarRuntime";

export async function startDesktopSidecarWithSecurity(options: {
  onCredentialVaultStartupFailure?: (
    failure: DesktopSecurityProvisioningFailure | "unknown",
  ) => void;
  resolution: DesktopSidecarResolution;
  security: Pick<DesktopSecurityProvisioner, "ensureCredentialVault">;
  sidecar: Pick<DesktopSidecarController, "start">;
}): Promise<void> {
  if (options.resolution.mode === "managed") {
    const policy = credentialVaultStartupPolicy({
      dataRoot: options.resolution.dataRoot,
      env: options.resolution.env,
    });
    if (policy.required) {
      try {
        await options.security.ensureCredentialVault({ allowCreate: policy.allowCreate });
        return;
      } catch (error) {
        options.onCredentialVaultStartupFailure?.(securityProvisioningFailure(error));
      }
    }
  }
  await options.sidecar.start();
}
