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
  const attemptedKey = useRef<string | null>(null);
  const running = useRef(false);
  const entitlement = draft.deployment.cloudflare.entitlement;
  const selected = authorizationReady
    && draft.deployment.provider === "cloudflare"
    && draft.providers.gateway.id === "cloudflare-workers"
    && entitlement.mode === "managed_worker"
    && entitlement.policy.sourceMode === "commerce_provider"
    && draft.providers.commerce?.id === "agentweave.commerce.creem"
    && Boolean(draft.deployment.cloudflare.accountId);
  const verifiedBundle = snapshot.verifiedBundle;
  const verifiedMatchesSelection = selected
    && verifiedBundle?.commerce?.providerId === draft.providers.commerce?.id
    && verifiedBundle?.commerce?.providerVersion === draft.providers.commerce?.version
    && verifiedBundle?.commerce?.environment
      === (draft.providers.commerce?.publicConfig.environment === "production" ? "production" : "test")
    && verifiedBundle?.entitlementPolicy.target.accountId === draft.deployment.cloudflare.accountId
    && verifiedBundle?.entitlementPolicy.target.workerName
      === (entitlement.mode === "managed_worker" ? entitlement.workerName : "");
  const requestKey = selected && !verifiedMatchesSelection ? [
    draft.deployment.cloudflare.accountId,
    draft.deployment.cloudflare.environment,
    draft.deployment.cloudflare.gatewayWorkerName,
    entitlement.mode === "managed_worker" ? entitlement.workerName : "",
    draft.providers.commerce?.publicConfig.environment === "production" ? "production" : "test",
  ].join(":") : null;

  const execute = useCallback(async (force = false) => {
    if (!requestKey || running.current || (!force && attemptedKey.current === requestKey)) return;
    running.current = true;
    attemptedKey.current = requestKey;
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
    void execute();
  }, [draft.providers.gateway, execute, selected, verifiedBundle, verifiedMatchesSelection]);

  return Object.freeze({
    error,
    receipt,
    retry: () => void execute(true),
    status,
  });
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
