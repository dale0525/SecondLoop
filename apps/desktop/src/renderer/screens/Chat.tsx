import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { Menu, Settings } from "lucide-react";

import {
  acceptStructuredAction,
  cancelServerTurn,
  createServerSession,
  deleteServerSession,
  listServerSessionEvents,
  listServerSessions,
  listServerTurnEvents,
  loadServerSession,
  startSessionTurn,
  updateServerSession,
  type RuntimeEvent,
  type ServerConversationEvent,
  type ServerSession,
  type ServerSessionDetail,
  type ServerTurn,
} from "../api";
import { buildAssistantTurnMessages } from "../chatEventMessages";
import { AppIconButton } from "../components/AppIconButton";
import { Composer } from "../components/Composer";
import { ConversationDrawer } from "../components/ConversationDrawer";
import { MessageList } from "../components/MessageList";
import { starterMessages } from "../data/fixtures";
import { useI18n } from "../i18n/I18nProvider";
import { loadSavedModelSettings } from "../modelSettings";
import {
  createStructuredContentState,
  mergeStructuredContentMessages,
  reduceStructuredContentEvents,
  type StructuredContentState,
} from "../structuredContentReducer";
import type {
  ChatMessage,
  StructuredContentActionHandler,
} from "../types";

type ChatProps = {
  onOpenSettings?: () => void;
  onStructuredContentAction?: StructuredContentActionHandler;
};

function createMessageId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `message-${Math.random().toString(36).slice(2)}`;
}

