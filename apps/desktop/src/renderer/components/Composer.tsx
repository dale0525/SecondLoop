import { FormEvent } from "react";
import { Send, Square } from "lucide-react";

import { AppIconButton } from "./AppIconButton";
import { useI18n } from "../i18n/I18nProvider";

type ComposerProps = {
  draft: string;
  error: string | null;
  isSending: boolean;
  isStopping: boolean;
  onChange: (value: string) => void;
  onStop: () => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  status: string | null;
};

export function Composer({
  draft,
  error,
  isSending,
  isStopping,
  onChange,
  onStop,
  onSubmit,
  status,
}: ComposerProps): JSX.Element {
  const { t } = useI18n();
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
      <div className="composer-input-row">
        <label className="sr-only" htmlFor="agentweave-message">
          {t("composer.message")}
        </label>
        <input
          id="agentweave-message"
          aria-label={t("composer.message")}
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
          <AppIconButton label={t("composer.send")} type="submit">
            <Send size={18} aria-hidden="true" />
          </AppIconButton>
        )}
      </div>
    </form>
  );
}
