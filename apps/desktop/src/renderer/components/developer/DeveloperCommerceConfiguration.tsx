import {
  Badge,
  Button,
  Callout,
  Checkbox,
  RadioCards,
  Select,
  Spinner,
  Text,
  TextField,
} from "@radix-ui/themes";
import { CheckCircle2, CreditCard, ExternalLink, PackageSearch, ShieldAlert, Webhook } from "lucide-react";
import { useState } from "react";

import {
  discoverCreemProducts,
  type CreemProduct,
} from "../../developerAccessApi";
import type { DeveloperProviderDescriptor } from "../../devProvidersApi";
import {
  selectionFromDescriptor,
  updateProviderConfig,
  type EntitlementPolicyPlan,
  type ManagedProjectDraft,
} from "../../developerProjectModel";
import { useI18n } from "../../i18n/I18nProvider";

export function DeveloperCommerceConfiguration({
  commerceProviders,
  draft,
  onDraft,
  onProductsConnected,
  onSecret,
  productionUnlocked,
  secretValues,
}: {
  commerceProviders: readonly DeveloperProviderDescriptor[];
  draft: ManagedProjectDraft;
  onDraft: (draft: ManagedProjectDraft) => void;
  onProductsConnected: () => Promise<void>;
  onSecret: (slot: string, value: string) => void;
  productionUnlocked: boolean;
  secretValues: Readonly<Record<string, string>>;
}): JSX.Element {
  const { t } = useI18n();
  const [products, setProducts] = useState<readonly CreemProduct[]>([]);
  const [connecting, setConnecting] = useState(false);
  const [connectionError, setConnectionError] = useState<string | null>(null);
  const managed = draft.deployment.cloudflare.entitlement;
  const commerceMode = managed.mode === "managed_worker"
    && managed.policy.sourceMode === "commerce_provider";
  const descriptor = commerceProviders.find((provider) => provider.provider_id === "agentweave.commerce.creem")
    ?? commerceProviders[0];
  const environment = draft.providers.commerce?.publicConfig.environment === "production"
    ? "production"
    : "test";

  const chooseMode = (mode: string) => {
    if (managed.mode !== "managed_worker") return;
    if (mode === "none") {
      onDraft({
        ...draft,
        providers: { ...draft.providers, commerce: null },
        deployment: {
          ...draft.deployment,
          cloudflare: {
            ...draft.deployment.cloudflare,
            entitlement: {
              ...managed,
              policy: {
                sourceMode: "uniform_bounded",
                tenantLimits: managed.policy.tenantLimits,
                uniformPlan: uniformPlan(draft),
              },
            },
          },
        },
      });
      return;
    }
    if (!descriptor) return;
    const commerce = draft.providers.commerce
      ?? selectionFromDescriptor(descriptor, { environment: "test", successUrl: "" });
    onDraft({
      ...draft,
      providers: { ...draft.providers, commerce },
      deployment: {
        ...draft.deployment,
        cloudflare: {
          ...draft.deployment.cloudflare,
          entitlement: {
            ...managed,
            policy: {
              sourceMode: "commerce_provider",
              tenantLimits: managed.policy.tenantLimits,
              productPlans: managed.policy.sourceMode === "commerce_provider"
                ? managed.policy.productPlans
                : [],
            },
          },
        },
      },
    });
  };

  const updateCommerceConfig = (field: "environment" | "successUrl", value: string) => {
    if (!draft.providers.commerce) return;
    onDraft({
      ...draft,
      providers: {
        ...draft.providers,
        commerce: updateProviderConfig(draft.providers.commerce, field, value),
      },
    });
    if (field === "environment") setProducts([]);
  };

  const connect = async () => {
    const apiKey = secretValues["commerce.apiKey"]?.trim();
    if (!apiKey) {
      setConnectionError(t("developer.release.creemApiKeyRequired"));
      return;
    }
    setConnecting(true);
    setConnectionError(null);
    try {
      const discovery = await discoverCreemProducts({ environment, apiKey });
      setProducts(discovery.products);
      onSecret("commerce.apiKey", "");
      await onProductsConnected();
    } catch (error) {
      setConnectionError(error instanceof Error ? error.message : t("developer.release.creemConnectionFailed"));
    } finally {
      setConnecting(false);
    }
  };

  return (
    <section className="release-commerce" aria-labelledby="release-commerce-title">
      <header className="release-config-section-heading">
        <span><CreditCard aria-hidden="true" size={19} /></span>
        <div>
          <h3 id="release-commerce-title">{t("developer.release.commerceTitle")}</h3>
          <p>{t("developer.release.commerceDescription")}</p>
        </div>
      </header>
      <RadioCards.Root className="release-commerce-mode" onValueChange={chooseMode} value={commerceMode ? "creem" : "none"}>
        <RadioCards.Item value="none">
          <strong>{t("developer.release.commerceNone")}</strong>
          <Text as="p" color="gray" size="2">{t("developer.release.commerceNoneHint")}</Text>
        </RadioCards.Item>
        <RadioCards.Item value="creem">
          <div className="release-preset-choice">
            <div><strong>Creem</strong><Badge color="blue" size="1">{t("developer.release.subscriptionOnly")}</Badge></div>
            <Text as="p" color="gray" size="2">{t("developer.release.creemHint")}</Text>
          </div>
        </RadioCards.Item>
      </RadioCards.Root>

      {!commerceMode ? <UniformPolicyEditor draft={draft} onDraft={onDraft} /> : null}

      {commerceMode && draft.providers.commerce ? (
        <div className="release-commerce-body">
          <div className="release-two-columns release-schema-fields">
            <label className="release-field">
              <Text size="2" weight="medium">{t("developer.release.creemEnvironment")}</Text>
              <Select.Root onValueChange={(value) => updateCommerceConfig("environment", value)} value={environment}>
                <Select.Trigger />
                <Select.Content>
                  <Select.Item value="test">Test</Select.Item>
                  <Select.Item disabled={!productionUnlocked} value="production">Production</Select.Item>
                </Select.Content>
              </Select.Root>
              {!productionUnlocked ? <Text color="gray" size="1">{t("developer.release.productionLockedHint")}</Text> : null}
            </label>
            <label className="release-field">
              <Text size="2" weight="medium">{t("developer.release.checkoutSuccessUrl")}</Text>
              <TextField.Root
                onChange={(event) => updateCommerceConfig("successUrl", event.target.value)}
                placeholder="https://example.com/billing/success"
                value={String(draft.providers.commerce.publicConfig.successUrl ?? "")}
              />
            </label>
          </div>
          <div className="release-creem-connect">
            <label className="release-field">
              <Text size="2" weight="medium">{t("developer.release.creemApiKey")}</Text>
              <TextField.Root
                autoComplete="off"
                onChange={(event) => onSecret("commerce.apiKey", event.target.value)}
                placeholder={t("developer.release.secretStoredPlaceholder")}
                type="password"
                value={secretValues["commerce.apiKey"] ?? ""}
              />
            </label>
            <Button disabled={connecting} onClick={() => void connect()}>
              {connecting ? <Spinner /> : <PackageSearch aria-hidden="true" size={16} />}
              {t("developer.release.discoverProducts")}
            </Button>
          </div>
          <label className="release-field release-webhook-secret-field">
            <Text size="2" weight="medium">{t("developer.release.creemWebhookSecret")}</Text>
            <TextField.Root
              autoComplete="off"
              onChange={(event) => onSecret("commerce.webhookSecret", event.target.value)}
              placeholder={t("developer.release.secretStoredPlaceholder")}
              type="password"
              value={secretValues["commerce.webhookSecret"] ?? ""}
            />
            <Text color="gray" size="1">
              <Webhook aria-hidden="true" size={13} /> {t("developer.release.creemWebhookSecretHint")}
            </Text>
          </label>
          {connectionError ? <Callout.Root color="red"><ShieldAlert aria-hidden="true" /><Callout.Text>{connectionError}</Callout.Text></Callout.Root> : null}
          {products.length > 0 ? (
            <ProductMappingTable draft={draft} onDraft={onDraft} products={products} />
          ) : (
            <Callout.Root color="gray" size="1">
              <PackageSearch aria-hidden="true" />
              <Callout.Text>{t("developer.release.productDiscoveryEmptyState")}</Callout.Text>
            </Callout.Root>
          )}
          <Callout.Root color="blue" size="1">
            <ExternalLink aria-hidden="true" />
            <Callout.Text>{t("developer.release.webhookManualStep")}</Callout.Text>
          </Callout.Root>
        </div>
      ) : null}
    </section>
  );
}

