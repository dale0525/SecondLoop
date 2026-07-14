import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

import {
  parseHostDiscovery,
  type AgentAppHostDiscovery,
} from "../shared/hostBootstrap";
import {
  CLOSED_DESKTOP_HOST_FEATURES,
  resolveDesktopHostFeatures,
  type DesktopHostFeatures,
} from "./hostFeatures";

type HostBootstrapStatus = "loading" | "ready" | "unavailable";

type HostBootstrapContextValue = Readonly<{
  discovery: AgentAppHostDiscovery | null;
  features: DesktopHostFeatures;
  reload: () => void;
  status: HostBootstrapStatus;
}>;

const HostBootstrapContext = createContext<HostBootstrapContextValue>({
  discovery: null,
  features: CLOSED_DESKTOP_HOST_FEATURES,
  reload: () => undefined,
  status: "unavailable",
});

export function HostBootstrapProvider({ children }: { children: ReactNode }): JSX.Element {
  const [attempt, setAttempt] = useState(0);
  const [discovery, setDiscovery] = useState<AgentAppHostDiscovery | null>(null);
  const [status, setStatus] = useState<HostBootstrapStatus>("loading");
  const reload = useCallback(() => {
    setDiscovery(null);
    setStatus("loading");
    const sidecar = window.agentWeave?.sidecar;
    if (!sidecar) {
      setAttempt((current) => current + 1);
      return;
    }
    void Promise.resolve()
      .then(() => sidecar.ensureRunning())
      .then(() => setAttempt((current) => current + 1))
      .catch(() => setStatus("unavailable"));
  }, []);

  useEffect(() => {
    let active = true;
    setDiscovery(null);
    setStatus("loading");
    const bridge = window.agentWeave?.hostBootstrap;
    if (!bridge) {
      setStatus("unavailable");
      return () => {
        active = false;
      };
    }
    Promise.resolve()
      .then(() => bridge.load())
      .then((value) => {
        if (!active) return;
        setDiscovery(parseHostDiscovery(value));
        setStatus("ready");
      })
      .catch(() => {
        if (!active) return;
        setDiscovery(null);
        setStatus("unavailable");
      });
    return () => {
      active = false;
    };
  }, [attempt]);

  const value = useMemo<HostBootstrapContextValue>(() => {
    const trustedDiscovery = status === "ready" ? discovery : null;
    return {
      discovery: trustedDiscovery,
      features: resolveDesktopHostFeatures(trustedDiscovery),
      reload,
      status,
    };
  }, [discovery, reload, status]);

  return (
    <HostBootstrapContext.Provider value={value}>
      {children}
    </HostBootstrapContext.Provider>
  );
}

export function useHostBootstrap(): HostBootstrapContextValue {
  return useContext(HostBootstrapContext);
}
