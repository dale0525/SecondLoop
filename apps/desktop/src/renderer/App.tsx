import { useEffect, useState } from "react";

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
import { DeveloperTools } from "./screens/DeveloperTools";
import { OwnerSkills } from "./screens/OwnerSkills";
import { Settings } from "./screens/Settings";
import { Accounts } from "./screens/Accounts";
import { Memory } from "./screens/Memory";
import { FoundationActions } from "./screens/FoundationActions";

type AppView = "chat" | "settings" | "developer" | "owner-skills" | "accounts" | "memory" | "actions";

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
  const bootstrap = useHostBootstrap();
  const { t } = useI18n();

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
    const nextHash = nextView === "chat" ? "" : `#${nextView}`;
    if (typeof window !== "undefined" && window.location.hash !== nextHash) {
      window.location.hash = nextHash;
    }
  };

  useEffect(() => {
    if (
      bootstrap.status !== "loading"
      && !isViewAllowed(view, bootstrap.features, ownerPolicy)
    ) {
      navigate("settings");
    }
  }, [bootstrap.features, bootstrap.status, ownerPolicy, view]);

  const activeView = isViewAllowed(view, bootstrap.features, ownerPolicy)
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
        <DeveloperTools onBack={() => navigate("settings")} />
      ) : activeView === "accounts" ? (
        <Accounts onBack={() => navigate("settings")} />
      ) : activeView === "memory" ? (
        <Memory onBack={() => navigate("settings")} />
      ) : activeView === "actions" ? (
        <FoundationActions onBack={() => navigate("settings")} />
      ) : activeView === "settings" ? (
        <Settings
          onBack={() => navigate("chat")}
          onOpenDeveloperTools={() => navigate("developer")}
          onOpenOwnerSkills={() => navigate("owner-skills")}
          onOpenAccounts={() => navigate("accounts")}
          onOpenMemory={() => navigate("memory")}
          onOpenActions={() => navigate("actions")}
          ownerPolicy={ownerPolicy}
        />
      ) : (
        <Chat onOpenSettings={() => navigate("settings")} />
      )}
    </div>
  );
}

function isViewAllowed(
  view: AppView,
  features: DesktopHostFeatures,
  ownerPolicy: OwnerPolicy | null,
): boolean {
  if (view === "accounts") return features.accounts;
  if (view === "memory") return features.memory;
  if (view === "actions") return features.actions;
  if (view === "developer") return features.skillManagement;
  if (view === "owner-skills") {
    return features.skillManagement && canInspectOwnerSkills(ownerPolicy);
  }
  return true;
}
