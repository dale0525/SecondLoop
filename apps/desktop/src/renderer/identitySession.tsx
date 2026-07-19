import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from "react";

import type {
  IdentityAccount,
  IdentityAuthorizationStart,
  IdentitySessionStatus,
} from "../shared/identity";
import { useHostBootstrap } from "./hostBootstrap";

export type IdentityUiState =
  | "not_required"
  | "loading"
  | "signed_out"
  | "waiting"
  | "signed_in"
  | "unavailable";

type IdentitySessionContextValue = Readonly<{
  account: IdentityAccount | null;
  expiresAt: string | null;
  logout(): Promise<void>;
  refresh(): Promise<void>;
  start(): Promise<void>;
  state: IdentityUiState;
}>;

const IdentitySessionContext = createContext<IdentitySessionContextValue | null>(null);

export function IdentitySessionProvider({ children }: PropsWithChildren): JSX.Element {
  const bootstrap = useHostBootstrap();
  const required = bootstrap.discovery?.access.identity.mode === "required";
  const [state, setState] = useState<IdentityUiState>(required ? "loading" : "not_required");
  const [account, setAccount] = useState<IdentityAccount | null>(null);
  const [expiresAt, setExpiresAt] = useState<string | null>(null);

  const applyStatus = useCallback((status: IdentitySessionStatus) => {
    setAccount(status.account);
    setState(status.state);
    if (status.account) setExpiresAt(status.account.expiresAt);
  }, []);

  const refresh = useCallback(async () => {
    if (!required) {
      setAccount(null);
      setExpiresAt(null);
      setState("not_required");
      return;
    }
    const identity = window.agentWeave?.identity;
    if (!identity) {
      setState("unavailable");
      return;
    }
    try {
      applyStatus(await identity.status());
    } catch {
      setState("unavailable");
    }
  }, [applyStatus, required]);

  useEffect(() => {
    if (bootstrap.status === "loading") {
      setState("loading");
      return;
    }
    void refresh();
  }, [bootstrap.status, refresh]);

  useEffect(() => {
    if (state !== "waiting") return;
    const poll = window.setInterval(() => {
      const identity = window.agentWeave?.identity;
      if (!identity) {
        window.clearInterval(poll);
        setState("unavailable");
        return;
      }
      void identity.status()
        .then((status) => {
          if (status.state === "signed_in" || status.state === "unavailable") {
            window.clearInterval(poll);
            applyStatus(status);
          } else if (expiresAt && Date.parse(expiresAt) <= Date.now()) {
            window.clearInterval(poll);
            setState("signed_out");
          }
        })
        .catch(() => {
          window.clearInterval(poll);
          setState("unavailable");
        });
    }, 1_500);
    return () => window.clearInterval(poll);
  }, [applyStatus, expiresAt, state]);

  const start = useCallback(async () => {
    const identity = window.agentWeave?.identity;
    if (!required || !identity) {
      setState(required ? "unavailable" : "not_required");
      return;
    }
    setState("loading");
    try {
      const started: IdentityAuthorizationStart = await identity.start();
      setExpiresAt(started.expiresAt);
      setState("waiting");
    } catch {
      setState("unavailable");
    }
  }, [required]);

  const logout = useCallback(async () => {
    const identity = window.agentWeave?.identity;
    if (!required || !identity) return;
    setState("loading");
    try {
      applyStatus(await identity.logout());
      setExpiresAt(null);
    } catch {
      setState("unavailable");
    }
  }, [applyStatus, required]);

  const value = useMemo<IdentitySessionContextValue>(() => ({
    account,
    expiresAt,
    logout,
    refresh,
    start,
    state,
  }), [account, expiresAt, logout, refresh, start, state]);

  return (
    <IdentitySessionContext.Provider value={value}>
      {children}
    </IdentitySessionContext.Provider>
  );
}

export function useIdentitySession(): IdentitySessionContextValue {
  const context = useContext(IdentitySessionContext);
  if (!context) throw new Error("Identity session is unavailable outside its provider");
  return context;
}
