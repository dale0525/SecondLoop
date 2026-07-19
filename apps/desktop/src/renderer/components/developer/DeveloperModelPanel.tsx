import { Badge, Button, Callout, RadioCards, Text } from "@radix-ui/themes";
import { KeyRound, LockKeyhole, Route, UserRoundCog } from "lucide-react";
import { useState, type ReactNode } from "react";

import type { DeveloperProjectSnapshot } from "../../../shared/developerProject";
import type { DeveloperProjectDocument } from "../../developerProjectModel";
import { userConfigurableProject } from "../../developerProjectModel";
import { useI18n } from "../../i18n/I18nProvider";

export function DeveloperModelPanel({
  snapshot,
  project,
  onConfigureManaged,
  onSaved,
}: {
  snapshot: DeveloperProjectSnapshot;
  project: DeveloperProjectDocument;
  onConfigureManaged: () => void;
  onSaved: (snapshot: DeveloperProjectSnapshot) => void;
}): JSX.Element {
  const { t } = useI18n();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const policy = project.modelAccess.configurationPolicy;

  const choose = async (value: string) => {
    if (value === "app_managed") {
      onConfigureManaged();
      return;
    }
    if (policy === "user_configurable") return;
    setSaving(true);
    setError(null);
    try {
      const api = window.agentWeave?.developerProject;
      if (!api) throw new Error("Developer project API is unavailable");
      onSaved(await api.save({
        expectedRevision: snapshot.revision,
        project: userConfigurableProject(project),
      }));
    } catch {
      setError(t("developer.release.modelSaveError"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <section className="release-page release-model-page" aria-labelledby="release-model-title">
      <header className="release-page-heading">
        <div>
          <span className="release-eyebrow">{t("developer.release.modelEyebrow")}</span>
          <h2 id="release-model-title">{t("developer.release.modelTitle")}</h2>
          <p>{t("developer.release.modelDescription")}</p>
        </div>
        <Badge color={policy === "app_managed" ? "blue" : "gray"} size="2">
          {policy === "app_managed"
            ? t("developer.release.modelAppManaged")
            : t("developer.release.modelUserConfigurable")}
        </Badge>
      </header>

      {error ? <Callout.Root color="red"><Callout.Text>{error}</Callout.Text></Callout.Root> : null}

      <RadioCards.Root
        className="release-policy-cards"
        disabled={saving}
        onValueChange={(value) => void choose(value)}
        value={policy}
      >
        <RadioCards.Item value="user_configurable">
          <PolicyChoice
            icon={<UserRoundCog aria-hidden="true" size={22} />}
            title={t("developer.release.policyUserTitle")}
            description={t("developer.release.policyUserDescription")}
            facts={[t("developer.release.policyUserFact1"), t("developer.release.policyUserFact2")]}
          />
        </RadioCards.Item>
        <RadioCards.Item value="app_managed">
          <PolicyChoice
            icon={<LockKeyhole aria-hidden="true" size={22} />}
            title={t("developer.release.policyManagedTitle")}
            description={t("developer.release.policyManagedDescription")}
            facts={[t("developer.release.policyManagedFact1"), t("developer.release.policyManagedFact2")]}
          />
        </RadioCards.Item>
      </RadioCards.Root>

      {policy === "app_managed" ? (
        <div className="release-current-profile">
          <div className="release-current-profile-title">
            <Route aria-hidden="true" size={20} />
            <div>
              <strong>{t("developer.release.currentProfile")}</strong>
              <Text color="gray" size="2">{t("developer.release.currentProfileHint")}</Text>
            </div>
          </div>
          <dl className="release-facts">
            <Fact label={t("developer.release.modelName")} value={project.modelAccess.profile.modelName} />
            <Fact label={t("developer.release.endpointType")} value={project.modelAccess.profile.endpointType} />
            <Fact label={t("developer.release.gatewayEndpoint")} value={project.modelAccess.profile.baseUrl} wide />
          </dl>
          <Button onClick={onConfigureManaged} size="3">{t("developer.release.reviewAccess")}</Button>
        </div>
      ) : (
        <Callout.Root color="gray" className="release-policy-note">
          <KeyRound aria-hidden="true" />
          <Callout.Text>
            {t("developer.release.byokNote")}
          </Callout.Text>
        </Callout.Root>
      )}
    </section>
  );
}

function PolicyChoice({
  icon,
  title,
  description,
  facts,
}: {
  icon: ReactNode;
  title: string;
  description: string;
  facts: readonly string[];
}): JSX.Element {
  return (
    <div className="release-policy-choice">
      <span className="release-policy-icon">{icon}</span>
      <div>
        <strong>{title}</strong>
        <Text as="p" color="gray" size="2">{description}</Text>
      </div>
      <ul>{facts.map((fact) => <li key={fact}>{fact}</li>)}</ul>
    </div>
  );
}

function Fact({ label, value, wide = false }: { label: string; value: string; wide?: boolean }) {
  return (
    <div className={wide ? "release-fact release-fact-wide" : "release-fact"}>
      <dt>{label}</dt><dd>{value || "—"}</dd>
    </div>
  );
}
