import { Badge, Button, Callout, Spinner } from "@radix-ui/themes";
import { CalendarClock, CreditCard, ExternalLink, PackageOpen, RefreshCw, ShieldX } from "lucide-react";
import { useCallback, useEffect, useState } from "react";

import type { BillingStatus } from "../../shared/commerce";
import { useHostBootstrap } from "../hostBootstrap";
import { useI18n } from "../i18n/I18nProvider";
import { useIdentitySession } from "../identitySession";

export function SettingsBilling(): JSX.Element | null {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const identity = useIdentitySession();
  const enabled = bootstrap.discovery?.access.entitlements.provider?.id
    === "agentweave.entitlements.cloudflare_policy";
  const [status, setStatus] = useState<BillingStatus | null>(null);
  const [loading, setLoading] = useState(false);
  const [action, setAction] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [opened, setOpened] = useState(false);

  const refresh = useCallback(async () => {
    if (!enabled || identity.state !== "signed_in" || !window.agentWeave?.commerce) return;
    setLoading(true);
    setError(null);
    try {
      setStatus(await window.agentWeave.commerce.status());
    } catch (cause) {
      setError(billingError(cause, t));
    } finally {
      setLoading(false);
    }
  }, [enabled, identity.state, t]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  if (!enabled) return null;

  const open = async (kind: "portal" | "checkout", planId?: string) => {
    if (!window.agentWeave?.commerce || action) return;
    setAction(kind === "portal" ? "portal" : planId ?? "checkout");
    setError(null);
    setOpened(false);
    try {
      if (kind === "portal") await window.agentWeave.commerce.customerPortal();
      else if (planId) await window.agentWeave.commerce.checkout(planId);
      setOpened(true);
      await refresh();
    } catch (cause) {
      setError(billingError(cause, t));
    } finally {
      setAction(null);
    }
  };

  return (
    <section className="settings-panel billing-panel" aria-labelledby="settings-billing-title">
      <div className="settings-panel-heading billing-heading">
        <div>
          <h2 id="settings-billing-title">{t("settings.billing.title")}</h2>
          <p>{t("settings.billing.description")}</p>
        </div>
        <Button color="gray" disabled={loading || action !== null} onClick={() => void refresh()} size="1" variant="ghost">
          {loading ? <Spinner /> : <RefreshCw aria-hidden="true" size={14} />}
          {t("settings.billing.refresh")}
        </Button>
      </div>

      {identity.state !== "signed_in" ? (
        <Callout.Root color="orange"><CreditCard aria-hidden="true" /><Callout.Text>{t("settings.billing.signInRequired")}</Callout.Text></Callout.Root>
      ) : loading && !status ? (
        <div className="billing-loading"><Spinner /><span>{t("settings.billing.loading")}</span></div>
      ) : null}

      {status ? (
        <>
          <article className={`billing-current${status.subscription?.revoked ? " is-revoked" : ""}`}>
            <div className="billing-current-icon">
              {status.subscription?.revoked ? <ShieldX aria-hidden="true" size={20} /> : <PackageOpen aria-hidden="true" size={20} />}
            </div>
            <div>
              <small>{t("settings.billing.currentPlan")}</small>
              <h3>{status.plan?.displayName ?? t("settings.billing.noSubscription")}</h3>
              <p>{subscriptionMessage(status, t)}</p>
            </div>
            <Badge color={status.subscription?.revoked ? "red" : status.subscription ? "green" : "gray"}>
              {status.subscription?.status ?? (status.mode === "uniform_bounded" ? t("settings.billing.included") : t("settings.billing.inactive"))}
            </Badge>
            {status.subscription?.paidThrough ? (
              <div className="billing-paid-through">
                <CalendarClock aria-hidden="true" size={16} />
                <span>{t("settings.billing.paidThrough", { date: formatDate(status.subscription.paidThrough) })}</span>
              </div>
            ) : null}
          </article>

          {status.mode === "commerce_provider" ? (
            <section className="billing-plans" aria-labelledby="settings-billing-plans-title">
              <header><h3 id="settings-billing-plans-title">{t("settings.billing.availablePlans")}</h3><p>{t("settings.billing.availablePlansHint")}</p></header>
              <div>
                {status.availablePlans.map((plan) => (
                  <article key={plan.id}>
                    <div><strong>{plan.displayName}</strong><small>{plan.allowedModels.join(", ")}</small></div>
                    <div className="billing-plan-limits">
                      <span>{formatLimit(plan.limits.maxRequests, t("settings.billing.requests"))}</span>
                      <span>{formatLimit(plan.limits.maxUnits, t("settings.billing.units"))}</span>
                      <span>{formatLimit(plan.limits.maxConcurrency, t("settings.billing.concurrency"))}</span>
                    </div>
                    <Button disabled={action !== null} onClick={() => void open("checkout", plan.id)}>
                      {action === plan.id ? <Spinner /> : <ExternalLink aria-hidden="true" size={15} />}
                      {status.plan?.id === plan.id ? t("settings.billing.changePlan") : t("settings.billing.subscribe")}
                    </Button>
                  </article>
                ))}
              </div>
            </section>
          ) : null}

          {status.mode === "commerce_provider" ? (
            <div className="billing-management">
              <div><strong>{t("settings.billing.management")}</strong><p>{status.customerBound ? t("settings.billing.managementHint") : t("settings.billing.unboundHint")}</p></div>
              <Button color="gray" disabled={!status.customerBound || action !== null} onClick={() => void open("portal")} variant="soft">
                {action === "portal" ? <Spinner /> : <CreditCard aria-hidden="true" size={16} />}
                {t("settings.billing.openPortal")}
              </Button>
            </div>
          ) : null}
        </>
      ) : null}

      {error ? <Callout.Root color="red" role="alert"><ShieldX aria-hidden="true" /><Callout.Text>{error}</Callout.Text></Callout.Root> : null}
      {opened ? <Callout.Root color="green"><ExternalLink aria-hidden="true" /><Callout.Text>{t("settings.billing.opened")}</Callout.Text></Callout.Root> : null}
    </section>
  );
}

export function subscriptionMessage(
  status: BillingStatus,
  t: (key: string, values?: Record<string, string | number>) => string,
): string {
  const subscription = status.subscription;
  if (status.mode === "uniform_bounded") return t("settings.billing.uniformPlan");
  if (!subscription) return t("settings.billing.noSubscriptionHint");
  if (subscription.revoked || ["expired", "unpaid", "refunded", "disputed"].includes(subscription.status)) {
    return t("settings.billing.revoked");
  }
  if (["scheduled_cancel", "past_due", "paused", "canceled"].includes(subscription.status)) {
    return subscription.paidThrough
      ? t("settings.billing.retainedUntil", { date: formatDate(subscription.paidThrough) })
      : t("settings.billing.inactive");
  }
  return t("settings.billing.activeHint");
}

function billingError(error: unknown, t: (key: string) => string): string {
  const code = error instanceof Error ? error.message : "";
  if (code.includes("commerce_customer_unbound")) return t("settings.billing.unboundHint");
  if (code.includes("commerce_unauthenticated")) return t("settings.billing.signInRequired");
  if (code.includes("commerce_browser_open_failed")) return t("settings.billing.openFailed");
  return t("settings.billing.unavailable");
}

function formatDate(seconds: number): string {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(seconds * 1000));
}

function formatLimit(value: number, label: string): string {
  return `${label}: ${value === 0 ? "∞" : value.toLocaleString()}`;
}