function UniformPolicyEditor({ draft, onDraft }: {
  draft: ManagedProjectDraft;
  onDraft: (draft: ManagedProjectDraft) => void;
}): JSX.Element {
  const { t } = useI18n();
  const managed = draft.deployment.cloudflare.entitlement;
  if (managed.mode !== "managed_worker" || managed.policy.sourceMode !== "uniform_bounded") {
    return <></>;
  }
  const policy = managed.policy;
  const updatePlan = (field: string, value: string) => {
    const plan = policy.uniformPlan;
    const next = field === "allowedModels"
      ? { ...plan, allowedModels: value.split(",").map((entry) => entry.trim()).filter(Boolean) }
      : field === "id"
        ? { ...plan, id: value }
        : { ...plan, limits: { ...plan.limits, [field]: numericLimit(value) } };
    onDraft({
      ...draft,
      deployment: {
        ...draft.deployment,
        cloudflare: {
          ...draft.deployment.cloudflare,
          entitlement: { ...managed, policy: { ...policy, uniformPlan: next } },
        },
      },
    });
  };
  const updateTenant = (field: "maxRequests" | "maxUnits", value: string) => onDraft({
    ...draft,
    deployment: {
      ...draft.deployment,
      cloudflare: {
        ...draft.deployment.cloudflare,
        entitlement: {
          ...managed,
          policy: {
            ...policy,
            tenantLimits: { ...policy.tenantLimits, [field]: numericLimit(value) },
          },
        },
      },
    },
  });
  const plan = policy.uniformPlan;
  return (
    <div className="release-uniform-policy">
      <header><strong>{t("developer.release.uniformPolicy")}</strong><small>{t("developer.release.zeroUnlimitedHint")}</small></header>
      <div className="release-product-fields">
        <label><span>{t("developer.release.planId")}</span><TextField.Root onChange={(event) => updatePlan("id", event.target.value)} value={plan.id} /></label>
        <label><span>{t("developer.release.allowedModels")}</span><TextField.Root onChange={(event) => updatePlan("allowedModels", event.target.value)} value={plan.allowedModels.join(", ")} /></label>
        {(["maxRequests", "maxUnits", "maxConcurrency"] as const).map((field) => (
          <label key={field}><span>{t(`developer.release.${field}`)}</span><TextField.Root min="0" onChange={(event) => updatePlan(field, event.target.value)} type="number" value={String(plan.limits[field])} /></label>
        ))}
        {(["maxRequests", "maxUnits"] as const).map((field) => (
          <label key={`tenant-${field}`}><span>{t(`developer.release.tenant${field === "maxRequests" ? "Requests" : "Units"}`)}</span><TextField.Root min="0" onChange={(event) => updateTenant(field, event.target.value)} type="number" value={String(policy.tenantLimits[field])} /></label>
        ))}
      </div>
      <div className="release-unlimited-note"><CheckCircle2 aria-hidden="true" size={16} />{t("developer.release.gatewayHardLimitsRemain")}</div>
    </div>
  );
}

