export function computeProjectDesiredHash(project: unknown): string;
export function computeProviderPublicConfigHash(provider: unknown): string;
export function computeRuntimeProjectionHash(app: unknown): string;
export function projectRuntimeProjection(project: unknown): {
  modelAccess: unknown;
  identity: unknown;
  entitlements: unknown;
};
export function validateAgentWeaveProjectData(project: unknown, label?: string): unknown;
export function validateDeploymentLockData(
  lock: unknown,
  options?: { project?: unknown; app?: unknown },
): unknown;
export function validateProjectMatchesRuntime(project: unknown, app: unknown): true;
