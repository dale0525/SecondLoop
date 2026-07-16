import { useCallback, useEffect, useRef, useState } from "react";

import { listDevSkills, type DevSkillInventory } from "./api";
import { AppearanceProvider } from "./appearance/AppearanceProvider";
import { HostBootstrapProvider, useHostBootstrap } from "./hostBootstrap";
import type { DesktopHostFeatures } from "./hostFeatures";
import { I18nProvider, useI18n } from "./i18n/I18nProvider";
import {
  OwnerPolicy,
  canInspectOwnerSkills,
  getOwnerPolicy
} from "./ownerBridge";
import { Chat } from "./screens/Chat";
import { DeveloperTools, type DevApiProbeStatus } from "./screens/DeveloperTools";
import { OwnerSkills } from "./screens/OwnerSkills";
import { Settings } from "./screens/Settings";
import { Accounts } from "./screens/Accounts";
import { Memory } from "./screens/Memory";
import { FoundationActions } from "./screens/FoundationActions";
import { Connections } from "./product/Connections";
import { SecondLoopShell, type SecondLoopView } from "./product/SecondLoopShell";
import { Today } from "./product/Today";

type AppView = "today" | "chat" | "settings" | "developer" | "owner-skills" | "accounts" | "connections" | "memory" | "actions";
type DevApiProbe = {
  inventory: DevSkillInventory | null;
  status: "idle" | DevApiProbeStatus;
};

function getViewFromHash(): AppView {
  if (typeof window !== "undefined") {
    if (window.location.hash === "#developer") {
      return "developer";
    }

    if (window.location.hash === "#owner-skills") {
      return "owner-skills";
    }

    if (window.location.hash === "#settings") {
      return "settings";
    }

    if (window.location.hash === "#today") return "today";
    if (window.location.hash === "#connections") return "connections";
    if (window.location.hash === "#accounts") return "accounts";
    if (window.location.hash === "#memory") return "memory";
    if (window.location.hash === "#actions") return "actions";
  }

  return "chat";
}

export default function App(): JSX.Element {
  return (
    <I18nProvider>
      <AppearanceProvider>
        <HostBootstrapProvider>
          <AppContent />
        </HostBootstrapProvider>
      </AppearanceProvider>
    </I18nProvider>
  );
}

