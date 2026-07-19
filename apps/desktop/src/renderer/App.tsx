import { useCallback, useEffect, useRef, useState } from "react";

import { listDevSkills, type DevSkillInventory } from "./api";
import { AppearanceProvider } from "./appearance/AppearanceProvider";
import { HostBootstrapProvider, useHostBootstrap } from "./hostBootstrap";
import { IdentitySessionProvider } from "./identitySession";
import type { DesktopHostFeatures } from "./hostFeatures";
import { I18nProvider, useI18n } from "./i18n/I18nProvider";
import {
  OwnerPolicy,
  canInspectOwnerSkills,
  getOwnerPolicy
} from "./ownerBridge";
import { Chat } from "./screens/Chat";
import {
  DeveloperTools,
  type DevApiProbeStatus,
  type DeveloperRoute,
} from "./screens/DeveloperTools";
import { OwnerSkills } from "./screens/OwnerSkills";
import { Settings } from "./screens/Settings";
import { Accounts } from "./screens/Accounts";
import { Memory } from "./screens/Memory";
import { FoundationActions } from "./screens/FoundationActions";
import { IdentityRequiredScreen } from "./components/IdentityRequiredScreen";

type AppView = "chat" | "settings" | "developer" | "owner-skills" | "accounts" | "memory" | "actions";
type DevApiProbe = {
  inventory: DevSkillInventory | null;
  status: "idle" | DevApiProbeStatus;
};

function getViewFromHash(): AppView {
  if (typeof window !== "undefined") {
    if (window.location.hash === "#developer" || window.location.hash.startsWith("#developer/")) {
      return "developer";
    }

    if (window.location.hash === "#owner-skills") {
      return "owner-skills";
    }

    if (window.location.hash === "#settings") {
      return "settings";
    }

    if (window.location.hash === "#accounts") return "accounts";
    if (window.location.hash === "#memory") return "memory";
    if (window.location.hash === "#actions") return "actions";
  }

  return "chat";
}

function getDeveloperRouteFromHash(): DeveloperRoute {
  if (typeof window === "undefined") return "model";
  const route = window.location.hash.replace(/^#developer\/?/, "");
  if (route === "model" || route === "access" || route === "access/setup"
    || route === "skills" || route === "build") return route;
  return window.location.hash === "#developer" ? "skills" : "model";
}

export default function App(): JSX.Element {
  return (
    <I18nProvider>
      <AppearanceProvider>
        <HostBootstrapProvider>
          <IdentitySessionProvider>
            <AppContent />
          </IdentitySessionProvider>
        </HostBootstrapProvider>
      </AppearanceProvider>
    </I18nProvider>
  );
}

function AppContent(): JSX.Element {
  const [view, setView] = useState<AppView>(getViewFromHash);
  const [developerRoute, setDeveloperRoute] = useState<DeveloperRoute>(getDeveloperRouteFromHash);
  const [ownerPolicy, setOwnerPolicy] = useState<OwnerPolicy | null>(null);
  const [devApiProbe, setDevApiProbe] = useState<DevApiProbe>({
    inventory: null,
    status: "idle",
  });
  const devApiProbeStarted = useRef(false);
  const bootstrap = useHostBootstrap();
  const { t } = useI18n();

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
    const syncViewFromHash = () => {
      setView(getViewFromHash());
      if (getViewFromHash() === "developer") setDeveloperRoute(getDeveloperRouteFromHash());
    };

    window.addEventListener("hashchange", syncViewFromHash);

    return () => window.removeEventListener("hashchange", syncViewFromHash);
  }, []);

  const navigate = (nextView: AppView) => {
    setView(nextView);
    const nextHash = nextView === "chat" ? "" : `#${nextView}`;
    if (typeof window !== "undefined" && window.location.hash !== nextHash) {
      window.location.hash = nextHash;
    }
  };

  const navigateDeveloper = (nextRoute: DeveloperRoute = developerRoute) => {
    setDeveloperRoute(nextRoute);
    setView("developer");
    const nextHash = `#developer/${nextRoute}`;
    if (typeof window !== "undefined" && window.location.hash !== nextHash) {
      window.location.hash = nextHash;
    }
  };

  useEffect(() => {
    if (
      bootstrap.status !== "loading"
      && !isViewAllowed(view, bootstrap.features, ownerPolicy, devApiProbe.status)
    ) {
      navigate("settings");
    }
  }, [bootstrap.features, bootstrap.status, devApiProbe.status, ownerPolicy, view]);

  const activeView = isViewAllowed(
    view,
    bootstrap.features,
    ownerPolicy,
    devApiProbe.status,
  )
    ? view
    : "settings";

  return (
    <div className="app-root">
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
            onOpenDeveloperTools={() => navigateDeveloper()}
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
          onNavigate={navigateDeveloper}
          route={developerRoute}
        />
      ) : activeView === "accounts" ? (
        <IdentityRequiredScreen onOpenSettings={() => navigate("settings")}>
          <Accounts onBack={() => navigate("settings")} />
        </IdentityRequiredScreen>
      ) : activeView === "memory" ? (
        <IdentityRequiredScreen onOpenSettings={() => navigate("settings")}>
          <Memory onBack={() => navigate("settings")} />
        </IdentityRequiredScreen>
      ) : activeView === "actions" ? (
        <IdentityRequiredScreen onOpenSettings={() => navigate("settings")}>
          <FoundationActions onBack={() => navigate("settings")} />
        </IdentityRequiredScreen>
      ) : activeView === "settings" ? (
        <Settings
          developerToolsAvailable={devApiProbe.status === "available"}
          onBack={() => navigate("chat")}
          onOpenDeveloperTools={() => navigateDeveloper()}
          onOpenOwnerSkills={() => navigate("owner-skills")}
          onOpenAccounts={() => navigate("accounts")}
          onOpenMemory={() => navigate("memory")}
          onOpenActions={() => navigate("actions")}
          ownerPolicy={ownerPolicy}
        />
      ) : (
        <IdentityRequiredScreen onOpenSettings={() => navigate("settings")}>
          <Chat onOpenSettings={() => navigate("settings")} />
        </IdentityRequiredScreen>
      )}
    </div>
  );
}

function isViewAllowed(
  view: AppView,
  features: DesktopHostFeatures,
  ownerPolicy: OwnerPolicy | null,
  devApiStatus: DevApiProbe["status"] = "unavailable",
): boolean {
  if (view === "accounts") return features.accounts;
  if (view === "memory") return features.memory;
  if (view === "actions") return features.actions;
  if (view === "developer") return devApiStatus !== "unavailable";
  if (view === "owner-skills") {
    return features.skillManagement && canInspectOwnerSkills(ownerPolicy);
  }
  return true;
}
