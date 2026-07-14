import * as Dialog from "@radix-ui/react-dialog";
import { Check, Pencil, Plus, Search, Trash2, X } from "lucide-react";
import { FormEvent, useMemo, useState } from "react";

import type { ServerSession } from "../api";
import { useI18n } from "../i18n/I18nProvider";
import { AppIconButton } from "./AppIconButton";

type ConversationDrawerProps = {
  activeSessionId: string | null;
  error: string | null;
  hasMore: boolean;
  isLoading: boolean;
  isOpen: boolean;
  onDelete: (session: ServerSession) => Promise<void>;
  onLoadMore: () => Promise<void>;
  onNewChat: () => void;
  onOpenChange: (isOpen: boolean) => void;
  onRename: (session: ServerSession, title: string) => Promise<void>;
  onRetry: () => Promise<void>;
  onSelect: (session: ServerSession) => Promise<boolean>;
  sessions: ServerSession[];
};

export function ConversationDrawer(props: ConversationDrawerProps): JSX.Element {
  const { t } = useI18n();
  const [query, setQuery] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingTitle, setEditingTitle] = useState("");
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<ServerSession | null>(null);
  const filtered = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase();
    return normalized
      ? props.sessions.filter((session) => session.title.toLocaleLowerCase().includes(normalized))
      : props.sessions;
  }, [props.sessions, query]);
  let currentSection = "";

  const beginRename = (session: ServerSession) => {
    setEditingId(session.id);
    setEditingTitle(session.title);
  };
  const submitRename = async (event: FormEvent, session: ServerSession) => {
    event.preventDefault();
    const title = editingTitle.trim();
    if (!title || title === session.title) {
      setEditingId(null);
      return;
    }
    setPendingId(session.id);
    try {
      await props.onRename(session, title);
      setEditingId(null);
    } catch {
      // The parent refreshes authoritative history and keeps this editor open.
    } finally {
      setPendingId(null);
    }
  };

  return (
    <Dialog.Root open={props.isOpen} onOpenChange={props.onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="conversation-drawer-overlay" />
        <Dialog.Content
          aria-label={t("conversation.title")}
          className="conversation-drawer-content"
          onEscapeKeyDown={(event) => {
            if (!editingId) return;
            event.preventDefault();
            setEditingId(null);
          }}
        >
          <header className="conversation-drawer-header">
            <Dialog.Title>{t("conversation.title")}</Dialog.Title>
            <AppIconButton label={t("conversation.close")} onClick={() => props.onOpenChange(false)}>
              <X size={16} aria-hidden="true" />
            </AppIconButton>
          </header>

          <button className="conversation-drawer-new" onClick={props.onNewChat} type="button">
            <Plus size={14} aria-hidden="true" />
            <span>{t("conversation.new")}</span>
          </button>

          <label className="search-box conversation-drawer-search">
            <Search size={14} aria-hidden="true" />
            <span className="sr-only">{t("conversation.search")}</span>
            <input
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("conversation.search")}
              type="search"
              value={query}
            />
          </label>

          <div className="conversation-drawer-list" aria-live="polite">
            {props.error ? (
              <div className="conversation-drawer-state" role="alert">
                <p>{props.error}</p>
                <button onClick={() => void props.onRetry()} type="button">
                  {t("conversation.retry")}
                </button>
              </div>
            ) : null}
            {props.isLoading && props.sessions.length === 0 ? (
              <p className="conversation-drawer-state">{t("conversation.loading")}</p>
            ) : null}
            {!props.isLoading && !props.error && filtered.length === 0 ? (
              <p className="conversation-drawer-state">
                {query ? t("conversation.noSearchResults") : t("conversation.empty")}
              </p>
            ) : null}
            {filtered.map((session) => {
              const sectionLabel = sectionKey(session.updated_at);
              const shouldShowSection = sectionLabel !== currentSection;
              currentSection = sectionLabel;
              const pending = pendingId === session.id;
              const active = props.activeSessionId === session.id;

              return (
                <div key={session.id}>
                  {shouldShowSection ? (
                    <p className="section-label conversation-drawer-section">
                      {t(sectionLabel)}
                    </p>
                  ) : null}
                  {editingId === session.id ? (
                    <form
                      className="conversation-row conversation-row-editing"
                      onSubmit={(event) => void submitRename(event, session)}
                    >
                      <input
                        aria-label={t("conversation.renameInput")}
                        autoFocus
                        disabled={pending}
                        maxLength={256}
                        onChange={(event) => setEditingTitle(event.target.value)}
                        onKeyDown={(event) => {
                          if (event.key !== "Escape") return;
                          event.preventDefault();
                          event.stopPropagation();
                          setEditingId(null);
                        }}
                        value={editingTitle}
                      />
                      <AppIconButton label={t("conversation.saveRename")} type="submit">
                        <Check size={15} aria-hidden="true" />
                      </AppIconButton>
                    </form>
                  ) : (
                    <div className={`conversation-row${active ? " is-active" : ""}`}>
                      <button
                        className="conversation-row-main"
                        disabled={pending}
                        onClick={() => void props.onSelect(session)}
                        type="button"
                      >
                        <strong>{session.title}</strong>
                        <small>{relativeTime(session.updated_at, t)}</small>
                      </button>
                      <div className="conversation-row-actions">
                        <AppIconButton
                          label={t("conversation.renameNamed", { name: session.title })}
                          onClick={() => beginRename(session)}
                        >
                          <Pencil size={14} aria-hidden="true" />
                        </AppIconButton>
                        <AppIconButton
                          label={t("conversation.deleteNamed", { name: session.title })}
                          onClick={() => setDeleteTarget(session)}
                        >
                          <Trash2 size={14} aria-hidden="true" />
                        </AppIconButton>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
            {props.hasMore && !query ? (
              <button
                className="conversation-load-more"
                disabled={props.isLoading}
                onClick={() => void props.onLoadMore()}
                type="button"
              >
                {props.isLoading ? t("conversation.loading") : t("conversation.loadMore")}
              </button>
            ) : null}
          </div>
        </Dialog.Content>
      </Dialog.Portal>

      <Dialog.Root open={Boolean(deleteTarget)} onOpenChange={(open) => !open && setDeleteTarget(null)}>
        <Dialog.Portal>
          <Dialog.Overlay className="modal-overlay" />
          <Dialog.Content className="modal-content conversation-delete-dialog">
            <Dialog.Title>{t("conversation.deleteTitle")}</Dialog.Title>
            <Dialog.Description>
              {t("conversation.deleteDescription", { name: deleteTarget?.title ?? "" })}
            </Dialog.Description>
            <div className="dialog-actions">
              <button onClick={() => setDeleteTarget(null)} type="button">
                {t("common.cancel")}
              </button>
              <button
                className="danger-button"
                disabled={pendingId === deleteTarget?.id}
                onClick={() => {
                  if (!deleteTarget) return;
                  setPendingId(deleteTarget.id);
                  void props.onDelete(deleteTarget).then(
                    () => setDeleteTarget(null),
                    () => undefined,
                  ).finally(() => setPendingId(null));
                }}
                type="button"
              >
                {t("conversation.delete")}
              </button>
            </div>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </Dialog.Root>
  );
}

function sectionKey(updatedAt: string): string {
  const date = new Date(updatedAt);
  if (!Number.isFinite(date.getTime())) return "conversation.previous30Days";
  const elapsedDays = Math.floor((Date.now() - date.getTime()) / 86_400_000);
  if (elapsedDays <= 0) return "conversation.today";
  if (elapsedDays === 1) return "conversation.yesterday";
  return "conversation.previous30Days";
}

function relativeTime(
  value: string,
  t: ReturnType<typeof useI18n>["t"],
): string {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return value;
  const elapsedMinutes = Math.max(0, Math.floor((Date.now() - date.getTime()) / 60_000));
  if (elapsedMinutes < 1) return t("conversation.justNow");
  if (elapsedMinutes === 1) return t("conversation.minuteAgo");
  if (elapsedMinutes < 60) return t("conversation.minutesAgo", { count: String(elapsedMinutes) });
  if (elapsedMinutes < 1_440) {
    const elapsedHours = Math.floor(elapsedMinutes / 60);
    if (elapsedHours === 1) return t("conversation.hourAgo");
    return t("conversation.hoursAgo", { count: String(elapsedHours) });
  }
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(date);
}