export function Chat({
  onOpenSettings = () => undefined,
  onStructuredContentAction,
}: ChatProps): JSX.Element {
  const { t } = useI18n();
  const shouldRestoreOnMount = useRef(canRestoreConversationOnMount()).current;
  const [draft, setDraft] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>(
    shouldRestoreOnMount ? [] : starterMessages,
  );
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [sessions, setSessions] = useState<ServerSession[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [apiError, setApiError] = useState<string | null>(null);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [isHistoryLoading, setIsHistoryLoading] = useState(shouldRestoreOnMount);
  const [isRestoringHistory, setIsRestoringHistory] = useState(shouldRestoreOnMount);
  const [isSending, setIsSending] = useState(false);
  const [isStopping, setIsStopping] = useState(false);
  const [isReconnecting, setIsReconnecting] = useState(false);
  const [turnNotice, setTurnNotice] = useState<string | null>(null);
  const [activeTurn, setActiveTurn] = useState<{ sessionId: string; turnId: string } | null>(null);
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const historyLoadedRef = useRef(false);
  const requestGenerationRef = useRef(0);
  const sessionEventCursorRef = useRef(-1);
  const structuredContentStateRef = useRef(createStructuredContentState());

  const localizedStarter = useCallback(() => (
    starterMessages.map((message) => ({ ...message, body: t("chat.starter") }))
  ), [t]);

  useEffect(() => {
    if (!sessionId || isSending || !window.agentWeave?.server) return;
    let active = true;
    const activeSessionId = sessionId;
    const consume = async () => {
      while (active) {
        try {
          const page = await listServerSessionEvents(
            activeSessionId,
            sessionEventCursorRef.current,
          );
          if (!active) return;
          setIsReconnecting(false);
          sessionEventCursorRef.current = page.nextCursor;
          if (page.events.length === 0) continue;
          structuredContentStateRef.current = reduceStructuredContentEvents(
            structuredContentStateRef.current,
            page.events.map((event) => event.payload),
          );
          const state = structuredContentStateRef.current;
          setMessages((current) => mergeStructuredContentMessages(current, state));
        } catch {
          if (!active) return;
          const recovered = await recoverManagedSidecar(() => active, setIsReconnecting);
          if (!recovered) {
            setIsReconnecting(false);
            await new Promise((resolve) => window.setTimeout(resolve, 500));
          }
        }
      }
    };
    void consume();
    return () => {
      active = false;
    };
  }, [isSending, sessionId]);

  const handleStructuredContentAction = useCallback<StructuredContentActionHandler>(async (request) => {
    setApiError(null);
    try {
      if (onStructuredContentAction) {
        await onStructuredContentAction(request);
        return;
      }
      if (!sessionId) throw new Error("Structured action has no active session");
      await acceptStructuredAction(sessionId, request.bindingId);
      const detail = await loadServerSession(sessionId);
      const history = messagesFromHistory(detail, localizedStarter(), t("chat.working"));
      structuredContentStateRef.current = history.structuredContentState;
      setMessages(history.messages);
      setSessions((current) => upsertSession(current, detail.session));
    } catch (error) {
      setApiError(t("chat.structuredActionFailed"));
      throw error;
    }
  }, [localizedStarter, onStructuredContentAction, sessionId, t]);

  const applyTurnFeedback = useCallback((turn: ServerTurn) => {
    setApiError(null);
    setTurnNotice(null);
    if (turn.status === "cancelled") setTurnNotice(t("chat.cancelled"));
    if (turn.status === "failed") setApiError(t("chat.turnFailed"));
    if (turn.status === "interrupted") setApiError(t("chat.interrupted"));
  }, [t]);

  const consumeTurn = useCallback(async (
    activeSessionId: string,
    turnId: string,
    requestGeneration: number,
    initialEvents: ServerConversationEvent[] = [],
    initialCursor = -1,
  ) => {
    let cursor = initialCursor;
    let events = [...initialEvents];
    const isCurrentRequest = () => requestGenerationRef.current === requestGeneration;
    setActiveTurn({ sessionId: activeSessionId, turnId });
    setIsSending(true);
    setIsStopping(false);
    setTurnNotice(null);
    try {
      while (isCurrentRequest()) {
        let page;
        try {
          page = await listServerTurnEvents(activeSessionId, turnId, cursor);
          if (isCurrentRequest()) setIsReconnecting(false);
        } catch (error) {
          if (!await recoverManagedSidecar(() => isCurrentRequest(), setIsReconnecting)) {
            throw error;
          }
          continue;
        }
        if (!isCurrentRequest()) return;
        events = appendUniqueEvents(events, page.events);
        cursor = page.nextCursor;
        structuredContentStateRef.current = reduceStructuredContentEvents(
          structuredContentStateRef.current,
          events.map((event) => event.payload),
        );
        const structuredContentState = structuredContentStateRef.current;
        setMessages((current) => mergeStructuredContentMessages(
          replaceTurnMessages(
            current,
            turnId,
            messagesFromTurn(events.map((event) => event.payload), page.turn, t("chat.working")),
          ),
          structuredContentState,
        ));
        if (!page.turn.status || page.turn.status === "running") continue;
        applyTurnFeedback(page.turn);
        if (window.agentWeave?.server) {
          try {
            const detail = await loadServerSession(activeSessionId);
            if (!isCurrentRequest()) return;
            const history = messagesFromHistory(detail, localizedStarter(), t("chat.working"));
            structuredContentStateRef.current = history.structuredContentState;
            setMessages(history.messages);
            setSessions((current) => upsertSession(current, detail.session));
          } catch {
            // Cursor replay already rendered the authoritative terminal event.
          }
        }
        return;
      }
    } catch {
      if (isCurrentRequest()) setApiError(t("chat.sendError"));
    } finally {
      if (isCurrentRequest()) {
        setActiveTurn(null);
        setIsReconnecting(false);
        setIsSending(false);
        setIsStopping(false);
      }
    }
  }, [applyTurnFeedback, localizedStarter, t]);

  const loadConversation = useCallback(async (
    session: ServerSession,
    closeDrawer = true,
  ): Promise<boolean> => {
    const requestGeneration = requestGenerationRef.current + 1;
    requestGenerationRef.current = requestGeneration;
    setIsHistoryLoading(true);
    setHistoryError(null);
    try {
      const detail = await loadServerSession(session.id);
      if (requestGenerationRef.current !== requestGeneration) return false;
      sessionEventCursorRef.current = detail.events.at(-1)?.event_index ?? -1;
      setSessionId(detail.session.id);
      const history = messagesFromHistory(detail, localizedStarter(), t("chat.working"));
      structuredContentStateRef.current = history.structuredContentState;
      setMessages(history.messages);
      setSessions((current) => upsertSession(current, detail.session));
      const latestTurn = detail.turns?.at(-1);
      if (latestTurn) applyTurnFeedback(latestTurn);
      if (latestTurn?.status === "running") {
        const turnEvents = detail.events.filter((event) => event.turn_id === latestTurn.id);
        const cursor = turnEvents.at(-1)?.event_index ?? -1;
        void consumeTurn(detail.session.id, latestTurn.id, requestGeneration, turnEvents, cursor);
      } else {
        setActiveTurn(null);
        setIsSending(false);
      }
      if (closeDrawer) setIsDrawerOpen(false);
      return true;
    } catch {
      if (requestGenerationRef.current === requestGeneration) {
        setHistoryError(t("conversation.loadError"));
      }
      return false;
    } finally {
      if (requestGenerationRef.current === requestGeneration) setIsHistoryLoading(false);
    }
  }, [applyTurnFeedback, consumeTurn, localizedStarter, t]);

  const refreshSessions = useCallback(async (cursor?: string, restore = false) => {
    setIsHistoryLoading(true);
    setHistoryError(null);
    try {
      const page = await listServerSessions(cursor, 50);
      historyLoadedRef.current = true;
      setSessions((current) => cursor
        ? deduplicateSessions([...current, ...page.items])
        : page.items);
      setNextCursor(page.nextCursor);
      if (restore) {
        const restored = page.items[0]
          ? await loadConversation(page.items[0], false)
          : false;
        if (!restored) {
          structuredContentStateRef.current = createStructuredContentState();
          setMessages(localizedStarter());
        }
      }
    } catch {
      if (restore) setMessages(localizedStarter());
      setHistoryError(t("conversation.listError"));
    } finally {
      setIsHistoryLoading(false);
    }
  }, [loadConversation, localizedStarter, t]);

  useEffect(() => {
    setMessages((current) => current.map((message) => (
      message.id === "starter-assistant" ? { ...message, body: t("chat.starter") } : message
    )));
  }, [t]);

  useEffect(() => {
    if (!shouldRestoreOnMount || historyLoadedRef.current) return;
    void refreshSessions(undefined, true).finally(() => setIsRestoringHistory(false));
  }, [refreshSessions, shouldRestoreOnMount]);

  const handleNewChat = () => {
    if (activeTurn) {
      void cancelServerTurn(activeTurn.sessionId, activeTurn.turnId).catch(() => undefined);
    }
    requestGenerationRef.current += 1;
    sessionEventCursorRef.current = -1;
    structuredContentStateRef.current = createStructuredContentState();
    setMessages(localizedStarter());
    setSessionId(null);
    setApiError(null);
    setHistoryError(null);
    setIsSending(false);
    setIsStopping(false);
    setIsReconnecting(false);
    setTurnNotice(null);
    setActiveTurn(null);
    setIsDrawerOpen(false);
  };

  const handleDrawerOpen = (open: boolean) => {
    setIsDrawerOpen(open);
    if (open && !historyLoadedRef.current) void refreshSessions();
  };

  const handleRename = async (session: ServerSession, title: string) => {
    try {
      const updated = await updateServerSession(session, title);
      setSessions((current) => upsertSession(current, updated));
      setHistoryError(null);
    } catch (error) {
      await refreshSessions();
      setHistoryError(t("conversation.conflictError"));
      throw error;
    }
  };

  const handleDelete = async (session: ServerSession) => {
    try {
      await deleteServerSession(session);
      const remaining = sessions.filter((candidate) => candidate.id !== session.id);
      setSessions(remaining);
      setHistoryError(null);
      if (session.id === sessionId) {
        if (remaining[0]) await loadConversation(remaining[0], false);
        else handleNewChat();
      }
    } catch (error) {
      await refreshSessions();
      setHistoryError(t("conversation.conflictError"));
      throw error;
    }
  };

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const text = draft.trim();
    if (!text || isSending) return;

    const pendingReasoningId = createMessageId();
    const localUserMessageId = createMessageId();
    setApiError(null);
    setTurnNotice(null);
    setMessages((current) => [
      ...current,
      { body: text, id: localUserMessageId, role: "user" },
      {
        id: pendingReasoningId,
        kind: "reasoning",
        role: "assistant",
        status: "running",
        text: t("chat.working"),
      },
    ]);
    setDraft("");

    const requestGeneration = requestGenerationRef.current + 1;
    requestGenerationRef.current = requestGeneration;
    const isCurrentRequest = () => requestGenerationRef.current === requestGeneration;

    try {
      setIsSending(true);
      setIsStopping(false);
      let activeSessionId = sessionId;
      if (!activeSessionId) {
        const session = await createServerSession(titleFromMessage(text));
        if (!isCurrentRequest()) return;
        activeSessionId = session.id;
        sessionEventCursorRef.current = -1;
        setSessionId(session.id);
        if (session.updated_at) setSessions((current) => upsertSession(current, session));
      }

      const requestId = createMessageId();
      const settings = await loadSavedModelSettings();
      let response;
      try {
        response = await startSessionTurn(activeSessionId, requestId, text, settings);
      } catch (error) {
        if (!await recoverManagedSidecar(isCurrentRequest, setIsReconnecting)) throw error;
        response = await startSessionTurn(activeSessionId, requestId, text, settings);
      }
      if (!isCurrentRequest()) return;
      setMessages((current) => current.map((message) => {
        if (message.id === localUserMessageId) {
          return { ...message, id: response.userMessage.id };
        }
        if (message.id === pendingReasoningId) {
          return { ...message, id: `turn:${response.turn.id}:working` };
        }
        return message;
      }));
      await consumeTurn(activeSessionId, response.turn.id, requestGeneration);
    } catch {
      if (isCurrentRequest()) {
        setMessages((current) => current.filter((message) => message.id !== pendingReasoningId));
        setApiError(t("chat.sendError"));
        setActiveTurn(null);
        setIsReconnecting(false);
        setIsSending(false);
        setIsStopping(false);
      }
    }
  };

  const handleStop = async () => {
    if (!activeTurn || isStopping) return;
    setIsStopping(true);
    setTurnNotice(t("chat.stopping"));
    try {
      await cancelServerTurn(activeTurn.sessionId, activeTurn.turnId);
    } catch {
      setApiError(t("chat.sendError"));
      setIsStopping(false);
    }
  };

  return (
    <main className="chat-shell" aria-label={t("chat.ariaLabel")}>
      <ConversationDrawer
        activeSessionId={sessionId}
        error={historyError}
        hasMore={Boolean(nextCursor)}
        isLoading={isHistoryLoading}
        isOpen={isDrawerOpen}
        onDelete={handleDelete}
        onLoadMore={() => refreshSessions(nextCursor ?? undefined)}
        onNewChat={handleNewChat}
        onOpenChange={handleDrawerOpen}
        onRename={handleRename}
        onRetry={() => refreshSessions()}
        onSelect={loadConversation}
        sessions={sessions}
      />
      <header className="top-bar chat-top-bar">
        <AppIconButton label={t("chat.openConversations")} onClick={() => handleDrawerOpen(true)}>
          <Menu size={18} aria-hidden="true" />
        </AppIconButton>
        <div className="top-bar-title">
          <h1>{t("app.name")}</h1>
          <p>{t("app.tagline")}</p>
        </div>
        <AppIconButton label={t("chat.openSettings")} onClick={onOpenSettings}>
          <Settings size={18} aria-hidden="true" />
        </AppIconButton>
      </header>
      {isRestoringHistory ? (
        <section className="message-list chat-history-loading" aria-label="Conversation">
          <div className="chat-history-loading-status" role="status">
            <span aria-hidden="true" className="chat-history-loading-dot" />
            {t("conversation.loading")}
          </div>
        </section>
      ) : (
        <MessageList
          messages={messages}
          onStructuredContentAction={handleStructuredContentAction}
        />
      )}
      <Composer
        draft={draft}
        error={apiError}
        isSending={isSending}
        isStopping={isStopping}
        onChange={setDraft}
        onStop={() => void handleStop()}
        onSubmit={handleSubmit}
        status={isReconnecting ? t("chat.reconnecting") : turnNotice}
      />
    </main>
  );
}