function AppContent(): JSX.Element {
  const [view, setView] = useState<AppView>(getViewFromHash);
  const [ownerPolicy, setOwnerPolicy] = useState<OwnerPolicy | null>(null);
  const [devApiProbe, setDevApiProbe] = useState<DevApiProbe>({
    inventory: null,
    status: "idle",
  });
  const devApiProbeStarted = useRef(false);
  const bootstrap = useHostBootstrap();
  const { t } = useI18n();
  const secondLoop = bootstrap.discovery?.identity.appId === "com.secondloop.secretary";
  const attachmentsEnabled = secondLoop
    && bootstrap.discovery?.requirements.capabilities.includes("attachments") === true
    && bootstrap.discovery.requirements.runtimeTools.includes("attachment_read")
    && bootstrap.discovery.requirements.runtimeTools.includes("attachment_get");

  useEffect(() => {
    if ((view !== "settings" && view !== "developer") || devApiProbeStarted.current) return;
    devApiProbeStarted.current = true;
    if (!window.agentWeave?.server) {
      setDevApiProbe({ inventory: null, status: "unavailable" });
      return;
    }
    setDevApiProbe({ inventory: null, status: "loading" });
    void listDevSkills()
      .then((inventory) => {
        setDevApiProbe({ inventory, status: "available" });
      })
      .catch(() => {
        setDevApiProbe({ inventory: null, status: "unavailable" });
      });
  }, [view]);

  const handleDevInventoryChange = useCallback((inventory: DevSkillInventory) => {
    setDevApiProbe({ inventory, status: "available" });
  }, []);

  useEffect(() => {
    let active = true;
    if (!bootstrap.features.skillManagement) {
      setOwnerPolicy({ mode: "disabled", actorId: "anonymous", role: "anonymous", grants: [] });
      return () => {
        active = false;
      };
    }
    setOwnerPolicy(null);
    getOwnerPolicy()
      .then((policy) => {
        if (active) setOwnerPolicy(policy);
      })
      .catch(() => {
        if (active) {
          setOwnerPolicy({ mode: "disabled", actorId: "anonymous", role: "anonymous", grants: [] });
        }
      });
    return () => {
      active = false;
    };
  }, [bootstrap.features.skillManagement]);

  useEffect(() => {
    document.title = bootstrap.discovery?.identity.displayName ?? t("app.name");
  }, [bootstrap.discovery, t]);

  useEffect(() => {
    const syncViewFromHash = () => setView(getViewFromHash());

    window.addEventListener("hashchange", syncViewFromHash);

    return () => window.removeEventListener("hashchange", syncViewFromHash);
  }, []);

  const navigate = (nextView: AppView) => {
    setView(nextView);
    const nextHash = nextView === "chat" && !secondLoop ? "" : `#${nextView}`;
    if (typeof window !== "undefined" && window.location.hash !== nextHash) {
      window.location.hash = nextHash;
    }
  };

  useEffect(() => {
    if (bootstrap.status !== "ready" || !secondLoop) return;
    if (!window.location.hash) navigate("today");
    if (view === "accounts") navigate("connections");
  }, [bootstrap.status, secondLoop, view]);

  useEffect(() => {
    if (
      bootstrap.status !== "loading"
      && !isViewAllowed(view, bootstrap.features, ownerPolicy, secondLoop, devApiProbe.status)
    ) {
      navigate("settings");
    }
  }, [bootstrap.features, bootstrap.status, devApiProbe.status, ownerPolicy, secondLoop, view]);

  const activeView = isViewAllowed(
    view,
    bootstrap.features,
    ownerPolicy,
    secondLoop,
    devApiProbe.status,
  )
    ? view
    : "settings";

  const screen = (
    <>
      {activeView === "owner-skills" ? (
        canInspectOwnerSkills(ownerPolicy) ? (
          <OwnerSkills
            onBack={() => navigate("settings")}
            policy={ownerPolicy as OwnerPolicy}
          />
        ) : (
          <Settings
            developerToolsAvailable={devApiProbe.status === "available"}
            onBack={() => navigate("chat")}
            onOpenDeveloperTools={() => navigate("developer")}
            onOpenOwnerSkills={() => navigate("owner-skills")}
            onOpenAccounts={() => navigate("accounts")}
            onOpenMemory={() => navigate("memory")}
            onOpenActions={() => navigate("actions")}
            ownerPolicy={ownerPolicy}
          />
        )
      ) : activeView === "developer" ? (
        <DeveloperTools
          initialInventory={devApiProbe.inventory}
          initialStatus={devApiProbe.status === "idle" ? "loading" : devApiProbe.status}
          onBack={() => navigate("settings")}
          onInventoryChange={handleDevInventoryChange}
        />
      ) : activeView === "accounts" ? (
        <Accounts onBack={() => navigate("settings")} />
      ) : activeView === "connections" ? (
        <Connections />
      ) : activeView === "memory" ? (
        <Memory embedded={secondLoop} onBack={() => navigate(secondLoop ? "today" : "settings")} />
      ) : activeView === "actions" ? (
        <FoundationActions embedded={secondLoop} onBack={() => navigate(secondLoop ? "today" : "settings")} />
      ) : activeView === "settings" ? (
        <Settings
          developerToolsAvailable={devApiProbe.status === "available"}
          onBack={() => navigate(secondLoop ? "today" : "chat")}
          onOpenDeveloperTools={() => navigate("developer")}
          onOpenOwnerSkills={() => navigate("owner-skills")}
          onOpenAccounts={() => navigate(secondLoop ? "connections" : "accounts")}
          onOpenMemory={() => navigate("memory")}
          onOpenActions={() => navigate("actions")}
          ownerPolicy={ownerPolicy}
          productMode={secondLoop}
        />
      ) : activeView === "today" ? (
        <Today />
      ) : (
        <Chat
          attachmentsEnabled={attachmentsEnabled}
          onOpenConnections={() => navigate("connections")}
          onOpenSettings={() => navigate("settings")}
          productMode={secondLoop}
        />
      )}
    </>
  );

  return (
    <div className="app-root">
      {secondLoop ? (
        <SecondLoopShell
          activeView={activeView as SecondLoopView}
          onNavigate={(nextView) => navigate(nextView)}
        >
          {screen}
        </SecondLoopShell>
      ) : screen}
    </div>
  );
}

function isViewAllowed(
  view: AppView,
  features: DesktopHostFeatures,
  ownerPolicy: OwnerPolicy | null,
  secondLoop: boolean,
  devApiStatus: DevApiProbe["status"] = "unavailable",
): boolean {
  if (view === "today") return secondLoop;
  if (view === "connections") return secondLoop;
  if (view === "accounts") return features.accounts;
  if (view === "memory") return features.memory;
  if (view === "actions") return features.actions;
  if (view === "developer") return devApiStatus !== "unavailable";
  if (view === "owner-skills") {
    return features.skillManagement && canInspectOwnerSkills(ownerPolicy);
  }
  return true;
}
