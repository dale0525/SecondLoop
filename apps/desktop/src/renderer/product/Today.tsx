import {
  Badge,
  Button,
  Card,
  Checkbox,
  Dialog,
  Flex,
  Heading,
  Text,
  TextField,
} from "@radix-ui/themes";
import {
  BellRing,
  CalendarDays,
  Check,
  CircleAlert,
  LoaderCircle,
  Mail,
  Plus,
  ShieldCheck,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import {
  type FoundationScheduleRecord,
  type FoundationTaskRecord,
  type PendingFoundationAction,
  createFoundationSchedule,
  createFoundationTask,
  listFoundationActions,
  listFoundationSchedules,
  listFoundationTasks,
  listMailAccounts,
  setFoundationTaskStatus,
} from "../api";
import { useHostBootstrap } from "../hostBootstrap";
import { useI18n } from "../i18n/I18nProvider";

type SourceStatus = "ready" | "missing" | "error";

export function Today(): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const [actions, setActions] = useState<PendingFoundationAction[]>([]);
  const [tasks, setTasks] = useState<FoundationTaskRecord[]>([]);
  const [schedules, setSchedules] = useState<FoundationScheduleRecord[]>([]);
  const [sources, setSources] = useState<Record<"mail" | "tasks" | "scheduler", SourceStatus>>({
    mail: "missing",
    tasks: "missing",
    scheduler: "missing",
  });
  const [loading, setLoading] = useState(true);
  const [busyTask, setBusyTask] = useState<string | null>(null);
  const [captureOpen, setCaptureOpen] = useState(false);

  const load = async () => {
    setLoading(true);
    const results = await Promise.allSettled([
      bootstrap.features.actions ? listFoundationActions() : Promise.resolve([]),
      bootstrap.features.accounts ? listMailAccounts() : Promise.resolve([]),
      listFoundationTasks({ status: "open", limit: 100 }),
      listFoundationSchedules(50),
    ]);
    const [actionResult, mailResult, taskResult, scheduleResult] = results;
    if (actionResult.status === "fulfilled") setActions(actionResult.value);
    if (mailResult.status === "fulfilled") {
      setSources((current) => ({
        ...current,
        mail: mailResult.value.length > 0 ? "ready" : "missing",
      }));
    } else {
      setSources((current) => ({ ...current, mail: "error" }));
    }
    if (taskResult.status === "fulfilled") {
      setTasks(taskResult.value.tasks);
      setSources((current) => ({ ...current, tasks: "ready" }));
    } else {
      setSources((current) => ({ ...current, tasks: "error" }));
    }
    if (scheduleResult.status === "fulfilled") {
      setSchedules(scheduleResult.value);
      setSources((current) => ({ ...current, scheduler: "ready" }));
    } else {
      setSources((current) => ({ ...current, scheduler: "error" }));
    }
    setLoading(false);
  };

  useEffect(() => { void load(); }, [bootstrap.features.accounts, bootstrap.features.actions]);

  const pending = useMemo(
    () => actions.filter((item) => item.approval.status === "pending"),
    [actions],
  );
  const endOfToday = useMemo(() => {
    const value = new Date();
    value.setHours(23, 59, 59, 999);
    return value;
  }, []);
  const focusTasks = useMemo(
    () => tasks.filter((task) => (
      task.content.dueAt
      && new Date(task.content.dueAt) <= endOfToday
      && !task.content.tags.includes("commitment")
    )),
    [endOfToday, tasks],
  );
  const commitments = useMemo(
    () => tasks.filter((task) => task.content.tags.includes("commitment")),
    [tasks],
  );
  const todaySchedules = useMemo(
    () => schedules.filter((schedule) => (
      schedule.next_run_at
      && new Date(schedule.next_run_at) <= endOfToday
      && schedule.status !== "cancelled"
      && schedule.status !== "completed"
    )),
    [endOfToday, schedules],
  );
  const hasSourceError = Object.values(sources).some((status) => status === "error");
  const date = new Intl.DateTimeFormat(undefined, {
    day: "numeric",
    month: "long",
    weekday: "long",
  }).format(new Date());

  const completeTask = async (task: FoundationTaskRecord) => {
    setBusyTask(task.id);
    try {
      await setFoundationTaskStatus(task.id, task.version, "completed");
      setTasks((current) => current.filter((item) => item.id !== task.id));
    } catch {
      setSources((current) => ({ ...current, tasks: "error" }));
    } finally {
      setBusyTask(null);
    }
  };

  return (
    <main className="today-screen" aria-label={t("today.title")}>
      <header className="today-header">
        <div>
          <Text className="today-date" size="1" weight="bold">{date}</Text>
          <Heading as="h1">{t("today.title")}</Heading>
          <Text color="gray" size="2">{t("today.subtitle")}</Text>
        </div>
        <div className="today-header-actions">
          <Button className="today-capture-button" onClick={() => setCaptureOpen(true)}>
            <Plus size={17} /> {t("today.addTask")}
          </Button>
          <div className="today-source-list" aria-label={t("today.sourceCoverage")}>
            <SourcePill label={t("today.sourceMail")} status={sources.mail} />
            <SourcePill label={t("today.sourceTasks")} status={sources.tasks} />
            <SourcePill label={t("today.sourceScheduler")} status={sources.scheduler} />
          </div>
        </div>
      </header>
      {hasSourceError ? (
        <button className="today-error" onClick={() => void load()} type="button">
          <CircleAlert size={17} />
          <span>{t("today.sourcesUnavailable")} {t("today.retry")}.</span>
        </button>
      ) : null}
      <div className="today-grid">
        <section className="today-main-column">
          <TodaySection
            count={focusTasks.length + todaySchedules.length}
            icon={<CalendarDays size={17} />}
            title={t("today.focus")}
          >
            {loading ? <LoadingRows /> : focusTasks.length + todaySchedules.length > 0 ? (
              <div className="today-record-list">
                {focusTasks.map((task) => (
                  <TaskRow
                    busy={busyTask === task.id}
                    key={task.id}
                    onComplete={() => void completeTask(task)}
                    task={task}
                  />
                ))}
                {todaySchedules.map((schedule) => (
                  <ScheduleRow key={schedule.id} schedule={schedule} />
                ))}
              </div>
            ) : (
              <EmptyState action={t("today.addTask")} onAction={() => setCaptureOpen(true)} text={t("today.noItems")} />
            )}
          </TodaySection>
          <TodaySection icon={<Mail size={17} />} title={t("today.replies")}>
            <EmptyState
              text={sources.mail === "ready" ? t("today.noReplies") : t("today.mailNextStep")}
            />
          </TodaySection>
        </section>
        <aside className="today-side-column">
          <TodaySection count={pending.length} icon={<ShieldCheck size={17} />} title={t("today.approvals")}>
            {loading ? <LoadingRows compact /> : pending.length > 0 ? pending.map((item) => (
              <article className="today-action-row" key={item.approval.approval_id}>
                <span>
                  <strong>{item.preview?.subject || item.approval.binding.action_name}</strong>
                  <small>{item.approval.binding.resource_target}</small>
                </span>
                <Badge color="amber" radius="full">{t("today.pending")}</Badge>
              </article>
            )) : <EmptyState text={t("today.noApprovals")} />}
          </TodaySection>
          <TodaySection count={commitments.length} icon={<Check size={17} />} title={t("today.commitments")}>
            {commitments.length > 0 ? (
              <div className="today-record-list">
                {commitments.map((task) => (
                  <TaskRow
                    busy={busyTask === task.id}
                    key={task.id}
                    onComplete={() => void completeTask(task)}
                    task={task}
                  />
                ))}
              </div>
            ) : <EmptyState text={t("today.noCommitments")} />}
          </TodaySection>
        </aside>
      </div>
      <TaskCaptureDialog
        onCreated={() => void load()}
        onOpenChange={setCaptureOpen}
        open={captureOpen}
      />
    </main>
  );
}