function canRestoreConversationOnMount(): boolean {
  return Boolean(window.agentWeave?.server) || import.meta.env.MODE === "development";
}

function messagesFromHistory(
  detail: ServerSessionDetail,
  fallback: ChatMessage[],
  workingLabel: string,
): { messages: ChatMessage[]; structuredContentState: StructuredContentState } {
  const turnsByUserMessage = new Map(
    (detail.turns ?? []).map((turn) => [turn.user_message_id, turn]),
  );
  const history: ChatMessage[] = [];
  for (const message of detail.messages) {
    if (message.role !== "user" && message.role !== "assistant") continue;
    history.push({
      body: message.content,
      id: message.id,
      role: message.role as "assistant" | "user",
    });
    const turn = turnsByUserMessage.get(message.id);
    if (!turn) continue;
    const events = detail.events
      .filter((event) => event.turn_id === turn.id)
      .map((event) => event.payload);
    const turnMessages = messagesFromTurn(events, turn, workingLabel);
    history.push(...(turn.assistant_message_id
      ? turnMessages.filter(isActivityMessage)
      : turnMessages));
  }
  const structuredContentState = reduceStructuredContentEvents(
    createStructuredContentState(),
    [...detail.events]
      .sort((left, right) => left.event_index - right.event_index)
      .map((event) => event.payload),
  );
  return {
    messages: mergeStructuredContentMessages(
      history.length > 0 ? history : fallback,
      structuredContentState,
    ),
    structuredContentState,
  };
}

