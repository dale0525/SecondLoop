import { Badge, Button, Callout, Spinner } from "@radix-ui/themes";
import { Check, Clipboard, CloudCog, ExternalLink, RotateCcw, Webhook } from "lucide-react";
import { useState } from "react";

import { openCreemWebhookDashboard } from "../../developerCommerceApi";
import { useI18n } from "../../i18n/I18nProvider";
import type {
  CreemWebhookBootstrapStatus,
  CreemWebhookEndpoint,
} from "./useCreemWebhookBootstrap";

export function DeveloperCommerceWebhookSetup({
  error,
  onRetry,
  receipt,
  status,
}: {
  error: string | null;
  onRetry: () => void;
  receipt: CreemWebhookEndpoint | null;
  status: CreemWebhookBootstrapStatus;
}): JSX.Element {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const copy = async () => {
    if (!receipt) return;
    setActionError(null);
    try {
      await navigator.clipboard.writeText(receipt.webhookUrl);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2_000);
    } catch {
      setActionError(t("developer.release.commerceVerification.copyFailed"));
    }
  };
  const openDashboard = async () => {
    setActionError(null);
    try {
      await openCreemWebhookDashboard();
    } catch (cause) {
      setActionError(cause instanceof Error
        ? cause.message
        : t("developer.release.commerceVerification.dashboardFailed"));
    }
  };

  return (
    <section className="release-commerce-bootstrap" aria-labelledby="release-commerce-bootstrap-title">
      <header>
        <span><CloudCog aria-hidden="true" size={18} /></span>
        <div>
          <h4 id="release-commerce-bootstrap-title">{t("developer.release.creemBootstrapTitle")}</h4>
          <p>{t("developer.release.creemBootstrapDescription")}</p>
        </div>
        <BootstrapBadge status={status} />
      </header>
      {status === "deploying" ? (
        <div className="release-commerce-bootstrap-progress" role="status">
          <Spinner />
          <div>
            <strong>{t("developer.release.creemBootstrapDeploying")}</strong>
            <small>{t("developer.release.creemBootstrapDeployingHint")}</small>
          </div>
        </div>
      ) : null}
      {status === "error" ? (
        <Callout.Root color="red" role="alert">
          <Callout.Text>{error ?? t("developer.release.creemBootstrapFailed")}</Callout.Text>
          <Button onClick={onRetry} variant="soft">
            <RotateCcw aria-hidden="true" size={15} />
            {t("developer.release.creemBootstrapRetry")}
          </Button>
        </Callout.Root>
      ) : null}
      {receipt ? (
        <div className="release-commerce-bootstrap-ready">
          <div className="release-webhook-url">
            <Webhook aria-hidden="true" size={16} />
            <code>{receipt.webhookUrl}</code>
            <Button onClick={() => void copy()} variant="soft">
              {copied ? <Check aria-hidden="true" size={15} /> : <Clipboard aria-hidden="true" size={15} />}
              {copied
                ? t("developer.release.commerceVerification.copied")
                : t("developer.release.commerceVerification.copy")}
            </Button>
            <Button onClick={() => void openDashboard()} variant="soft">
              <ExternalLink aria-hidden="true" size={15} />
              {t("developer.release.commerceVerification.openDashboard")}
            </Button>
          </div>
          <p>{t("developer.release.creemWebhookRegistrationHint")}</p>
        </div>
      ) : null}
      {actionError ? <Callout.Root color="red" role="alert"><Callout.Text>{actionError}</Callout.Text></Callout.Root> : null}
    </section>
  );
}

function BootstrapBadge({ status }: { status: CreemWebhookBootstrapStatus }): JSX.Element {
  const { t } = useI18n();
  if (status === "ready") {
    return <Badge color="green">{t("developer.release.creemBootstrapReady")}</Badge>;
  }
  if (status === "deploying") {
    return <Badge color="blue">{t("developer.release.creemBootstrapInProgress")}</Badge>;
  }
  if (status === "error") {
    return <Badge color="red">{t("developer.release.creemBootstrapFailedBadge")}</Badge>;
  }
  return <Badge color="gray">{t("developer.release.creemBootstrapWaiting")}</Badge>;
}
