import { Badge, Button, Callout, Flex, Spinner, Text } from "@radix-ui/themes";
import { CircleAlert, LogIn, LogOut, UserRoundCheck } from "lucide-react";

import { useI18n } from "../i18n/I18nProvider";
import { useIdentitySession } from "../identitySession";
import { IdentityPasswordForm } from "./IdentityPasswordForm";

export function SettingsIdentity(): JSX.Element {
  const { t } = useI18n();
  const identity = useIdentitySession();
  const accountReference = identity.account?.id.slice(-8).toUpperCase() ?? null;
  return (
    <section className="settings-panel settings-identity-panel" aria-labelledby="settings-identity-title">
      <div className="settings-panel-heading">
        <Flex align="center" gap="2">
          <h2 id="settings-identity-title">{t("identity.accountTitle")}</h2>
          {identity.state === "signed_in" ? (
            <Badge color="green" variant="soft">{t("identity.signedIn")}</Badge>
          ) : null}
        </Flex>
        <p>{t("identity.accountDescription")}</p>
      </div>

      {identity.state === "signed_in" ? (
        <Flex align={{ initial: "stretch", sm: "center" }} justify="between" gap="4">
          <Flex align="center" gap="3">
            <span className="settings-identity-avatar" aria-hidden="true">
              <UserRoundCheck size={20} />
            </span>
            <Flex direction="column" gap="1">
              <Text size="2" weight="bold">{t("identity.currentAccount")}</Text>
              <Text color="gray" size="1">
                {t("identity.accountReference", { reference: accountReference ?? "" })}
              </Text>
            </Flex>
          </Flex>
          <Button color="gray" onClick={() => void identity.logout()} variant="soft">
            <LogOut size={16} /> {t("identity.signOut")}
          </Button>
        </Flex>
      ) : identity.state === "waiting" ? (
        <Callout.Root color="blue" role="status">
          <Callout.Icon><Spinner /></Callout.Icon>
          <Callout.Text>{t("identity.waitingForBrowser")}</Callout.Text>
        </Callout.Root>
      ) : (
        <Flex direction="column" gap="3">
          {identity.state === "unavailable" ? (
            <Callout.Root color="red" role="alert">
              <Callout.Icon><CircleAlert size={16} /></Callout.Icon>
              <Callout.Text>{t("identity.unavailable")}</Callout.Text>
            </Callout.Root>
          ) : null}
          {identity.method === "password" ? <IdentityPasswordForm /> : (
            <Button
              disabled={identity.state === "loading"}
              onClick={() => void identity.start()}
            >
              {identity.state === "loading" ? <Spinner /> : <LogIn size={16} />}
              {identity.state === "unavailable" ? t("identity.tryAgain") : t("identity.signIn")}
            </Button>
          )}
        </Flex>
      )}
    </section>
  );
}
