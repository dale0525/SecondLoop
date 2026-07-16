import { Badge, Button, Card, Flex, Heading, Text } from "@radix-ui/themes";
import { Building2, CheckCircle2, CircleAlert, LoaderCircle, ShieldCheck, X } from "lucide-react";
import { useEffect, useState } from "react";

import { useI18n } from "../i18n/I18nProvider";
import { rememberWorkspaceBindings } from "../workspaceBindings";
import {
  cancelWorkspaceOAuth,
  getWorkspaceOAuthStatus,
  startWorkspaceOAuth,
  type OAuthAuthorizationStatus,
  type OAuthAuthorizationView,
} from "../workspaceApi";

const AUTHORIZATIONS = {
  google: {
    connectorIds: ["agentweave-mail", "agentweave-calendar", "agentweave-contacts"],
    providerId: "google-workspace",
    requestedCapabilities: ["mail", "calendar", "contacts"],
  },
  microsoftMail: {
    connectorIds: ["agentweave-mail"],
    providerId: "microsoft-graph",
    requestedCapabilities: ["mail"],
  },
  microsoftWorkspace: {
    connectorIds: ["agentweave-calendar", "agentweave-contacts"],
    providerId: "microsoft-graph",
    requestedCapabilities: ["calendar", "contacts"],
  },
} as const;

type AuthorizationKey = keyof typeof AUTHORIZATIONS;
type AuthorizationState = Readonly<{
  authorizationId?: string;
  errorCode?: string | null;
  status: "idle" | "starting" | OAuthAuthorizationStatus;
  view?: OAuthAuthorizationView;
}>;

const INITIAL_STATE: Record<AuthorizationKey, AuthorizationState> = {
  google: { status: "idle" },
  microsoftMail: { status: "idle" },
  microsoftWorkspace: { status: "idle" },
};

export function WorkspaceOAuthPanel({ onBindingsChanged }: {
  onBindingsChanged: () => void;
}): JSX.Element {
  const { t } = useI18n();
  const [authorizations, setAuthorizations] = useState(INITIAL_STATE);

  useEffect(() => {
    const timers = (Object.entries(authorizations) as Array<[AuthorizationKey, AuthorizationState]>)
      .filter(([, state]) => state.authorizationId && isPolling(state.status))
      .map(([key, state]) => window.setTimeout(() => {
        void pollAuthorization(key, state.authorizationId!);
      }, 900));
    return () => timers.forEach(window.clearTimeout);
  }, [authorizations]);

  const update = (key: AuthorizationKey, next: AuthorizationState) => {
    setAuthorizations((current) => ({ ...current, [key]: next }));
  };

  const pollAuthorization = async (key: AuthorizationKey, authorizationId: string) => {
    try {
      const view = await getWorkspaceOAuthStatus(authorizationId);
      if (view.status === "completed") {
        rememberWorkspaceBindings(view);
        onBindingsChanged();
      }
      setAuthorizations((current) => current[key].authorizationId !== authorizationId
        ? current
        : { ...current, [key]: stateFromView(view) });
    } catch {
      setAuthorizations((current) => current[key].authorizationId !== authorizationId
        ? current
        : { ...current, [key]: { authorizationId, errorCode: "status_unavailable", status: "failed" } });
    }
  };

  const start = async (key: AuthorizationKey) => {
    update(key, { status: "starting" });
    try {
      const summary = await startWorkspaceOAuth(AUTHORIZATIONS[key]);
      update(key, { authorizationId: summary.authorizationId, status: summary.status });
    } catch {
      update(key, { errorCode: "provider_unavailable", status: "failed" });
    }
  };

  const cancel = async (key: AuthorizationKey) => {
    const authorizationId = authorizations[key].authorizationId;
    if (!authorizationId) return;
    try {
      update(key, stateFromView(await cancelWorkspaceOAuth(authorizationId)));
    } catch {
      update(key, { authorizationId, errorCode: "cancel_failed", status: "failed" });
    }
  };

  return (
    <section className="workspace-oauth" id="secondloop-workspace-oauth">
      <div className="workspace-oauth-heading">
        <div>
          <Text className="foundation-kicker" size="1" weight="bold">
            {t("connections.workspace.eyebrow")}
          </Text>
          <Heading as="h2" mt="2" size="5">{t("connections.workspace.title")}</Heading>
          <Text as="p" color="gray" mt="2" size="2">
            {t("connections.workspace.description")}
          </Text>
        </div>
        <span className="workspace-oauth-boundary"><ShieldCheck size={16} /> {t("connections.workspace.boundary")}</span>
      </div>
      <div className="workspace-provider-grid">
        <ProviderCard
          description={t("connections.workspace.googleDescription")}
          icon={<span className="workspace-provider-letter">G</span>}
          title="Google Workspace"
        >
          <AuthorizationRow
            label={t("connections.workspace.allServices")}
            onCancel={() => void cancel("google")}
            onStart={() => void start("google")}
            state={authorizations.google}
          />
        </ProviderCard>
        <ProviderCard
          description={t("connections.workspace.microsoftDescription")}
          icon={<Building2 size={20} />}
          title="Microsoft 365"
        >
          <AuthorizationRow
            label={t("connections.workspace.mailAccess")}
            onCancel={() => void cancel("microsoftMail")}
            onStart={() => void start("microsoftMail")}
            state={authorizations.microsoftMail}
          />
          <AuthorizationRow
            label={t("connections.workspace.calendarContactsAccess")}
            onCancel={() => void cancel("microsoftWorkspace")}
            onStart={() => void start("microsoftWorkspace")}
            state={authorizations.microsoftWorkspace}
          />
        </ProviderCard>
      </div>
    </section>
  );
}

