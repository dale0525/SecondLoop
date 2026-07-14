import * as Dialog from "@radix-ui/react-dialog";
import {
  Brain,
  CalendarDays,
  MessageCircle,
  MoreHorizontal,
  Plug,
  Settings,
  ShieldCheck,
  X,
} from "lucide-react";
import type { ReactNode } from "react";

import { useI18n } from "../i18n/I18nProvider";

export type SecondLoopView =
  | "today"
  | "chat"
  | "actions"
  | "memory"
  | "connections"
  | "settings";

type SecondLoopShellProps = {
  activeView: SecondLoopView;
  children: ReactNode;
  onNavigate: (view: SecondLoopView) => void;
};

const primaryItems = [
  { icon: CalendarDays, key: "nav.today", view: "today" },
  { icon: MessageCircle, key: "nav.chat", view: "chat" },
  { icon: ShieldCheck, key: "nav.actions", view: "actions" },
  { icon: Brain, key: "nav.memory", view: "memory" },
] as const;

const secondaryItems = [
  { icon: Plug, key: "nav.connections", view: "connections" },
  { icon: Settings, key: "nav.settings", view: "settings" },
] as const;

export function SecondLoopShell({
  activeView,
  children,
  onNavigate,
}: SecondLoopShellProps): JSX.Element {
  const { t } = useI18n();
  return (
    <div className="secondloop-shell">
      <aside className="secondloop-sidebar" aria-label="SecondLoop">
        <div className="secondloop-brand">
          <span aria-hidden="true" className="secondloop-mark"><i /><i /></span>
          <span><strong>SecondLoop</strong><small>Personal desk</small></span>
        </div>
        <nav className="secondloop-nav" aria-label="Primary">
          {primaryItems.map((item) => (
            <NavButton active={activeView === item.view} item={item} key={item.view} onNavigate={onNavigate} />
          ))}
        </nav>
        <nav className="secondloop-nav secondloop-nav-secondary" aria-label="System">
          {secondaryItems.map((item) => (
            <NavButton active={activeView === item.view} item={item} key={item.view} onNavigate={onNavigate} />
          ))}
        </nav>
      </aside>
      <div className="secondloop-content">{children}</div>
      <nav className="secondloop-mobile-nav" aria-label="Primary">
        {primaryItems.map((item) => (
          <NavButton active={activeView === item.view} item={item} key={item.view} onNavigate={onNavigate} />
        ))}
        <Dialog.Root>
          <Dialog.Trigger asChild>
            <button className="secondloop-mobile-nav-item" type="button">
              <MoreHorizontal aria-hidden="true" size={19} />
              <span>{t("nav.more")}</span>
            </button>
          </Dialog.Trigger>
          <Dialog.Portal>
            <Dialog.Overlay className="secondloop-more-overlay" />
            <Dialog.Content className="secondloop-more-sheet">
              <div className="secondloop-more-heading">
                <Dialog.Title>{t("nav.more")}</Dialog.Title>
                <Dialog.Close asChild>
                  <button aria-label={t("shell.closeMore")} className="secondloop-more-close" type="button"><X size={18} /></button>
                </Dialog.Close>
              </div>
              {secondaryItems.map((item) => {
                const Icon = item.icon;
                return (
                  <Dialog.Close asChild key={item.view}>
                    <button className="secondloop-more-item" onClick={() => onNavigate(item.view)} type="button">
                      <Icon aria-hidden="true" size={19} />
                      <span>{t(item.key)}</span>
                    </button>
                  </Dialog.Close>
                );
              })}
            </Dialog.Content>
          </Dialog.Portal>
        </Dialog.Root>
      </nav>
    </div>
  );
}

function NavButton({
  active,
  item,
  onNavigate,
}: {
  active: boolean;
  item: (typeof primaryItems)[number] | (typeof secondaryItems)[number];
  onNavigate: (view: SecondLoopView) => void;
}): JSX.Element {
  const { t } = useI18n();
  const Icon = item.icon;
  return (
    <button
      aria-current={active ? "page" : undefined}
      className="secondloop-nav-item"
      onClick={() => onNavigate(item.view)}
      type="button"
    >
      <Icon aria-hidden="true" size={18} />
      <span>{t(item.key)}</span>
    </button>
  );
}
