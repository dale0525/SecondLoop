import { Button, Spinner, Text, TextField } from "@radix-ui/themes";
import { LogIn } from "lucide-react";
import { FormEvent, useState } from "react";

import { useI18n } from "../i18n/I18nProvider";
import { useIdentitySession } from "../identitySession";

export function IdentityPasswordForm(): JSX.Element {
  const { t } = useI18n();
  const identity = useIdentitySession();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (!email.trim() || !password) return;
    void identity.password(email.trim(), password).finally(() => setPassword(""));
  };
  return (
    <form className="identity-password-form" onSubmit={submit}>
      <label>
        <Text size="2" weight="medium">{t("identity.email")}</Text>
        <TextField.Root
          autoComplete="email"
          disabled={identity.state === "loading"}
          onChange={(event) => setEmail(event.target.value)}
          required
          type="email"
          value={email}
        />
      </label>
      <label>
        <Text size="2" weight="medium">{t("identity.password")}</Text>
        <TextField.Root
          autoComplete="current-password"
          disabled={identity.state === "loading"}
          onChange={(event) => setPassword(event.target.value)}
          required
          type="password"
          value={password}
        />
      </label>
      <Button disabled={identity.state === "loading" || !email.trim() || !password} size="3" type="submit">
        {identity.state === "loading" ? <Spinner /> : <LogIn size={16} />}
        {identity.state === "unavailable" ? t("identity.tryAgain") : t("identity.signInWithEmail")}
      </Button>
    </form>
  );
}
