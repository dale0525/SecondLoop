import { FormEvent } from "react";
import { FileText, LoaderCircle, Paperclip, Send, Square, X } from "lucide-react";

import type { AttachmentMetadata } from "../../shared/attachments";
import { AppIconButton } from "./AppIconButton";
import { useI18n } from "../i18n/I18nProvider";

type ComposerProps = {
  draft: string;
  error: string | null;
  attachments?: AttachmentMetadata[];
  isImportingAttachment?: boolean;
  isSendDisabled?: boolean;
  isSending: boolean;
  isStopping: boolean;
  onAddAttachment?: () => void;
  onChange: (value: string) => void;
  onRemoveAttachment?: (id: string) => void;
  onStop: () => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  removingAttachmentIds?: string[];
  status: string | null;
};

export function Composer({
  draft,
  error,
  attachments = [],
  isImportingAttachment = false,
  isSendDisabled = false,
  isSending,
  isStopping,
  onAddAttachment,
  onChange,
  onRemoveAttachment,
  onStop,
  onSubmit,
  removingAttachmentIds = [],
  status,
}: ComposerProps): JSX.Element {
  const { t } = useI18n();
  const removing = new Set(removingAttachmentIds);
  return (
    <form aria-label={t("composer.ariaLabel")} className="composer" onSubmit={onSubmit}>
      {error ? (
        <p className="composer-error" role="alert">
          {error}
        </p>
      ) : null}
      {status ? (
        <p className="composer-status" role="status">
          {status}
        </p>
      ) : null}
      {attachments.length > 0 ? (
        <div className="composer-attachment-list" aria-label={t("composer.attachments")}>
          {attachments.map((attachment) => (
            <span className="composer-attachment-chip" key={attachment.id}>
              <FileText aria-hidden="true" size={16} />
              <span>
                <strong>{attachment.fileName}</strong>
                <small>{formatBytes(attachment.sizeBytes)}</small>
              </span>
              {onRemoveAttachment ? (
                <button
                  aria-label={t("composer.removeAttachment", { name: attachment.fileName })}
                  disabled={removing.has(attachment.id) || isSending}
                  onClick={() => onRemoveAttachment(attachment.id)}
                  type="button"
                >
                  {removing.has(attachment.id)
                    ? <LoaderCircle aria-hidden="true" className="spin" size={15} />
                    : <X aria-hidden="true" size={15} />}
                </button>
              ) : null}
            </span>
          ))}
        </div>
      ) : null}
      <div className="composer-input-row">
        {onAddAttachment ? (
          <button
            aria-label={t("composer.addAttachment")}
            className="composer-attach-button"
            disabled={isImportingAttachment || isSending}
            onClick={onAddAttachment}
            title={t("composer.addAttachment")}
            type="button"
          >
            {isImportingAttachment
              ? <LoaderCircle aria-hidden="true" className="spin" size={18} />
              : <Paperclip aria-hidden="true" size={18} />}
          </button>
        ) : null}
        <label className="sr-only" htmlFor="agentweave-message">
          {t("composer.message")}
        </label>
        <textarea
          id="agentweave-message"
          aria-label={t("composer.message")}
          rows={1}
          value={draft}
          onChange={(event) => onChange(event.target.value)}
        />
        {isSending ? (
          <AppIconButton
            disabled={isStopping}
            label={t("composer.stop")}
            onClick={onStop}
            type="button"
          >
            <Square fill="currentColor" size={14} aria-hidden="true" />
          </AppIconButton>
        ) : (
          <AppIconButton disabled={isSendDisabled} label={t("composer.send")} type="submit">
            <Send size={18} aria-hidden="true" />
          </AppIconButton>
        )}
      </div>
    </form>
  );
}

function formatBytes(value: number): string {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${Math.round(value / 1024)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}