function SourcePill({ label, status }: { label: string; status: SourceStatus }): JSX.Element {
  const { t } = useI18n();
  return (
    <span className={`today-source-state is-${status}`}>
      <i aria-hidden="true" />
      <Text size="1">{label} · {t(`today.sourceStatus.${status}`)}</Text>
    </span>
  );
}

function TaskRow({
  busy,
  onComplete,
  task,
}: {
  busy: boolean;
  onComplete: () => void;
  task: FoundationTaskRecord;
}): JSX.Element {
  const { t } = useI18n();
  return (
    <article className="today-record-row">
      <button
        aria-label={t("today.completeTask")}
        className="today-complete-task"
        disabled={busy}
        onClick={onComplete}
        type="button"
      >
        {busy ? <LoaderCircle className="spin" size={15} /> : <span />}
      </button>
      <span className="today-record-copy">
        <strong>{task.content.title}</strong>
        <small>{formatWhen(task.content.dueAt)} · {t("today.confirmedTask")}</small>
      </span>
      <Badge color={isOverdue(task) ? "red" : "green"} radius="full">
        {isOverdue(task) ? t("today.overdue") : t("today.confirmed")}
      </Badge>
    </article>
  );
}

function ScheduleRow({ schedule }: { schedule: FoundationScheduleRecord }): JSX.Element {
  const { t } = useI18n();
  return (
    <article className="today-record-row">
      <span className="today-schedule-mark"><BellRing size={15} /></span>
      <span className="today-record-copy">
        <strong>{schedule.request.name}</strong>
        <small>{formatWhen(schedule.next_run_at)} · {t("today.confirmedSchedule")}</small>
      </span>
      <Badge color={schedule.status === "paused" ? "gray" : "blue"} radius="full">
        {schedule.status === "paused" ? t("today.paused") : t("today.scheduled")}
      </Badge>
    </article>
  );
}