function messagesFromTurn(
  events: RuntimeEvent[],
  turn: ServerTurn,
  workingLabel: string,
): ChatMessage[] {
  let index = 0;
  const messages = buildAssistantTurnMessages(
    { accepted: true, events },
    () => `turn:${turn.id}:${index++}`,
  );
  if (turn.status === "running" && messages.length === 0) {
    return [{
      id: `turn:${turn.id}:working`,
      kind: "reasoning",
      role: "assistant",
      status: "running",
      text: workingLabel,
    }];
  }
  return messages;
}

function replaceTurnMessages(
  current: ChatMessage[],
  turnId: string,
  replacement: ChatMessage[],
): ChatMessage[] {
  const prefix = `turn:${turnId}:`;
  return [...current.filter((message) => !message.id.startsWith(prefix)), ...replacement];
}

function appendUniqueEvents(
  current: ServerConversationEvent[],
  next: ServerConversationEvent[],
): ServerConversationEvent[] {
  const unique = new Map(current.map((event) => [event.id, event]));
  for (const event of next) unique.set(event.id, event);
  return [...unique.values()].sort((left, right) => left.event_index - right.event_index);
}

function isActivityMessage(message: ChatMessage): boolean {
  return "kind" in message && new Set(["reasoning", "tool_call", "tool_result"]).has(
    message.kind ?? "",
  );
}

