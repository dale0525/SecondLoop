import { useCallback, useEffect, useRef, useState } from "react";

import type { DeveloperCreemWebhookBootstrapReceipt } from "../../../shared/developerAccess";
import type { DeveloperProjectSnapshot } from "../../../shared/developerProject";
import { saveDeveloperProject } from "../../developerAccessApi";
import { bootstrapCreemWebhook } from "../../developerCommerceApi";
import type { ManagedProjectDraft } from "../../developerProjectModel";

export type CreemWebhookBootstrapStatus = "idle" | "deploying" | "ready" | "error";
export type CreemWebhookEndpoint = Pick<DeveloperCreemWebhookBootstrapReceipt, "webhookUrl">;

export function useCreemWebhookBootstrap({
  authorizationReady,
  draft,
  onProjectSaved,
  snapshot,
}: {
  authorizationReady: boolean;
  draft: ManagedProjectDraft;
  onProjectSaved: (snapshot: DeveloperProjectSnapshot) => void;
  snapshot: DeveloperProjectSnapshot;
}) {
  const [status, setStatus] = useState<CreemWebhookBootstrapStatus>("idle");
  const [receipt, setReceipt] = useState<CreemWebhookEndpoint | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [rerunVersion, setRerunVersion] = useState(0);
  const attemptedKey = useRef<string | null>(null);
  const queuedKey = useRef<string | null>(null);
  const running = useRef(false);
  const entitlement = draft.deployment.cloudflare.entitlement;
  const selected = authorizationReady
    && draft.deployment.provider === "cloudflare"
    && draft.providers.gateway.id === "cloudflare-workers"
    && entitlement.mode === "managed_worker"
    && entitlement.policy.sourceMode === "commerce_provider"
    && draft.providers.commerce?.id === "agentweave.commerce.creem"
    && Boolean(draft.deployment.cloudflare.accountId);
  const modelReady = validManagedModelName(draft.modelAccess.profile.modelName);
  const configurationReady = bootstrapConfigurationReady(draft);
  const configurationFingerprint = creemBootstrapFingerprint(draft);
  const savedConfigurationFingerprint = creemBootstrapFingerprint(snapshot.project);
  const verifiedBundle = snapshot.verifiedBundle;
  const verifiedMatchesSelection = selected
    && configurationFingerprint !== null
    && configurationFingerprint === savedConfigurationFingerprint
    && verifiedBundle?.commerce?.providerId === draft.providers.commerce?.id
    && verifiedBundle?.commerce?.providerVersion === draft.providers.commerce?.version
    && verifiedBundle?.commerce?.environment
      === (draft.providers.commerce?.publicConfig.environment === "production" ? "production" : "test")
    && verifiedBundle?.entitlementPolicy.target.accountId === draft.deployment.cloudflare.accountId
    && verifiedBundle?.entitlementPolicy.target.workerName
      === (entitlement.mode === "managed_worker" ? entitlement.workerName : "");
  const requestKey = selected && modelReady && configurationReady && !verifiedMatchesSelection
    ? configurationFingerprint
    : null;

  const execute = useCallback(async (force = false) => {
    if (!requestKey) return;
    if (running.current) {
      if (attemptedKey.current !== requestKey) queuedKey.current = requestKey;
      return;
    }
    if (!force && attemptedKey.current === requestKey) return;
    running.current = true;
    attemptedKey.current = requestKey;
    queuedKey.current = null;
    setStatus("deploying");
    setError(null);
    try {
      const saved = await saveDeveloperProject(snapshot, draft);
      onProjectSaved(saved);
      const result = await bootstrapCreemWebhook(saved);
      setReceipt(result);
      setStatus("ready");
    } catch (cause) {
      setStatus("error");
      setError(cause instanceof Error && cause.message.trim()
        ? cause.message
        : "Creem webhook Worker could not be prepared");
    } finally {
      running.current = false;
      if (queuedKey.current !== null && queuedKey.current !== requestKey) {
        queuedKey.current = null;
        setRerunVersion((current) => current + 1);
      }
    }
  }, [draft, onProjectSaved, requestKey, snapshot]);

  useEffect(() => {
    if (!selected) {
      attemptedKey.current = null;
      setReceipt(null);
      setStatus("idle");
      setError(null);
      return;
    }
    if (verifiedMatchesSelection && verifiedBundle) {
      attemptedKey.current = null;
      setReceipt(receiptFromVerifiedBundle(verifiedBundle));
      setStatus("ready");
      setError(null);
      return;
    }
    if (!modelReady || !configurationReady) {
      attemptedKey.current = null;
      setReceipt(null);
      setStatus("idle");
      setError(null);
      return;
    }
    const timeout = window.setTimeout(() => void execute(), 250);
    return () => window.clearTimeout(timeout);
  }, [
    configurationReady,
    draft.providers.gateway,
    execute,
    modelReady,
    rerunVersion,
    selected,
    verifiedBundle,
    verifiedMatchesSelection,
  ]);

  return Object.freeze({
    error,
    receipt,
    retry: () => void execute(true),
    status,
  });
}

