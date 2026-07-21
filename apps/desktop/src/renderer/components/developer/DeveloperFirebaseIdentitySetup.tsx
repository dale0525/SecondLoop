import { Badge, Button, Callout, Select, Spinner, Text, TextField } from "@radix-ui/themes";
import { Check, ExternalLink, Flame, RotateCcw, WandSparkles } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import type {
  FirebaseAuthorizationStatus,
  FirebaseProject,
} from "../../developerAccessApi";
import { useI18n } from "../../i18n/I18nProvider";

export function DeveloperFirebaseIdentitySetup({
  busy,
  configuredProjectId,
  onCancel,
  onConfigure,
  onConnect,
  onRetryProjects,
  projects,
  projectsFailed,
  projectsLoading,
  status,
}: {
  busy: string | null;
  configuredProjectId: string | null;
  onCancel: () => void;
  onConfigure: (projectId: string) => void;
  onConnect: (client: { clientId?: string; clientSecret?: string; publicClient: boolean }) => void;
  onRetryProjects: () => void;
  projects: readonly FirebaseProject[];
  projectsFailed: boolean;
  projectsLoading: boolean;
  status?: FirebaseAuthorizationStatus;
}): JSX.Element {
  const { t } = useI18n();
  const [custom, setCustom] = useState(false);
  const [clientId, setClientId] = useState("");
  const [clientSecret, setClientSecret] = useState("");
  const [projectId, setProjectId] = useState(configuredProjectId ?? "");
  const automaticProjectRef = useRef<string | null>(null);
  const phase = status?.phase ?? "disconnected";
  const configuring = busy === "firebase-configure";
  const ready = phase === "ready" && Boolean(status?.projectId || configuredProjectId);
  const useCustom = custom || status?.publicOauthClientAvailable === false;
  const selectedProject = projects.find((project) => project.projectId === projectId);
  useEffect(() => {
    if (phase !== "select_project" || projects.length !== 1 || busy !== null) return;
    const onlyProject = projects[0];
    if (automaticProjectRef.current === onlyProject.projectId) return;
    automaticProjectRef.current = onlyProject.projectId;
    setProjectId(onlyProject.projectId);
    onConfigure(onlyProject.projectId);
  }, [busy, onConfigure, phase, projects]);
  return (
    <div className={`release-firebase-card is-${configuring ? "configuring" : phase}`}>
      <div className="release-firebase-heading">
        <span className="release-firebase-mark"><Flame aria-hidden="true" size={20} /></span>
        <div>
          <strong>{t("developer.release.firebaseTitle")}</strong>
          <Text as="p" color="gray" size="2">{t("developer.release.firebaseHint")}</Text>
        </div>
        <Badge color={ready ? "green" : "orange"} variant="soft">
          {ready ? t("developer.release.autoConfigured") : t("developer.release.firebaseRecommended")}
        </Badge>
      </div>

      {(phase === "disconnected" || phase === "expired") && !configuring ? (
        <div className="release-firebase-actions">
          {!useCustom ? (
            <Button disabled={busy !== null} onClick={() => onConnect({ publicClient: true })} size="3">
              {busy === "firebase-oauth" ? <Spinner /> : <ExternalLink aria-hidden="true" size={16} />}
              {t("developer.release.continueWithGoogle")}
            </Button>
          ) : null}
          <details className="release-advanced" open={status?.publicOauthClientAvailable === false || undefined}>
            <summary>{t("developer.release.firebaseCustomOauth")}</summary>
            {status?.publicOauthClientAvailable !== false ? (
              <label className="release-inline-toggle">
                <input checked={custom} onChange={(event) => setCustom(event.target.checked)} type="checkbox" />
                <span><strong>{t("developer.release.useCustomOauth")}</strong></span>
              </label>
            ) : (
              <Callout.Root color="orange" size="1">
                <Callout.Text>{t("developer.release.firebasePublicOauthUnavailable")}</Callout.Text>
              </Callout.Root>
            )}
            {useCustom ? (
              <div className="release-schema-fields">
                <label className="release-field">
                  <Text size="2" weight="medium">{t("developer.release.firebaseOauthClientId")}</Text>
                  <TextField.Root onChange={(event) => setClientId(event.target.value)} value={clientId} />
                </label>
                <label className="release-field">
                  <Text size="2" weight="medium">{t("developer.release.oauthClientSecretOptional")}</Text>
                  <TextField.Root
                    onChange={(event) => setClientSecret(event.target.value)}
                    type="password"
                    value={clientSecret}
                  />
                </label>
                <Button
                  disabled={busy !== null || !clientId.trim()}
                  onClick={() => onConnect({
                    clientId: clientId.trim(),
                    clientSecret: clientSecret.trim() || undefined,
                    publicClient: false,
                  })}
                >
                  {busy === "firebase-oauth" ? <Spinner /> : <ExternalLink aria-hidden="true" size={16} />}
                  {t("developer.release.connectGoogle")}
                </Button>
              </div>
            ) : null}
          </details>
        </div>
      ) : null}

      {phase === "awaiting_callback" ? (
        <div className="release-oauth-waiting">
          <Spinner size="3" />
          <Text color="gray" size="2">{t("developer.release.firebaseWaiting")}</Text>
          <Button color="gray" disabled={busy !== null} onClick={onCancel} variant="soft">
            <RotateCcw aria-hidden="true" size={16} /> {t("developer.release.cancelAuthorization")}
          </Button>
        </div>
      ) : null}

      {phase === "select_project" && !configuring ? (
        <div className="release-firebase-project-picker">
          <label className="release-field">
            <Text size="2" weight="medium">{t("developer.release.firebaseProject")}</Text>
            <Select.Root onValueChange={setProjectId} value={projectId}>
              <Select.Trigger placeholder={t("developer.release.selectFirebaseProject")} />
              <Select.Content>{projects.map((project) => (
                <Select.Item key={project.projectId} value={project.projectId}>
                  {project.displayName} · {project.projectId}
                </Select.Item>
              ))}</Select.Content>
            </Select.Root>
          </label>
          <Button
            color={projectsFailed ? "gray" : undefined}
            disabled={busy !== null || projectsLoading || (!projectsFailed && !selectedProject)}
            onClick={() => projectsFailed ? onRetryProjects() : onConfigure(projectId)}
            size="3"
          >
            {projectsLoading ? <Spinner /> : projectsFailed
              ? <RotateCcw aria-hidden="true" size={16} />
              : <WandSparkles aria-hidden="true" size={16} />}
            {projectsFailed
              ? t("developer.release.retryFirebaseProjects")
              : t("developer.release.configureFirebase")}
          </Button>
        </div>
      ) : null}

      {configuring || ready ? (
        <div className="release-firebase-progress" role="status">
          {[
            "firebaseProjectLinked",
            "firebaseIdentityEnabled",
            "firebaseWebAppReady",
            "firebaseEmailEnabled",
            "firebaseVerified",
          ].map((key) => (
            <span key={key}>
              {configuring ? <Spinner size="1" /> : <Check aria-hidden="true" size={14} />}
              {t(`developer.release.${key}`)}
            </span>
          ))}
          {ready ? <code>{status?.projectId ?? configuredProjectId}</code> : null}
        </div>
      ) : null}
    </div>
  );
}
