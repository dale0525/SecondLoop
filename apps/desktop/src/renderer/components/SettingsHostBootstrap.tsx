import { Button, Callout } from "@radix-ui/themes";
import { CircleAlert, LoaderCircle, RotateCw, ShieldCheck } from "lucide-react";

import { useHostBootstrap } from "../hostBootstrap";
import { useI18n } from "../i18n/I18nProvider";

export function SettingsHostBootstrap(): JSX.Element {
  const bootstrap = useHostBootstrap();
  const { t } = useI18n();

  if (bootstrap.status === "loading") {
    return (
      <Callout.Root color="gray" role="status" size="2">
        <Callout.Icon><LoaderCircle className="spin" aria-hidden="true" /></Callout.Icon>
        <Callout.Text>{t("hostBootstrap.loading")}</Callout.Text>
      </Callout.Root>
    );
  }

  if (bootstrap.status === "unavailable") {
    return (
      <Callout.Root color="amber" role="alert" size="2">
        <Callout.Icon><CircleAlert aria-hidden="true" /></Callout.Icon>
        <Callout.Text>{t("hostBootstrap.unavailable")}</Callout.Text>
        <Button onClick={bootstrap.reload} size="1" variant="soft">
          <RotateCw aria-hidden="true" size={14} /> {t("hostBootstrap.retry")}
        </Button>
      </Callout.Root>
    );
  }

  return (
    <Callout.Root color="green" role="status" size="2">
      <Callout.Icon><ShieldCheck aria-hidden="true" /></Callout.Icon>
      <Callout.Text>
        {t("hostBootstrap.ready", {
          name: bootstrap.discovery?.identity.displayName ?? "",
          version: bootstrap.discovery?.identity.version ?? "",
        })}
      </Callout.Text>
    </Callout.Root>
  );
}