function validManagedModelName(value: string): boolean {
  return value.length > 0
    && value === value.trim()
    && !/[\u0000-\u001f\u007f]/.test(value)
    && new TextEncoder().encode(value).byteLength <= 256;
}

function bootstrapConfigurationReady(draft: ManagedProjectDraft): boolean {
  const entitlement = draft.deployment.cloudflare.entitlement;
  if (entitlement.mode !== "managed_worker" || entitlement.policy.sourceMode !== "commerce_provider") {
    return false;
  }
  const enabledPlans = entitlement.policy.productPlans.filter((plan) => plan.enabled !== false);
  if (enabledPlans.length === 0 || enabledPlans.some((plan) => !plan.id.trim()
    || !plan.productId || !/^prod_[A-Za-z0-9_]+$/.test(plan.productId)
    || !Object.values(plan.limits).every((value) => Number.isSafeInteger(value) && value >= 0)
    || plan.limits.maxConcurrency > 1000)) return false;
  if (!Object.values(entitlement.policy.tenantLimits)
    .every((value) => Number.isSafeInteger(value) && value >= 0)) return false;
  const publicConfig = draft.providers.commerce?.publicConfig;
  if (!publicConfig) return false;
  const successUrl = publicConfig.successUrl;
  const successPage = publicConfig.successPage === undefined
    ? (typeof successUrl === "string" && successUrl.length > 0 ? "custom_url" : "managed_worker")
    : publicConfig.successPage;
  if (successPage === "managed_worker") return successUrl === undefined;
  if (successPage !== "custom_url" || typeof successUrl !== "string") return false;
  try {
    const url = new URL(successUrl);
    return url.protocol === "https:" && !url.username && !url.password && !url.search && !url.hash;
  } catch {
    return false;
  }
}

function creemBootstrapFingerprint(value: unknown): string | null {
  if (!isRecord(value)) return null;
  const providers = recordField(value, "providers");
  const commerce = providers && recordField(providers, "commerce");
  const publicConfig = commerce && recordField(commerce, "publicConfig");
  const deployment = recordField(value, "deployment");
  const cloudflare = deployment && recordField(deployment, "cloudflare");
  const entitlement = cloudflare && recordField(cloudflare, "entitlement");
  const policy = entitlement && recordField(entitlement, "policy");
  const tenantLimits = policy && recordField(policy, "tenantLimits");
  const productPlans = policy?.productPlans;
  if (!providers || !commerce || !publicConfig || !cloudflare || !entitlement || !policy
    || !tenantLimits || !Array.isArray(productPlans)) return null;

  const successUrl = publicConfig.successUrl;
  const successPage = publicConfig.successPage === undefined
    ? (typeof successUrl === "string" && successUrl.length > 0 ? "custom_url" : "managed_worker")
    : publicConfig.successPage;
  const plans = productPlans.map((candidate) => {
    if (!isRecord(candidate)) return candidate;
    const limits = recordField(candidate, "limits");
    return {
      id: candidate.id,
      displayName: candidate.displayName,
      enabled: candidate.enabled !== false,
      productId: candidate.productId,
      allowedModels: Array.isArray(candidate.allowedModels) ? [...candidate.allowedModels] : candidate.allowedModels,
      limits: limits ? {
        maxRequests: limits.maxRequests,
        maxUnits: limits.maxUnits,
        maxConcurrency: limits.maxConcurrency,
      } : candidate.limits,
    };
  });
  return JSON.stringify({
    accountId: cloudflare.accountId,
    environment: cloudflare.environment,
    gatewayWorkerName: cloudflare.gatewayWorkerName,
    entitlementWorkerName: entitlement.workerName,
    commerce: {
      providerId: commerce.id,
      providerVersion: commerce.version,
      environment: publicConfig.environment === "production" ? "production" : "test",
      successPage,
      successUrl: successPage === "custom_url" ? successUrl : null,
    },
    policy: {
      sourceMode: policy.sourceMode,
      tenantLimits: {
        maxRequests: tenantLimits.maxRequests,
        maxUnits: tenantLimits.maxUnits,
      },
      productPlans: plans,
    },
  });
}

function recordField(value: Record<string, unknown>, field: string): Record<string, unknown> | null {
  const candidate = value[field];
  return isRecord(candidate) ? candidate : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function receiptFromVerifiedBundle(
  bundle: NonNullable<DeveloperProjectSnapshot["verifiedBundle"]>,
): CreemWebhookEndpoint {
  const endpoint = new URL(bundle.entitlementPolicy.endpoint);
  endpoint.pathname = "/agentweave/commerce/v1/webhooks/creem";
  endpoint.search = "";
  endpoint.hash = "";
  return Object.freeze({
    webhookUrl: endpoint.toString(),
  });
}