async function recoverManagedSidecar(
  isCurrent: () => boolean,
  setReconnecting: (value: boolean) => void,
): Promise<boolean> {
  const sidecar = window.agentWeave?.sidecar;
  if (!sidecar || !isCurrent()) return false;
  setReconnecting(true);
  for (let attempt = 0; attempt < 3 && isCurrent(); attempt += 1) {
    try {
      const status = await sidecar.ensureRunning();
      if (status.state === "ready") return true;
    } catch {
      // The supervisor exposes the authoritative state on the next bounded retry.
    }
    await new Promise((resolve) => window.setTimeout(resolve, 150 * (attempt + 1)));
  }
  return false;
}

function titleFromMessage(value: string): string {
  const firstLine = value.split(/\r?\n/, 1)[0].trim();
  return Array.from(firstLine).slice(0, 60).join("") || "New conversation";
}

function upsertSession(sessions: ServerSession[], updated: ServerSession): ServerSession[] {
  return deduplicateSessions([updated, ...sessions.filter((session) => session.id !== updated.id)]);
}

function deduplicateSessions(sessions: ServerSession[]): ServerSession[] {
  const unique = new Map(sessions.map((session) => [session.id, session]));
  return [...unique.values()].sort((left, right) => (
    new Date(right.updated_at).getTime() - new Date(left.updated_at).getTime()
  ));
}
