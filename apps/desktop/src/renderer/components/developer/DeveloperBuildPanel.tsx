import { Badge, Button, Callout, Spinner } from "@radix-ui/themes";
import {
  Check,
  CheckCircle2,
  FolderOpen,
  PackageCheck,
  ShieldCheck,
  TriangleAlert,
} from "lucide-react";
import { useMemo, useState } from "react";

import type { DeveloperProjectSnapshot } from "../../../shared/developerProject";
import type { DevSkillInventory } from "../../api";
import { packageDeveloperProject, showDeveloperPackage } from "../../developerAccessApi";
import type { DeveloperProjectDocument } from "../../developerProjectModel";
import { useHostBootstrap } from "../../hostBootstrap";
import { useI18n } from "../../i18n/I18nProvider";

export function DeveloperBuildPanel({
  inventory,
  onOpenAccess,
  project,
  snapshot,
}: {
  inventory: DevSkillInventory | null;
  onOpenAccess: () => void;
  project: DeveloperProjectDocument | null;
  snapshot: DeveloperProjectSnapshot | null;
}): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const identity = bootstrap.discovery?.identity;
  const [packaging, setPackaging] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [output, setOutput] = useState<{ outputPath: string; summary: string } | null>(null);
  const packages = inventory?.packages ?? [];
  const skillIssues = packages.filter((item) => !item.releaseReady);
  const checks = useMemo(() => releaseChecks(project, snapshot, inventory, skillIssues.length, t), [
    inventory,
    project,
    skillIssues.length,
    snapshot,
    t,
  ]);
  const blocking = checks.filter((check) => !check.ready);
  const canPackage = blocking.length === 0 && snapshot !== null;

  const packageApp = async () => {
    if (!canPackage || packaging) return;
    setPackaging(true);
    setError(null);
    try {
      setOutput(await packageDeveloperProject());
    } catch (cause) {
      setError(cause instanceof Error && cause.message ? cause.message : t("developer.build.packageFailed"));
    } finally {
      setPackaging(false);
    }
  };

  return (
    <section className="release-page release-build-page" aria-labelledby="developer-build-title">
      <header className="release-page-heading">
        <div>
          <span className="release-eyebrow">{t("developer.build.eyebrow")}</span>
          <h2 id="developer-build-title">{t("developer.build.title")}</h2>
          <p>{t("developer.build.description")}</p>
        </div>
        <Badge color={canPackage ? "green" : "orange"} size="2">
          {canPackage ? t("developer.build.ready") : t("developer.build.blocked")}
        </Badge>
      </header>

      <div className="developer-build-grid release-build-facts">
        <BuildFact label={t("developer.build.appName")} value={identity?.displayName ?? "—"} />
        <BuildFact label={t("developer.build.appId")} value={identity?.appId ?? String(snapshot?.manifest.appId ?? "—")} />
        <BuildFact label={t("developer.build.version")} value={identity?.version ?? String(snapshot?.manifest.version ?? "—")} />
        <BuildFact label={t("developer.build.appRoot")} value={snapshot?.appRoot ?? "—"} wide />
      </div>

      <div className="release-check-list">
        {checks.map((check) => (
          <article className={check.ready ? "is-ready" : "is-blocked"} key={check.id}>
            <span>{check.ready ? <Check aria-hidden="true" size={15} /> : <TriangleAlert aria-hidden="true" size={16} />}</span>
            <div><strong>{check.title}</strong><p>{check.description}</p></div>
            <Badge color={check.ready ? "green" : "orange"} size="1">
              {check.ready ? t("developer.build.pass") : t("developer.build.actionRequired")}
            </Badge>
          </article>
        ))}
      </div>

      {!canPackage && project?.modelAccess.configurationPolicy === "app_managed" ? (
        <Button onClick={onOpenAccess} variant="soft">
          <ShieldCheck aria-hidden="true" size={16} /> {t("developer.build.openAccess")}
        </Button>
      ) : null}

      {error ? <Callout.Root color="red" role="alert"><TriangleAlert aria-hidden="true" /><Callout.Text>{error}</Callout.Text></Callout.Root> : null}
      {output ? (
        <Callout.Root color="green" className="release-package-output">
          <CheckCircle2 aria-hidden="true" />
          <Callout.Text><strong>{output.summary}</strong><code>{output.outputPath}</code></Callout.Text>
        </Callout.Root>
      ) : null}

      <div className="release-build-actions">
        <Button disabled={!canPackage || packaging} onClick={() => void packageApp()} size="3">
          {packaging ? <Spinner /> : <PackageCheck aria-hidden="true" size={17} />}
          {packaging ? t("developer.build.packaging") : t("developer.build.package")}
        </Button>
        {output ? (
          <Button color="gray" onClick={() => void showDeveloperPackage()} variant="soft">
            <FolderOpen aria-hidden="true" size={16} /> {t("developer.build.showOutput")}
          </Button>
        ) : null}
      </div>
    </section>
  );
}

type ReleaseCheck = { id: string; ready: boolean; title: string; description: string };

function releaseChecks(
  project: DeveloperProjectDocument | null,
  snapshot: DeveloperProjectSnapshot | null,
  inventory: DevSkillInventory | null,
  skillIssueCount: number,
  t: (key: string, values?: Record<string, string | number>) => string,
): ReleaseCheck[] {
  const managed = project?.modelAccess.configurationPolicy === "app_managed";
  const providersReady = !managed || Boolean(
    project.providers.identity && project.providers.entitlement && project.providers.gateway,
  );
  return [
    {
      id: "project",
      ready: project !== null && snapshot !== null,
      title: t("developer.build.checkProject"),
      description: project && snapshot ? t("developer.build.checkProjectReady") : t("developer.build.checkProjectMissing"),
    },
    {
      id: "model",
      ready: project !== null,
      title: t("developer.build.checkModel"),
      description: managed ? t("developer.build.checkModelManaged") : t("developer.build.checkModelUser"),
    },
    {
      id: "access",
      ready: providersReady,
      title: t("developer.build.checkAccess"),
      description: providersReady ? t("developer.build.checkAccessReady") : t("developer.build.checkAccessMissing"),
    },
    {
      id: "gateway",
      ready: !managed || snapshot?.deploymentStatus === "ready",
      title: t("developer.build.checkGateway"),
      description: managed
        ? snapshot?.deploymentStatus === "ready" ? t("developer.build.checkGatewayReady") : snapshot?.deploymentMessage ?? t("developer.build.checkGatewayMissing")
        : t("developer.build.checkGatewayNotRequired"),
    },
    {
      id: "skills",
      ready: inventory !== null && skillIssueCount === 0,
      title: t("developer.build.checkSkills"),
      description: inventory === null
        ? t("developer.build.checkSkillsUnavailable")
        : skillIssueCount > 0 ? t("developer.build.issueCount", { count: skillIssueCount }) : t("developer.build.readyHint", { count: inventory.packages.length }),
    },
  ];
}

function BuildFact({ label, value, wide = false }: { label: string; value: string; wide?: boolean }) {
  return <div className={`developer-build-fact${wide ? " developer-build-fact-wide" : ""}`}><span>{label}</span><strong>{value}</strong></div>;
}