function ProviderCard({ children, description, icon, title }: {
  children: React.ReactNode;
  description: string;
  icon: React.ReactNode;
  title: string;
}): JSX.Element {
  return (
    <Card className="workspace-provider-card" size="3">
      <Flex align="start" gap="3">
        <span className="workspace-provider-icon">{icon}</span>
        <div className="workspace-provider-copy">
          <Text as="div" weight="bold">{title}</Text>
          <Text as="p" color="gray" mt="1" size="2">{description}</Text>
        </div>
      </Flex>
      <div className="workspace-authorization-list">{children}</div>
    </Card>
  );
}

function AuthorizationRow({ label, onCancel, onStart, state }: {
  label: string;
  onCancel: () => void;
  onStart: () => void;
  state: AuthorizationState;
}): JSX.Element {
  const { t } = useI18n();
  const active = state.status === "starting" || isPolling(state.status);
  const complete = state.status === "completed";
  const failed = isFailure(state.status);
  const permissionInsufficient = state.errorCode === "permission_insufficient";
  const statusLabel = permissionInsufficient
    ? t("connections.workspace.status.permissionInsufficient")
    : t(`connections.workspace.status.${state.status}`);
  return (
    <div className="workspace-authorization-row">
      <div className="workspace-authorization-copy">
        <Text as="div" size="2" weight="bold">{label}</Text>
        {state.view?.bindings[0]?.accountId ? (
          <Text as="div" color="gray" size="1">{state.view.bindings[0].accountId}</Text>
        ) : null}
      </div>
      <Badge color={complete ? "green" : failed ? "red" : active ? "blue" : "gray"} radius="full">
        {active ? <LoaderCircle className="spin" size={12} /> : null}
        {complete ? <CheckCircle2 size={12} /> : null}
        {failed ? <CircleAlert size={12} /> : null}
        {statusLabel}
      </Badge>
      {active && state.authorizationId ? (
        <Button aria-label={t("connections.workspace.cancel")} onClick={onCancel} variant="ghost">
          <X size={15} /> {t("connections.workspace.cancel")}
        </Button>
      ) : (
        <Button onClick={onStart} variant={complete ? "soft" : "solid"}>
          {complete || failed ? t("connections.workspace.reauthorize") : t("connections.workspace.authorize")}
        </Button>
      )}
    </div>
  );
}

function stateFromView(view: OAuthAuthorizationView): AuthorizationState {
  return {
    authorizationId: view.authorizationId,
    errorCode: view.errorCode,
    status: view.status,
    view,
  };
}

function isPolling(status: AuthorizationState["status"]): boolean {
  return status === "pending" || status === "preparing" || status === "exchanging";
}

function isFailure(status: AuthorizationState["status"]): boolean {
  return status === "cancelled"
    || status === "denied"
    || status === "expired"
    || status === "failed";
}
