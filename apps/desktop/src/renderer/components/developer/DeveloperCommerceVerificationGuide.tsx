import { Badge, Button, Callout } from "@radix-ui/themes";
import { Check, Clipboard, ExternalLink, FlaskConical, Webhook } from "lucide-react";
import { useMemo, useState } from "react";

import { openCreemWebhookDashboard } from "../../developerCommerceApi";
import { useI18n } from "../../i18n/I18nProvider";

const WEBHOOK_PATH = "/agentweave/commerce/v1/webhooks/creem";

export function DeveloperCommerceVerificationGuide({
  entitlementEndpoint,
  environment,
  portalVerifiedAtUnixMs,
  webhookVerifiedAtUnixMs,
}: {
  entitlementEndpoint: string | null;
  environment: "test" | "production";
  portalVerifiedAtUnixMs: number | null;
  webhookVerifiedAtUnixMs: number | null;
}): JSX.Element {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const webhookUrl = useMemo(() => trustedWebhookUrl(entitlementEndpoint), [entitlementEndpoint]);

  const copy = async () => {
    if (!webhookUrl) return;
    setError(null);
    try {
      await navigator.clipboard.writeText(webhookUrl);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2_000);
    } catch {
      setError(t("developer.release.commerceVerification.copyFailed"));
    }
  };

  const openDashboard = async () => {
    setError(null);
    try {
      await openCreemWebhookDashboard();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : t("developer.release.commerceVerification.dashboardFailed"));
    }
  };

  return (
    <section className="release-commerce-verification" aria-labelledby="release-commerce-verification-title">
      <header>
        <span><FlaskConical aria-hidden="true" size={18} /></span>
        <div>
          <h3 id="release-commerce-verification-title">{t("developer.release.commerceVerification.title")}</h3>
          <p>{t("developer.release.commerceVerification.description", { environment })}</p>
        </div>
      </header>
      <ol>
        <li>
          <div className="release-verification-step-heading">
            <span>1</span>
            <div>
              <strong>{t("developer.release.commerceVerification.registerWebhook")}</strong>
              <small>{t("developer.release.commerceVerification.registerWebhookHint")}</small>
            </div>
            <Badge color={webhookVerifiedAtUnixMs ? "green" : "orange"}>
              {webhookVerifiedAtUnixMs
                ? t("developer.release.commerceVerification.verified")
                : t("developer.release.commerceVerification.pending")}
            </Badge>
          </div>
          <div className="release-webhook-url">
            <Webhook aria-hidden="true" size={16} />
            <code>{webhookUrl ?? t("developer.release.commerceVerification.deployFirst")}</code>
            <Button disabled={!webhookUrl} onClick={() => void copy()} variant="soft">
              {copied ? <Check aria-hidden="true" size={15} /> : <Clipboard aria-hidden="true" size={15} />}
              {copied ? t("developer.release.commerceVerification.copied") : t("developer.release.commerceVerification.copy")}
            </Button>
            <Button onClick={() => void openDashboard()} variant="soft">
              <ExternalLink aria-hidden="true" size={15} />
              {t("developer.release.commerceVerification.openDashboard")}
            </Button>
          </div>
        </li>
        <li>
          <div className="release-verification-step-heading">
            <span>2</span>
            <div>
              <strong>{t("developer.release.commerceVerification.testCheckout")}</strong>
              <small>{t("developer.release.commerceVerification.testCheckoutHint")}</small>
            </div>
            <Badge color={portalVerifiedAtUnixMs ? "green" : "orange"}>
              {portalVerifiedAtUnixMs
                ? t("developer.release.commerceVerification.verified")
                : t("developer.release.commerceVerification.pending")}
            </Badge>
          </div>
          <Button asChild variant="soft">
            <a href="#settings">{t("developer.release.commerceVerification.openBilling")}</a>
          </Button>
        </li>
        <li>
          <div className="release-verification-step-heading">
            <span>3</span>
            <div>
              <strong>{t("developer.release.commerceVerification.verifyRelease")}</strong>
              <small>{t("developer.release.commerceVerification.verifyReleaseHint")}</small>
            </div>
            <Badge color={webhookVerifiedAtUnixMs && portalVerifiedAtUnixMs ? "green" : "gray"}>
              {webhookVerifiedAtUnixMs && portalVerifiedAtUnixMs
                ? t("developer.release.commerceVerification.complete")
                : t("developer.release.commerceVerification.blocked")}
            </Badge>
          </div>
        </li>
      </ol>
      {error ? <Callout.Root color="red" role="alert"><Callout.Text>{error}</Callout.Text></Callout.Root> : null}
    </section>
  );
}

function trustedWebhookUrl(endpoint: string | null): string | null {
  if (!endpoint) return null;
  try {
    const url = new URL(endpoint);
    if (url.protocol !== "https:"
      || url.username
      || url.password
      || !url.hostname.endsWith(".workers.dev")) return null;
    url.pathname = WEBHOOK_PATH;
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}
