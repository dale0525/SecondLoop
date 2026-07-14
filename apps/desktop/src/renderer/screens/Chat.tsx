import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { CircleAlert, Menu, Settings } from "lucide-react";

import {
  cancelServerTurn,
  createServerSession,
  deleteAttachment,
  deleteServerSession,
  listServerSessions,
  listServerTurnEvents,
  loadServerSession,
  pickAndImportAttachment,
  startSessionTurn,
  updateServerSession,
  type AttachmentMetadata,
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
import { loadModelSettings, loadSavedModelSettings } from "../modelSettings";
import { ChatMessage } from "../types";

type ChatProps = {
  attachmentsEnabled?: boolean;
  onOpenConnections?: () => void;
  onOpenSettings?: () => void;
  productMode?: boolean;
};

function createMessageId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `message-${Math.random().toString(36).slice(2)}`;
}

export function Chat({
  attachmentsEnabled = false,
  onOpenConnections = () => undefined,
  onOpenSettings = () => undefined,
  productMode = false,
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
  const [attachments, setAttachments] = useState<AttachmentMetadata[]>([]);
  const [attachmentError, setAttachmentError] = useState<string | null>(null);
  const [isImportingAttachment, setIsImportingAttachment] = useState(false);
  const [removingAttachmentIds, setRemovingAttachmentIds] = useState<string[]>([]);
  const [modelConfigured, setModelConfigured] = useState<boolean | null>(null);
  const [activeTurn, setActiveTurn] = useState<{ sessionId: string; turnId: string } | null>(null);
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const historyLoadedRef = useRef(false);
  const requestGenerationRef = useRef(0);

  useEffect(() => {
    if (!productMode) return;
    let active = true;
    void loadModelSettings()
      .then((snapshot) => {
        if (active) setModelConfigured(snapshot.saved || snapshot.apiKeyConfigured);
      })
      .catch(() => {
        if (active) setModelConfigured(null);
      });
    return () => {
      active = false;
    };
  }, [productMode]);

  const localizedStarter = useCallback(() => (
    starterMessages.map((message) => ({ ...message, body: t("chat.starter") }))
  ), [t]);

  const applyTurnFeedback = useCallback((turn: ServerTurn) => {
    setApiError(null);
    setTurnNotice(null);
    setAttachments([]);
    setAttachmentError(null);
    setRemovingAttachmentIds([]);
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
        setMessages((current) => replaceTurnMessages(
          current,
          turnId,
          messagesFromTurn(events.map((event) => event.payload), page.turn, t("chat.working")),
        ));
        if (!page.turn.status || page.turn.status === "running") continue;
        applyTurnFeedback(page.turn);
        if (window.agentWeave?.server) {
          try {
            const detail = await loadServerSession(activeSessionId);
            if (!isCurrentRequest()) return;
            setMessages(messagesFromHistory(detail, localizedStarter(), t("chat.working")));
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
      setSessionId(detail.session.id);
      setMessages(messagesFromHistory(detail, localizedStarter(), t("chat.working")));
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
        if (!restored) setMessages(localizedStarter());
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
    setMessages(localizedStarter());
    setSessionId(null);
    setApiError(null);
    setHistoryError(null);
    setIsSending(false);
    setIsStopping(false);
    setIsReconnecting(false);
    setTurnNotice(null);
    setAttachments([]);
    setAttachmentError(null);
    setRemovingAttachmentIds([]);
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
    const submittedAttachments = [...attachments];
    const text = draft.trim() || (submittedAttachments.length > 0
      ? t("composer.attachmentOnlyPrompt")
      : "");
    if (!text || isSending) return;
    const turnContent = contentWithAttachmentReferences(text, submittedAttachments);

    const pendingReasoningId = createMessageId();
    const localUserMessageId = createMessageId();
    setApiError(null);
    setTurnNotice(null);
    setMessages((current) => [
      ...current,
      {
        attachments: submittedAttachments.map(toMessageAttachment),
        body: text,
        id: localUserMessageId,
        role: "user",
      },
      {
        id: pendingReasoningId,
        kind: "reasoning",
        role: "assistant",
        status: "running",
        text: t("chat.working"),
      },
    ]);
    setDraft("");
    setAttachments([]);
    setAttachmentError(null);

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
        setSessionId(session.id);
        if (session.updated_at) setSessions((current) => upsertSession(current, session));
      }

      const requestId = createMessageId();
      const settings = await loadSavedModelSettings();
      let response;
      try {
        response = await startSessionTurn(activeSessionId, requestId, turnContent, settings);
      } catch (error) {
        if (!await recoverManagedSidecar(isCurrentRequest, setIsReconnecting)) throw error;
        response = await startSessionTurn(activeSessionId, requestId, turnContent, settings);
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
        setAttachments((current) => deduplicateAttachments([
          ...submittedAttachments,
          ...current,
        ]));
      }
    }
  };

  const handleAddAttachment = async () => {
    if (isImportingAttachment) return;
    setIsImportingAttachment(true);
    setAttachmentError(null);
    try {
      const attachment = await pickAndImportAttachment();
      if (attachment) {
        setAttachments((current) => deduplicateAttachments([...current, attachment]));
      }
    } catch {
      setAttachmentError(t("composer.attachmentImportFailed"));
    } finally {
      setIsImportingAttachment(false);
    }
  };

  const handleRemoveAttachment = async (id: string) => {
    if (removingAttachmentIds.includes(id)) return;
    setRemovingAttachmentIds((current) => [...current, id]);
    setAttachmentError(null);
    try {
      await deleteAttachment(id);
      setAttachments((current) => current.filter((attachment) => attachment.id !== id));
    } catch {
      setAttachmentError(t("composer.attachmentRemoveFailed"));
    } finally {
      setRemovingAttachmentIds((current) => current.filter((candidate) => candidate !== id));
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
      {productMode && modelConfigured === false ? (
        <div className="chat-onboarding" role="status">
          <CircleAlert aria-hidden="true" size={18} />
          <div>
            <strong>{t("chat.modelMissingTitle")}</strong>
            <span>{t("chat.modelMissingDescription")}</span>
          </div>
          <button onClick={onOpenConnections} type="button">
            {t("chat.configureModel")}
          </button>
        </div>
      ) : null}
      {isRestoringHistory ? (
        <section className="message-list chat-history-loading" aria-label="Conversation">
          <div className="chat-history-loading-status" role="status">
            <span aria-hidden="true" className="chat-history-loading-dot" />
            {t("conversation.loading")}
          </div>
        </section>
      ) : (
        <MessageList messages={messages} />
      )}
      <Composer
        attachments={attachments}
        draft={draft}
        error={attachmentError ?? apiError}
        isImportingAttachment={isImportingAttachment}
        isSending={isSending}
        isStopping={isStopping}
        onAddAttachment={attachmentsEnabled ? () => void handleAddAttachment() : undefined}
        onChange={setDraft}
        onRemoveAttachment={attachmentsEnabled ? (id) => void handleRemoveAttachment(id) : undefined}
        onStop={() => void handleStop()}
        onSubmit={handleSubmit}
        removingAttachmentIds={removingAttachmentIds}
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
): ChatMessage[] {
  const turnsByUserMessage = new Map(
    (detail.turns ?? []).map((turn) => [turn.user_message_id, turn]),
  );
  const history: ChatMessage[] = [];
  for (const message of detail.messages) {
    if (message.role !== "user" && message.role !== "assistant") continue;
    const parsed = message.role === "user"
      ? parseAttachmentReferences(message.content)
      : { attachments: [], content: message.content };
    history.push({
      attachments: parsed.attachments.map(toMessageAttachment),
      body: parsed.content,
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
  return history.length > 0 ? history : fallback;
}

const ATTACHMENT_REFERENCE_OPEN = "<secondloop_attachment_refs>";
const ATTACHMENT_REFERENCE_CLOSE = "</secondloop_attachment_refs>";

function contentWithAttachmentReferences(
  content: string,
  attachments: AttachmentMetadata[],
): string {
  if (attachments.length === 0) return content;
  const references = JSON.stringify({
    attachments: attachments.map((attachment) => ({
      fileName: attachment.fileName,
      id: attachment.id,
      mimeType: attachment.mimeType,
      sha256: attachment.sha256,
      sizeBytes: attachment.sizeBytes,
    })),
    version: 1,
  });
  return `${content}\n\n${ATTACHMENT_REFERENCE_OPEN}${references}${ATTACHMENT_REFERENCE_CLOSE}`;
}

function parseAttachmentReferences(content: string): {
  attachments: AttachmentMetadata[];
  content: string;
} {
  const marker = `\n\n${ATTACHMENT_REFERENCE_OPEN}`;
  const start = content.lastIndexOf(marker);
  if (start < 0 || !content.endsWith(ATTACHMENT_REFERENCE_CLOSE)) {
    return { attachments: [], content };
  }
  const encoded = content.slice(
    start + marker.length,
    -ATTACHMENT_REFERENCE_CLOSE.length,
  );
  try {
    const parsed = JSON.parse(encoded) as {
      attachments?: Array<Partial<AttachmentMetadata>>;
      version?: number;
    };
    if (parsed.version !== 1 || !Array.isArray(parsed.attachments)) {
      return { attachments: [], content };
    }
    const valid = parsed.attachments.filter(isAttachmentReference).map((attachment) => ({
      createdAt: "1970-01-01T00:00:00.000Z",
      fileName: attachment.fileName,
      id: attachment.id,
      mimeType: attachment.mimeType,
      sha256: attachment.sha256,
      sizeBytes: attachment.sizeBytes,
    }));
    if (valid.length !== parsed.attachments.length) return { attachments: [], content };
    return { attachments: valid, content: content.slice(0, start) };
  } catch {
    return { attachments: [], content };
  }
}

function isAttachmentReference(value: Partial<AttachmentMetadata>): value is AttachmentMetadata {
  return typeof value.id === "string"
    && typeof value.fileName === "string"
    && typeof value.mimeType === "string"
    && typeof value.sha256 === "string"
    && typeof value.sizeBytes === "number";
}

function toMessageAttachment(attachment: AttachmentMetadata) {
  return {
    id: attachment.id,
    kind: attachment.mimeType.startsWith("image/") ? "image" as const : "file" as const,
    mime: attachment.mimeType,
    name: attachment.fileName,
    size: attachment.sizeBytes,
  };
}

function deduplicateAttachments(attachments: AttachmentMetadata[]): AttachmentMetadata[] {
  return [...new Map(attachments.map((attachment) => [attachment.id, attachment])).values()];
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