function TaskCaptureDialog({
  onCreated,
  onOpenChange,
  open,
}: {
  onCreated: () => void;
  onOpenChange: (open: boolean) => void;
  open: boolean;
}): JSX.Element {
  const { t } = useI18n();
  const [title, setTitle] = useState("");
  const [due, setDue] = useState(() => defaultDueTime());
  const [remind, setRemind] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [idempotencyKey, setIdempotencyKey] = useState(() => createIdempotencyKey());

  const changeOpen = (next: boolean) => {
    if (next && !open) {
      setTitle("");
      setDue(defaultDueTime());
      setRemind(true);
      setError(null);
      setIdempotencyKey(createIdempotencyKey());
    }
    onOpenChange(next);
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!title.trim()) return;
    setSaving(true);
    setError(null);
    try {
      const dueAt = due ? new Date(due).toISOString() : null;
      const task = await createFoundationTask({
        title: title.trim(),
        notes: null,
        dueAt,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        recurrence: null,
        priority: "normal",
        tags: [],
      }, idempotencyKey);
      if (remind && dueAt) {
        await createFoundationSchedule({
          name: title.trim(),
          schedule: { kind: "one_shot", at: dueAt },
          misfire: { kind: "fire_once" },
          payload: {
            result: { kind: "task_reminder", taskId: task.id },
            notifications: [{
              channel: "desktop",
              title: t("today.reminderTitle"),
              body: title.trim(),
              dedupeKey: `${idempotencyKey}:notification`,
              notBefore: dueAt,
              quietHours: null,
              data: { route: "today", taskId: task.id },
            }],
          },
          idempotencyKey: `${idempotencyKey}:schedule`,
        });
      }
      changeOpen(false);
      onCreated();
    } catch {
      setError(t("today.captureFailed"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog.Root onOpenChange={changeOpen} open={open}>
      <Dialog.Content className="today-capture-dialog" maxWidth="440px">
        <Dialog.Title>{t("today.captureTitle")}</Dialog.Title>
        <Dialog.Description>{t("today.captureDescription")}</Dialog.Description>
        <form className="today-capture-form" onSubmit={(event) => void submit(event)}>
          <label>
            <Text as="span" size="2" weight="medium">{t("today.taskTitle")}</Text>
            <TextField.Root
              autoFocus
              onChange={(event) => setTitle(event.currentTarget.value)}
              placeholder={t("today.taskPlaceholder")}
              value={title}
            />
          </label>
          <label>
            <Text as="span" size="2" weight="medium">{t("today.dueAt")}</Text>
            <TextField.Root
              onChange={(event) => setDue(event.currentTarget.value)}
              type="datetime-local"
              value={due}
            />
          </label>
          <label className="today-reminder-toggle">
            <Checkbox checked={remind} onCheckedChange={(checked) => setRemind(checked === true)} />
            <span><strong>{t("today.scheduleReminder")}</strong><small>{t("today.scheduleReminderHint")}</small></span>
          </label>
          {error ? <p className="today-capture-error" role="alert">{error}</p> : null}
          <Flex gap="3" justify="end" mt="2">
            <Dialog.Close><Button type="button" variant="soft">{t("today.cancel")}</Button></Dialog.Close>
            <Button disabled={saving || !title.trim()} type="submit">
              {saving ? <LoaderCircle className="spin" size={16} /> : <Check size={16} />}
              {saving ? t("today.saving") : t("today.saveTask")}
            </Button>
          </Flex>
        </form>
      </Dialog.Content>
    </Dialog.Root>
  );
}

function TodaySection({
  children,
  count,
  icon,
  title,
}: {
  children: React.ReactNode;
  count?: number;
  icon: React.ReactNode;
  title: string;
}): JSX.Element {
  return (
    <Card className="today-card" size="3">
      <Flex align="center" className="today-card-heading" gap="2">
        <span className="today-card-icon">{icon}</span>
        <Heading as="h2" size="3">{title}</Heading>
        {count !== undefined ? <Badge color="gray" ml="auto" radius="full">{count}</Badge> : null}
      </Flex>
      <div className="today-card-body">{children}</div>
    </Card>
  );
}

function LoadingRows({ compact = false }: { compact?: boolean }): JSX.Element {
  const { t } = useI18n();
  return (
    <div className="today-loading" role="status">
      <LoaderCircle className="spin" size={16} />
      <span>{compact ? t("today.checkingApprovals") : t("today.checkingSources")}</span>
    </div>
  );
}

function EmptyState({
  action,
  onAction,
  text,
}: {
  action?: string;
  onAction?: () => void;
  text: string;
}): JSX.Element {
  return (
    <div className="today-empty">
      <p>{text}</p>
      {action && onAction ? <Button onClick={onAction} size="1" variant="ghost">{action}</Button> : null}
    </div>
  );
}

function formatWhen(value?: string | null): string {
  if (!value) return "—";
  return new Intl.DateTimeFormat(undefined, {
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    month: "short",
  }).format(new Date(value));
}

function isOverdue(task: FoundationTaskRecord): boolean {
  return Boolean(task.content.dueAt && new Date(task.content.dueAt) < new Date());
}

function defaultDueTime(): string {
  const value = new Date(Date.now() + 60 * 60 * 1_000);
  value.setMinutes(0, 0, 0);
  const local = new Date(value.getTime() - value.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function createIdempotencyKey(): string {
  return typeof crypto.randomUUID === "function"
    ? `secondloop-task:${crypto.randomUUID()}`
    : `secondloop-task:${Date.now()}`;
}
