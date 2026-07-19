import * as Dialog from "@radix-ui/react-dialog";
import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  KeyRound,
  LoaderCircle,
  Send,
  Sparkles,
  X,
} from "lucide-react";
import { FormEvent, useEffect, useMemo, useRef, useState } from "react";

import {
  cancelServerTurn,
  createDevSkill,
  createServerSession,
  deleteServerSession,
  listServerTurnEvents,
  loadServerSession,
  readDevSkill,
  reloadDevSkills,
  startSessionTurn,
  updateDevSkill,
  type DevSkillInventory,
  type DevSkillPackage,
  type DevSkillSource,
  type RuntimeEvent,
  type ServerConversationEvent,
  type ServerSession,
} from "../../api";
import { buildAssistantTurnMessages } from "../../chatEventMessages";
import { buildCreateSkillPrompt, buildModifySkillPrompt } from "../../devSkillPrompts";
import { useI18n } from "../../i18n/I18nProvider";
import { loadModelSettings, loadSavedModelSettings } from "../../modelSettings";
import {
  buildSkillAuthoringTurn,
  parseSkillAuthoringResponse,
  skillDraftDisplayName,
  type SkillAuthoringDraft,
} from "../../skillAuthoringProtocol";
import type { ChatMessage } from "../../types";
import { AppIconButton } from "../AppIconButton";
import { MessageList } from "../MessageList";

export type SkillAuthoringSaveResult = {
  activeGeneration: number | null;
  directory: string;
  inventory: DevSkillInventory;
  reloadFailed: boolean;
};

type SkillAuthoringDialogProps = {
  inventory: DevSkillInventory | null;
  onOpenChange: (open: boolean) => void;
  onRequestModelSettings: () => void;
  onSaved: (result: SkillAuthoringSaveResult) => void;
  target: DevSkillPackage | "new" | null;
};

type SetupStatus = "checking" | "loading" | "needs-model" | "ready" | "failed";
type MutationStatus = "idle" | "applying" | "complete";
const TURN_EVENT_POLL_INTERVAL_MS = 250;

function createMessageId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `message-${Math.random().toString(36).slice(2)}`;
}

