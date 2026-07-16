import { useState } from "react";
import { CircleAlert, CircleCheck, CircleDot, Info, LoaderCircle, TriangleAlert } from "lucide-react";

import type { StructuredContent } from "../../runtimeEvents";
import {
  adaptStructuredContent,
  type StructuredContentBlock,
  type StructuredContentTone,
} from "../../structuredContentAdapters";
import type { StructuredContentActionHandler } from "../../types";
import { useI18n } from "../../i18n/I18nProvider";

type StructuredContentViewProps = {
  content: StructuredContent;
  onAction?: StructuredContentActionHandler;
};

const statusIcons = {
  danger: CircleAlert,
  info: Info,
  neutral: CircleDot,
  success: CircleCheck,
  warning: TriangleAlert,
} satisfies Record<StructuredContentTone, typeof CircleDot>;

export function StructuredContentView({
  content,
  onAction,
}: StructuredContentViewProps): JSX.Element {
  const { t } = useI18n();
  const [pendingBinding, setPendingBinding] = useState<string | null>(null);
  const [actionError, setActionError] = useState(false);
  const model = adaptStructuredContent(content);
  if (!model) {
    return (
      <div className="structured-content-fallback" data-mime-type={content.mime_type}>
        {content.fallback_text}
      </div>
    );
  }
  const activePendingBinding = pendingBinding !== null && model.actions.some(
    (action) => action.bindingId === pendingBinding,
  ) ? pendingBinding : null;

  return (
    <div
      aria-label="Structured assistant content"
      className={`structured-content-card structured-content-card-${model.source}`}
    >
      <div className="structured-content-blocks">
        {model.blocks.map((block, index) => (
          <StructuredBlock block={block} key={`${block.kind}-${index}`} />
        ))}
      </div>
      {model.actions.length > 0 ? (
        <div className="structured-content-actions">
          {model.actions.map((action) => (
            <button
              aria-busy={activePendingBinding !== null && activePendingBinding === action.bindingId}
              className={`structured-content-action structured-content-action-${action.variant}`}
              disabled={!onAction || !action.bindingId || activePendingBinding !== null}
              key={`${action.actionId}:${action.bindingId ?? "unbound"}`}
              onClick={() => {
                if (!action.bindingId) return;
                setActionError(false);
                let operation: void | Promise<void>;
                try {
                  operation = onAction?.({
                    actionId: action.actionId,
                    bindingId: action.bindingId,
                  });
                } catch {
                  setActionError(true);
                  return;
                }
                if (!operation) return;
                setPendingBinding(action.bindingId);
                void operation.catch(() => {
                  setActionError(true);
                }).finally(() => setPendingBinding(null));
              }}
              type="button"
            >
              {activePendingBinding !== null && activePendingBinding === action.bindingId ? (
                <>
                  <LoaderCircle aria-hidden="true" className="structured-content-action-spinner" size={15} />
                  {t("chat.structuredActionWorking")}
                </>
              ) : action.label}
            </button>
          ))}
        </div>
      ) : null}
      {actionError ? (
        <p className="structured-content-action-error" role="alert">
          {t("chat.structuredActionRetry")}
        </p>
      ) : null}
    </div>
  );
}

function StructuredBlock({ block }: { block: StructuredContentBlock }): JSX.Element {
  if (block.kind === "text") {
    const Tag = block.style === "heading" ? "h3" : "p";
    return (
      <Tag className={`structured-content-text structured-content-text-${block.style}`}>
        {block.text}
      </Tag>
    );
  }
  if (block.kind === "field") {
    return (
      <div className="structured-content-field">
        <span>{block.label}</span>
        <strong>{block.value}</strong>
      </div>
    );
  }
  if (block.kind === "list") {
    return (
      <ul className="structured-content-list">
        {block.items.map((item, index) => <li key={`${index}:${item}`}>{item}</li>)}
      </ul>
    );
  }
  const StatusIcon = statusIcons[block.tone];
  return (
    <div className={`structured-content-status structured-content-status-${block.tone}`}>
      <StatusIcon aria-hidden="true" size={15} />
      <span>{block.label}</span>
    </div>
  );
}
