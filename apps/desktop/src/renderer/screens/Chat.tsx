import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { Menu, Settings } from "lucide-react";

import {
  createServerSession,
  deleteServerSession,
  listServerSessions,
  loadServerSession,
  postSessionMessage,
  updateServerSession,
  type ServerMessage,
  type ServerSession,
} from "../api";
import { buildAssistantTurnMessages } from "../chatEventMessages";
import { AppIconButton } from "../components/AppIconButton";
import { Composer } from "../components/Composer";
import { ConversationDrawer } from "../components/ConversationDrawer";
import { MessageList } from "../components/MessageList";
import { starterMessages } from "../data/fixtures";
import { useI18n } from "../i18n/I18nProvider";
import { loadSavedModelSettings } from "../modelSettings";
import { ChatMessage } from "../types";

type ChatProps = {
  onOpenSettings?: () => void;
};

function createMessageId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `message-${Math.random().toString(36).slice(2)}`;
}

export function Chat({ onOpenSettings = () => undefined }: ChatProps): JSX.Element {
  const { t } = useI18n();
  const [draft, setDraft] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>(starterMessages);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [sessions, setSessions] = useState<ServerSession[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [apiError, setApiError] = useState<string | null>(null);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [isHistoryLoading, setIsHistoryLoading] = useState(false);
  const [isSending, setIsSending] = useState(false);
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const historyLoadedRef = useRef(false);
  const requestGenerationRef = useRef(0);

  const localizedStarter = useCallback(() => (
    starterMessages.map((message) => ({ ...message, body: t("chat.starter") }))
  ), [t]);

  const loadConversation = useCallback(async (
    session: ServerSession,
    closeDrawer = true,
  ) => {
    const requestGeneration = requestGenerationRef.current + 1;
    requestGenerationRef.current = requestGeneration;
    setIsHistoryLoading(true);
    setHistoryError(null);
    try {
      const detail = await loadServerSession(session.id);
      if (requestGenerationRef.current !== requestGeneration) return;
      setSessionId(detail.session.id);
      setMessages(messagesFromHistory(detail.messages, localizedStarter()));
      setSessions((current) => upsertSession(current, detail.session));
      if (closeDrawer) setIsDrawerOpen(false);
    } catch {
      if (requestGenerationRef.current === requestGeneration) {
        setHistoryError(t("conversation.loadError"));
      }
    } finally {
      if (requestGenerationRef.current === requestGeneration) setIsHistoryLoading(false);
    }
  }, [localizedStarter, t]);

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
      if (restore && page.items[0]) await loadConversation(page.items[0], false);
    } catch {
      setHistoryError(t("conversation.listError"));
    } finally {
      setIsHistoryLoading(false);
    }
  }, [loadConversation, t]);

  useEffect(() => {
    setMessages((current) => current.map((message) => (
      message.id === "starter-assistant" ? { ...message, body: t("chat.starter") } : message
    )));
  }, [t]);

  useEffect(() => {
    if (!window.agentWeave?.server || historyLoadedRef.current) return;
    void refreshSessions(undefined, true);
  }, [refreshSessions]);

  const handleNewChat = () => {
    requestGenerationRef.current += 1;
    setMessages(localizedStarter());
    setSessionId(null);
    setApiError(null);
    setHistoryError(null);
    setIsSending(false);
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
    setApiError(null);
    setMessages((current) => [
      ...current,
      { body: text, id: createMessageId(), role: "user" },
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
      let activeSessionId = sessionId;
      if (!activeSessionId) {
        const session = await createServerSession(titleFromMessage(text));
        if (!isCurrentRequest()) return;
        activeSessionId = session.id;
        setSessionId(session.id);
        if (session.updated_at) setSessions((current) => upsertSession(current, session));
      }

      const response = await postSessionMessage(
        activeSessionId,
        text,
        await loadSavedModelSettings(),
      );
      if (!isCurrentRequest()) return;
      const assistantMessages = buildAssistantTurnMessages(response, createMessageId);
      setMessages((current) => [
        ...current.filter((message) => message.id !== pendingReasoningId),
        ...assistantMessages,
      ]);
      if (window.agentWeave?.server) void refreshSessions();
    } catch {
      if (isCurrentRequest()) {
        setMessages((current) => current.filter((message) => message.id !== pendingReasoningId));
        setApiError(t("chat.sendError"));
      }
    } finally {
      if (isCurrentRequest()) setIsSending(false);
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
      <MessageList messages={messages} />
      <Composer
        draft={draft}
        error={apiError}
        isSending={isSending}
        onChange={setDraft}
        onSubmit={handleSubmit}
      />
    </main>
  );
}

function messagesFromHistory(
  messages: ServerMessage[],
  fallback: ChatMessage[],
): ChatMessage[] {
  const history = messages
    .filter((message) => message.role === "user" || message.role === "assistant")
    .map((message): ChatMessage => ({
      body: message.content,
      id: message.id,
      role: message.role as "assistant" | "user",
    }));
  return history.length > 0 ? history : fallback;
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