export function SkillAuthoringDialog({
  inventory,
  onOpenChange,
  onRequestModelSettings,
  onSaved,
  target,
}: SkillAuthoringDialogProps): JSX.Element {
  const { t } = useI18n();
  const editingTarget = target !== null && target !== "new" ? target : null;
  const editing = editingTarget !== null;
  const open = target !== null && inventory !== null;
  const [setupStatus, setSetupStatus] = useState<SetupStatus>("checking");
  const [mutationStatus, setMutationStatus] = useState<MutationStatus>("idle");
  const [source, setSource] = useState<DevSkillSource | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [candidate, setCandidate] = useState<SkillAuthoringDraft | null>(null);
  const [isSending, setIsSending] = useState(false);
  const [conversationError, setConversationError] = useState<string | null>(null);
  const [protocolError, setProtocolError] = useState<string | null>(null);
  const [reloadFailed, setReloadFailed] = useState(false);
  const sessionRef = useRef<ServerSession | null>(null);
  const activeTurnRef = useRef<{ sessionId: string; turnId: string } | null>(null);
  const initialContextSentRef = useRef(false);
  const generationRef = useRef(0);
  const messageListRef = useRef<HTMLDivElement | null>(null);
  const composerRef = useRef<HTMLTextAreaElement | null>(null);
  const translateRef = useRef(t);
  translateRef.current = t;

  useEffect(() => {
    const generation = ++generationRef.current;
    const previousSession = sessionRef.current;
    sessionRef.current = null;
    activeTurnRef.current = null;
    initialContextSentRef.current = false;
    if (previousSession) void disposeSession(previousSession);
    setSetupStatus("checking");
    setMutationStatus("idle");
    setSource(null);
    setMessages([]);
    setDraft("");
    setCandidate(null);
    setConversationError(null);
    setProtocolError(null);
    setReloadFailed(false);
    setIsSending(false);
    if (target === null) return;

    void loadModelSettings()
      .then(async (snapshot) => {
        if (generationRef.current !== generation) return;
        if (!snapshot.saved) {
          setSetupStatus("needs-model");
          return;
        }
        if (target !== "new") {
          setSetupStatus("loading");
          const nextSource = await readDevSkill(target.path);
          if (generationRef.current !== generation) return;
          setSource(nextSource);
        }
        setMessages([welcomeMessage(target, translateRef.current)]);
        setSetupStatus("ready");
      })
      .catch(() => {
        if (generationRef.current === generation) setSetupStatus("failed");
      });
  }, [target]);

  useEffect(() => {
    const viewport = messageListRef.current?.querySelector(".message-list");
    if (viewport) viewport.scrollTop = viewport.scrollHeight;
  }, [candidate, isSending, messages]);

  useEffect(() => () => {
    const session = sessionRef.current;
    const activeTurn = activeTurnRef.current;
    ++generationRef.current;
    sessionRef.current = null;
    activeTurnRef.current = null;
    if (session) void cancelAndDispose(session, activeTurn);
  }, []);

  const statusLabel = useMemo(() => {
    if (mutationStatus === "complete") return t("developer.authoring.statusComplete");
    if (mutationStatus === "applying") return t("developer.authoring.statusApplying");
    if (isSending) return t("developer.authoring.statusThinking");
    if (candidate) return t("developer.authoring.statusDraft");
    return t("developer.authoring.statusDiscovering");
  }, [candidate, isSending, mutationStatus, t]);

  const close = () => {
    if (mutationStatus === "applying") return;
    const session = sessionRef.current;
    const activeTurn = activeTurnRef.current;
    ++generationRef.current;
    sessionRef.current = null;
    activeTurnRef.current = null;
    if (session) void cancelAndDispose(session, activeTurn);
    onOpenChange(false);
  };

  const send = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const text = draft.trim();
    if (!text || isSending || mutationStatus !== "idle" || !inventory) return;
    if (editing && !source) return;
    const generation = generationRef.current;
    const localUserId = createMessageId();
    const pendingId = createMessageId();
    setMessages((current) => [
      ...current,
      { body: text, id: localUserId, role: "user" },
      {
        id: pendingId,
        kind: "reasoning",
        role: "assistant",
        status: "running",
        text: t("developer.authoring.thinking"),
      },
    ]);
    setDraft("");
    setCandidate(null);
    setConversationError(null);
    setProtocolError(null);
    setIsSending(true);

    let startedTurnId: string | null = null;
    try {
      let session = sessionRef.current;
      if (!session) {
        session = await createServerSession(authoringTitle(target, t));
        if (generationRef.current !== generation) {
          void disposeSession(session);
          return;
        }
        sessionRef.current = session;
      }
      const context = editingTarget
        ? buildModifySkillPrompt(inventory.root, editingTarget)
        : buildCreateSkillPrompt(inventory.root);
      const content = !initialContextSentRef.current
        ? buildSkillAuthoringTurn(context, text, source ?? undefined)
        : text;
      const settings = await loadSavedModelSettings();
      const response = await startSessionTurn(session.id, createMessageId(), content, settings);
      if (generationRef.current !== generation) return;
      startedTurnId = response.turn.id;
      initialContextSentRef.current = true;
      activeTurnRef.current = { sessionId: session.id, turnId: response.turn.id };
      setMessages((current) => current.map((message) => (
        message.id === localUserId ? { ...message, id: response.userMessage.id } : message
      )));
      await consumeTurn({
        expectedDirectory: editingTarget?.path,
        generation,
        pendingId,
        sessionId: session.id,
        turnId: response.turn.id,
      });
    } catch {
      if (generationRef.current === generation) {
        const turnPrefix = startedTurnId ? `skill-authoring:${startedTurnId}:` : null;
        setMessages((current) => current.filter((message) => (
          message.id !== pendingId && (!turnPrefix || !message.id.startsWith(turnPrefix))
        )));
        setCandidate(null);
        setProtocolError(null);
        setConversationError(t("developer.authoring.sendFailed"));
      }
    } finally {
      if (generationRef.current === generation) {
        activeTurnRef.current = null;
        setIsSending(false);
      }
    }
  };

  const consumeTurn = async (options: {
    expectedDirectory?: string;
    generation: number;
    pendingId: string;
    sessionId: string;
    turnId: string;
  }) => {
    let cursor = -1;
    let events: ServerConversationEvent[] = [];
    while (generationRef.current === options.generation) {
      const page = await listServerTurnEvents(options.sessionId, options.turnId, cursor);
      if (generationRef.current !== options.generation) return;
      events = appendUniqueEvents(events, page.events);
      cursor = page.nextCursor;
      const turnMessages = visibleTurnMessages(
        events.map((event) => event.payload),
        options.turnId,
        options.expectedDirectory,
        t("developer.authoring.draftPrepared"),
      );
      if (turnMessages.candidate) setCandidate(turnMessages.candidate);
      setProtocolError(turnMessages.protocolError
        ? t(`developer.authoring.${turnMessages.protocolError}`)
        : null);
      const prefix = `skill-authoring:${options.turnId}:`;
      setMessages((current) => [
        ...current.filter((message) => message.id !== options.pendingId && !message.id.startsWith(prefix)),
        ...turnMessages.messages,
      ]);
      if (page.turn.status === "running") {
        await waitForTurnPoll();
        continue;
      }
      if (page.turn.status !== "completed") {
        throw new Error(`Skill authoring turn ended with ${page.turn.status}`);
      }
      return;
    }
  };

  const applyCandidate = async () => {
    if (!candidate || mutationStatus !== "idle" || (editing && !source)) return;
    setMutationStatus("applying");
    setConversationError(null);
    try {
      const mutation = editingTarget && source
        ? await updateDevSkill(editingTarget.path, {
          expectedRevision: source.sourceRevision,
          manifest: candidate.manifest,
          skillMd: candidate.skillMd,
        })
        : await createDevSkill(candidate);
      let inventoryResult = mutation.inventory;
      let activeGeneration: number | null = null;
      let didReloadFail = false;
      try {
        const reloaded = await reloadDevSkills();
        inventoryResult = reloaded.inventory;
        activeGeneration = reloaded.activeGeneration;
      } catch {
        didReloadFail = true;
      }
      setReloadFailed(didReloadFail);
      setMutationStatus("complete");
      onSaved({
        activeGeneration,
        directory: candidate.directory,
        inventory: inventoryResult,
        reloadFailed: didReloadFail,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message.toLowerCase() : "";
      setConversationError(t(message.includes("conflict") || message.includes("409")
        ? "developer.authoring.conflict"
        : "developer.authoring.applyFailed"));
      setMutationStatus("idle");
    }
  };

  return (
    <Dialog.Root open={open} onOpenChange={(nextOpen) => {
      if (!nextOpen) close();
    }}>
      <Dialog.Portal>
        <Dialog.Overlay className="developer-dialog-overlay" />
        <Dialog.Content
          aria-label={editing
            ? t("developer.authoring.editTitle")
            : t("developer.authoring.createTitle")}
          className="developer-dialog-content developer-authoring-dialog"
        >
          <header className="developer-dialog-header developer-authoring-header">
            <div className="developer-authoring-title">
              <span className="developer-authoring-mark" aria-hidden="true">
                <Sparkles size={18} />
              </span>
              <div>
                <Dialog.Title>
                  {editing
                    ? t("developer.authoring.editTitle")
                    : t("developer.authoring.createTitle")}
                </Dialog.Title>
                <Dialog.Description>
                  {editingTarget
                    ? t("developer.authoring.editSubtitle", { name: editingTarget.name })
                    : t("developer.authoring.createSubtitle")}
                </Dialog.Description>
              </div>
            </div>
            <div className="developer-authoring-header-actions">
              {setupStatus === "ready" ? (
                <span className="developer-authoring-status">
                  <span aria-hidden="true" /> {statusLabel}
                </span>
              ) : null}
              <AppIconButton
                disabled={mutationStatus === "applying"}
                label={t("developer.authoring.close")}
                onClick={close}
              >
                <X aria-hidden="true" size={16} />
              </AppIconButton>
            </div>
          </header>

          {setupStatus === "checking" || setupStatus === "loading" ? (
            <AuthoringState
              icon={<LoaderCircle aria-hidden="true" className="spin" size={22} />}
              text={t(setupStatus === "loading"
                ? "developer.authoring.loadingSkill"
                : "developer.authoring.checkingModel")}
            />
          ) : setupStatus === "needs-model" ? (
            <div className="developer-authoring-gate">
              <span className="developer-authoring-gate-icon" aria-hidden="true">
                <KeyRound size={24} />
              </span>
              <h3>{t("developer.authoring.modelRequired")}</h3>
              <p>{t("developer.authoring.modelRequiredHint")}</p>
              <button className="developer-primary-button" onClick={onRequestModelSettings} type="button">
                <span>{t("developer.authoring.configureModel")}</span>
                <ArrowRight aria-hidden="true" size={16} />
              </button>
            </div>
          ) : setupStatus === "failed" ? (
            <AuthoringState
              error
              icon={<AlertTriangle aria-hidden="true" size={22} />}
              text={t("developer.authoring.setupFailed")}
            />
          ) : (
            <div className="developer-authoring-workspace">
              <aside className="developer-authoring-guide">
                <span className="developer-authoring-eyebrow">
                  {t("developer.authoring.eyebrow")}
                </span>
                <h3>{t("developer.authoring.guideTitle")}</h3>
                <ol>
                  <li data-active={mutationStatus === "idle" && !candidate}>{t("developer.authoring.stepDescribe")}</li>
                  <li data-active={mutationStatus === "idle" && Boolean(candidate)}>{t("developer.authoring.stepReview")}</li>
                  <li data-active={mutationStatus !== "idle"}>{t("developer.authoring.stepApply")}</li>
                </ol>
                <p>{t("developer.authoring.guideHint")}</p>
              </aside>

              <section className="developer-authoring-chat" ref={messageListRef}>
                <MessageList messages={messages} />

                {protocolError ? (
                  <div className="developer-authoring-error" role="alert">
                    <AlertTriangle aria-hidden="true" size={16} />
                    <span>{protocolError}</span>
                  </div>
                ) : null}
                {conversationError ? (
                  <div className="developer-authoring-error" role="alert">
                    <AlertTriangle aria-hidden="true" size={16} />
                    <span>{conversationError}</span>
                  </div>
                ) : null}

                {candidate && mutationStatus !== "complete" ? (
                  <div className="developer-authoring-candidate" role="status">
                    <div>
                      <span>{t("developer.authoring.candidateLabel")}</span>
                      <strong>{skillDraftDisplayName(candidate)}</strong>
                      <small>{candidate.directory}</small>
                    </div>
                    <div>
                      <button
                        className="developer-secondary-button"
                        disabled={mutationStatus === "applying"}
                        onClick={() => {
                          setCandidate(null);
                          window.setTimeout(() => composerRef.current?.focus(), 0);
                        }}
                        type="button"
                      >
                        {t("developer.authoring.keepRefining")}
                      </button>
                      <button
                        className="developer-primary-button"
                        disabled={mutationStatus === "applying"}
                        onClick={() => void applyCandidate()}
                        type="button"
                      >
                        {mutationStatus === "applying"
                          ? <LoaderCircle aria-hidden="true" className="spin" size={16} />
                          : <CheckCircle2 aria-hidden="true" size={16} />}
                        {t(mutationStatus === "applying"
                          ? "developer.authoring.applying"
                          : "developer.authoring.apply")}
                      </button>
                    </div>
                  </div>
                ) : null}

                {mutationStatus === "complete" ? (
                  <div className="developer-authoring-complete" role="status">
                    <CheckCircle2 aria-hidden="true" size={20} />
                    <div>
                      <strong>{t("developer.authoring.completeTitle")}</strong>
                      <p>{t(reloadFailed
                        ? "developer.authoring.completeReloadFailed"
                        : "developer.authoring.completeHint")}</p>
                    </div>
                    <button className="developer-primary-button" onClick={close} type="button">
                      {t("developer.authoring.done")}
                    </button>
                  </div>
                ) : (
                  <form className="developer-authoring-composer" onSubmit={send}>
                    <label className="sr-only" htmlFor="skill-authoring-message">
                      {t("developer.authoring.message")}
                    </label>
                    <textarea
                      autoFocus
                      disabled={isSending || mutationStatus === "applying"}
                      id="skill-authoring-message"
                      onChange={(event) => setDraft(event.target.value)}
                      onKeyDown={(event) => {
                        if (event.key === "Enter" && !event.shiftKey) {
                          event.preventDefault();
                          event.currentTarget.form?.requestSubmit();
                        }
                      }}
                      placeholder={t(editing
                        ? "developer.authoring.editPlaceholder"
                        : "developer.authoring.createPlaceholder")}
                      ref={composerRef}
                      rows={3}
                      value={draft}
                    />
                    <div>
                      <small>{t("developer.authoring.composerHint")}</small>
                      <button
                        aria-label={t("developer.authoring.send")}
                        className="developer-authoring-send"
                        disabled={!draft.trim() || isSending}
                        type="submit"
                      >
                        {isSending
                          ? <LoaderCircle aria-hidden="true" className="spin" size={17} />
                          : <Send aria-hidden="true" size={17} />}
                      </button>
                    </div>
                  </form>
                )}
              </section>
            </div>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function AuthoringState(props: {
  error?: boolean;
  icon: JSX.Element;
  text: string;
}): JSX.Element {
  return (
    <div
      className={`developer-authoring-state${props.error ? " developer-authoring-state-error" : ""}`}
      role={props.error ? "alert" : "status"}
    >
      {props.icon}
      <span>{props.text}</span>
    </div>
  );
}

function welcomeMessage(
  target: DevSkillPackage | "new",
  t: ReturnType<typeof useI18n>["t"],
): ChatMessage {
  return {
    body: target === "new"
      ? t("developer.authoring.welcomeCreate")
      : t("developer.authoring.welcomeEdit", { name: target.name }),
    id: "skill-authoring-welcome",
    role: "assistant",
  };
}

function authoringTitle(
  target: DevSkillPackage | "new" | null,
  t: ReturnType<typeof useI18n>["t"],
): string {
  return target && target !== "new"
    ? t("developer.authoring.sessionEdit", { name: target.name })
    : t("developer.authoring.sessionCreate");
}

function waitForTurnPoll(): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, TURN_EVENT_POLL_INTERVAL_MS);
  });
}

function visibleTurnMessages(
  events: RuntimeEvent[],
  turnId: string,
  expectedDirectory: string | undefined,
  draftPrepared: string,
): {
  candidate: SkillAuthoringDraft | null;
  messages: ChatMessage[];
  protocolError: "draftDirectory" | "draftFormat" | null;
} {
  let index = 0;
  let candidate: SkillAuthoringDraft | null = null;
  let protocolError: "draftDirectory" | "draftFormat" | null = null;
  const messages = buildAssistantTurnMessages(
    { accepted: true, events },
    () => `skill-authoring:${turnId}:${index++}`,
  ).map((message): ChatMessage => {
    if (!("body" in message) || message.role !== "assistant") return message;
    const parsed = parseSkillAuthoringResponse(message.body, expectedDirectory);
    if (parsed.draft) candidate = parsed.draft;
    if (parsed.error) protocolError = parsed.error === "directory" ? "draftDirectory" : "draftFormat";
    return {
      ...message,
      body: parsed.visibleText || (parsed.draft ? draftPrepared : ""),
    };
  }).filter((message) => !("body" in message) || Boolean(message.body));
  return { candidate, messages, protocolError };
}

function appendUniqueEvents(
  current: ServerConversationEvent[],
  next: ServerConversationEvent[],
): ServerConversationEvent[] {
  const unique = new Map(current.map((event) => [event.id, event]));
  for (const event of next) unique.set(event.id, event);
  return [...unique.values()].sort((left, right) => left.event_index - right.event_index);
}

async function cancelAndDispose(
  session: ServerSession,
  activeTurn: { sessionId: string; turnId: string } | null,
): Promise<void> {
  if (activeTurn) {
    await cancelServerTurn(activeTurn.sessionId, activeTurn.turnId).catch(() => undefined);
  }
  await disposeSession(session);
}

async function disposeSession(session: ServerSession): Promise<void> {
  try {
    const current = await loadServerSession(session.id);
    await deleteServerSession(current.session);
  } catch {
    // Authoring sessions are best-effort ephemeral; failed cleanup never blocks the editor.
  }
}
