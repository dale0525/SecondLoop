import { Badge, Button, Callout, Card, Flex, Spinner, Text } from "@radix-ui/themes";
import { ArrowRight, CircleAlert, Settings2, ShieldCheck } from "lucide-react";
import type { PropsWithChildren } from "react";

import { useHostBootstrap } from "../hostBootstrap";
import { useI18n } from "../i18n/I18nProvider";
import { useIdentitySession } from "../identitySession";

export function IdentityRequiredScreen({
  children,
  onOpenSettings,
}: PropsWithChildren<{ onOpenSettings: () => void }>): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const identity = useIdentitySession();
  if (identity.state === "not_required" || identity.state === "signed_in") {
    return <>{children}</>;
  }
  const appName = bootstrap.discovery?.identity.displayName ?? t("app.name");
  return (
    <main className="identity-gate" aria-labelledby="identity-gate-title">
      <Card className="identity-gate-card" size="4">
        <Flex direction="column" gap="5">
          <Flex align="center" justify="between" gap="3">
            <span className="identity-gate-mark" aria-hidden="true">
              <ShieldCheck size={22} />
            </span>
            <Badge color="green" variant="soft">{t("identity.secureSession")}</Badge>
          </Flex>
          <Flex direction="column" gap="2">
            <Text as="div" size="6" weight="bold" id="identity-gate-title">
              {t("identity.signInTo", { app: appName })}
            </Text>
            <Text as="p" color="gray" size="3">
              {t("identity.signInDescription")}
            </Text>
          </Flex>
          {identity.state === "waiting" ? (
            <Callout.Root color="blue" role="status">
              <Callout.Icon><Spinner /></Callout.Icon>
              <Callout.Text>{t("identity.waitingForBrowser")}</Callout.Text>
            </Callout.Root>
          ) : identity.state === "unavailable" ? (
            <Callout.Root color="red" role="alert">
              <Callout.Icon><CircleAlert size={16} /></Callout.Icon>
              <Callout.Text>{t("identity.unavailable")}</Callout.Text>
            </Callout.Root>
          ) : null}
          <Flex direction={{ initial: "column", sm: "row" }} gap="3">
            <Button
              disabled={identity.state === "loading" || identity.state === "waiting"}
              onClick={() => void identity.start()}
              size="3"
            >
              {identity.state === "loading" ? <Spinner /> : <ArrowRight size={16} />}
              {identity.state === "unavailable" ? t("identity.tryAgain") : t("identity.signIn")}
            </Button>
            <Button color="gray" onClick={onOpenSettings} size="3" variant="soft">
              <Settings2 size={16} /> {t("identity.openSettings")}
            </Button>
          </Flex>
          <Text as="p" color="gray" size="1">
            {t("identity.privacyNote")}
          </Text>
        </Flex>
      </Card>
    </main>
  );
}