function ProductMappingTable({ draft, onDraft, products }: {
  draft: ManagedProjectDraft;
  onDraft: (draft: ManagedProjectDraft) => void;
  products: readonly CreemProduct[];
}): JSX.Element {
  const { t } = useI18n();
  const managed = draft.deployment.cloudflare.entitlement;
  if (managed.mode !== "managed_worker" || managed.policy.sourceMode !== "commerce_provider") {
    return <></>;
  }
  const policy = managed.policy;
  const plans = policy.productPlans;
  const updatePlans = (next: EntitlementPolicyPlan[]) => onDraft({
    ...draft,
    deployment: {
      ...draft.deployment,
      cloudflare: {
        ...draft.deployment.cloudflare,
        entitlement: { ...managed, policy: { ...policy, productPlans: next } },
      },
    },
  });
  const toggle = (product: CreemProduct, enabled: boolean) => {
    const existing = plans.find((plan) => plan.productId === product.id);
    if (!enabled) {
      updatePlans(plans.map((plan) => plan.productId === product.id ? { ...plan, enabled: false } : plan));
      return;
    }
    const next = existing
      ? plans.map((plan) => plan.productId === product.id ? { ...plan, enabled: true } : plan)
      : [...plans, productPlan(product, draft.modelAccess.profile.modelName)];
    updatePlans(next);
  };
  const change = (productId: string, field: string, value: string) => updatePlans(plans.map((plan) => {
    if (plan.productId !== productId) return plan;
    if (field === "id") return { ...plan, id: value };
    if (field === "allowedModels") return { ...plan, allowedModels: value.split(",").map((entry) => entry.trim()).filter(Boolean) };
    return { ...plan, limits: { ...plan.limits, [field]: numericLimit(value) } };
  }));
  return (
    <div className="release-product-mappings">
      <header><strong>{t("developer.release.productMappings")}</strong><small>{t("developer.release.zeroUnlimitedHint")}</small></header>
      {products.map((product) => {
        const plan = plans.find((candidate) => candidate.productId === product.id);
        const subscription = product.billingType === "recurring" || product.billingType === "subscription";
        const selectable = product.active && subscription;
        return (
          <article className={!selectable ? "is-disabled" : ""} key={product.id}>
            <div className="release-product-heading">
              <Checkbox
                checked={plan?.enabled === true}
                disabled={!selectable}
                onCheckedChange={(checked) => toggle(product, checked === true)}
              />
              <div><strong>{product.name}</strong><code>{product.id}</code></div>
              <Badge color={selectable ? "green" : "gray"}>{selectable ? product.billingPeriod : t("developer.release.unsupportedProduct")}</Badge>
            </div>
            {plan?.enabled ? (
              <div className="release-product-fields">
                <label><span>{t("developer.release.planId")}</span><TextField.Root onChange={(event) => change(product.id, "id", event.target.value)} value={plan.id} /></label>
                <label><span>{t("developer.release.allowedModels")}</span><TextField.Root onChange={(event) => change(product.id, "allowedModels", event.target.value)} value={plan.allowedModels.join(", ")} /></label>
                {(["maxRequests", "maxUnits", "maxConcurrency"] as const).map((field) => (
                  <label key={field}><span>{t(`developer.release.${field}`)}</span><TextField.Root min="0" onChange={(event) => change(product.id, field, event.target.value)} type="number" value={String(plan.limits[field])} /></label>
                ))}
              </div>
            ) : null}
          </article>
        );
      })}
      <div className="release-unlimited-note"><CheckCircle2 aria-hidden="true" size={16} />{t("developer.release.gatewayHardLimitsRemain")}</div>
    </div>
  );
}

function numericLimit(value: string): number {
  const numeric = Number(value);
  return Number.isSafeInteger(numeric) && numeric >= 0 ? numeric : -1;
}

function uniformPlan(draft: ManagedProjectDraft): EntitlementPolicyPlan {
  return {
    id: "default",
    displayName: "Default plan",
    allowedModels: draft.modelAccess.profile.modelName ? [draft.modelAccess.profile.modelName] : [],
    limits: { maxRequests: 0, maxUnits: 0, maxConcurrency: 0 },
  };
}

function productPlan(product: CreemProduct, model: string): EntitlementPolicyPlan {
  return {
    id: product.id.replace(/^prod_/, "").toLowerCase().replaceAll(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "plan",
    displayName: product.name,
    enabled: true,
    productId: product.id,
    allowedModels: model ? [model] : [],
    limits: { maxRequests: 0, maxUnits: 0, maxConcurrency: 0 },
  };
}
