import * as Dialog from "@radix-ui/react-dialog";
import { Badge, Button, Card, Flex, Heading, Text, TextField } from "@radix-ui/themes";
import { Brain, Download, LoaderCircle, Search, ShieldAlert, Trash2, X } from "lucide-react";
import { FormEvent, useEffect, useMemo, useState } from "react";

import { MemoryRecord, exportMemories, forgetMemory, listMemories } from "../api";
import { useI18n } from "../i18n/I18nProvider";
import { FoundationHeader } from "./Accounts";

type MemoryProps = { embedded?: boolean; onBack: () => void };

export function Memory({ embedded = false, onBack }: MemoryProps): JSX.Element {
  const { t } = useI18n();
  const [records, setRecords] = useState<MemoryRecord[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [forgetting, setForgetting] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [detailOpen, setDetailOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const Root = embedded ? "section" : "main";

  const selected = useMemo(
    () => records.find((record) => record.id === selectedId) ?? null,
    [records, selectedId]
  );

  const load = async (nextQuery = query) => {
    setLoading(true);
    setError(null);
    try {
      const next = await listMemories(nextQuery);
      setRecords(next);
      setSelectedId((current) => next.some((record) => record.id === current) ? current : next[0]?.id ?? null);
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(""); }, []);

  const submitSearch = (event: FormEvent) => {
    event.preventDefault();
    void load(query);
  };

  const forget = async () => {
    if (!selected) return;
    setForgetting(true);
    setError(null);
    try {
      await forgetMemory(selected.id, selected.version);
      setConfirmOpen(false);
      await load(query);
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setForgetting(false);
    }
  };

  const exportLedger = async () => {
    try {
      const value = await exportMemories();
      const url = URL.createObjectURL(new Blob([JSON.stringify(value, null, 2)], { type: "application/json" }));
      const link = document.createElement("a");
      link.href = url;
      link.download = `agentweave-memory-${new Date().toISOString().slice(0, 10)}.json`;
      link.click();
      URL.revokeObjectURL(url);
    } catch (reason) {
      setError(errorMessage(reason));
    }
  };

  return (
    <Root className="foundation-screen" aria-label="Memory ledger">
      {embedded ? <header className="product-page-header"><Text className="foundation-kicker" size="1" weight="bold">PERSONAL CONTEXT</Text><Heading as="h1">{t("nav.memory")}</Heading><Text color="gray" size="2">Inspectable, sourced, and forgettable.</Text></header> : <FoundationHeader eyebrow="PERSONAL CONTEXT" onBack={onBack} subtitle="Inspectable, sourced, and forgettable" title="Memory ledger" />}
      <div className="memory-toolbar">
        <form onSubmit={submitSearch} role="search">
          <TextField.Root aria-label="Search committed memories" onChange={(event) => setQuery(event.target.value)} placeholder="Search preferences, people, or projects" value={query}>
            <TextField.Slot><Search aria-hidden="true" size={15} /></TextField.Slot>
          </TextField.Root>
        </form>
        <Button onClick={() => void exportLedger()} variant="soft"><Download aria-hidden="true" size={15} /> Export</Button>
      </div>
      {error ? <div className="memory-error" role="alert"><ShieldAlert size={16} /> {error}</div> : null}
      <div className="foundation-page-shell memory-layout">
        <section className="foundation-list-column memory-list" aria-label="Committed memories">
          <div className="foundation-column-heading"><Text color="gray" size="1" weight="bold">COMMITTED LEDGER</Text><Badge color="gray" radius="full">{records.length}</Badge></div>
          {loading ? <Flex align="center" gap="2" p="4"><LoaderCircle className="spin" size={16} /><Text color="gray" size="2">Searching scoped memory</Text></Flex> : null}
          {!loading && !error && records.length === 0 ? (
            <Card className="foundation-empty"><Flex align="center" direction="column" gap="2"><Brain size={22} /><Text weight="bold">Nothing committed here</Text><Text align="center" color="gray" size="2">Proposals appear only after confirmation. Try a different query or ask the Agent to remember a preference.</Text></Flex></Card>
          ) : null}
          {records.map((record) => (
            <button aria-pressed={selectedId === record.id} className="memory-list-item" key={record.id} onClick={() => { setSelectedId(record.id); setDetailOpen(true); }} type="button">
              <span className="memory-kind">{kindLabel(record.kind)}</span>
              <strong>{record.value.text}</strong>
              <small>{formatDate(record.updatedAt)} · v{record.version}</small>
            </button>
          ))}
        </section>
        <section className="foundation-detail-column memory-detail" aria-live="polite">
          {selected ? <MemoryDetail onForget={() => setConfirmOpen(true)} record={selected} /> : null}
        </section>
      </div>
      <Dialog.Root onOpenChange={setDetailOpen} open={detailOpen}>
        <Dialog.Portal>
          <Dialog.Overlay className="foundation-dialog-overlay memory-mobile-detail" />
          <Dialog.Content className="foundation-dialog-content memory-mobile-detail memory-mobile-detail-content">
            <Dialog.Title className="sr-only">Memory details</Dialog.Title>
            <Dialog.Close asChild><button aria-label="Close memory details" className="dialog-close mobile-detail-close" type="button"><X size={16} /></button></Dialog.Close>
            {selected ? <MemoryDetail onForget={() => { setDetailOpen(false); setConfirmOpen(true); }} record={selected} /> : null}
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
      <Dialog.Root onOpenChange={setConfirmOpen} open={confirmOpen}>
        <Dialog.Portal>
          <Dialog.Overlay className="foundation-dialog-overlay" />
          <Dialog.Content className="foundation-dialog-content">
            <Flex align="start" justify="between" gap="3"><div><Dialog.Title className="foundation-dialog-title">Forget this memory?</Dialog.Title><Dialog.Description className="foundation-dialog-description">The value and evidence will be scrubbed and removed from derived search. A non-sensitive tombstone remains for audit.</Dialog.Description></div><Dialog.Close asChild><button aria-label="Close confirmation" className="dialog-close" type="button"><X size={16} /></button></Dialog.Close></Flex>
            <Card className="forget-preview"><Text size="2">{selected?.value.text}</Text></Card>
            <Flex className="forget-dialog-actions" justify="end"><Dialog.Close asChild><Button disabled={forgetting} variant="soft">Keep memory</Button></Dialog.Close><Button color="red" disabled={forgetting} onClick={() => void forget()}><Trash2 size={15} />{forgetting ? "Forgetting…" : "Forget permanently"}</Button></Flex>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </Root>
  );
}

function MemoryDetail({ onForget, record }: { onForget: () => void; record: MemoryRecord }): JSX.Element {
  return (
    <Card className="foundation-detail-card memory-detail-card" size="4">
      <Flex align="start" justify="between" gap="4" wrap="wrap"><div><Text className="foundation-kicker" size="1" weight="bold">{kindLabel(record.kind)}</Text><Heading as="h2" mt="2" size="6">{record.value.text}</Heading></div><Badge color={sensitivityColor(record.sensitivity)} radius="full">{record.sensitivity}</Badge></Flex>
      <div className="foundation-rule" />
      <dl className="foundation-facts"><Fact label="Confidence" value={`${Math.round(record.confidence / 100)}%`} /><Fact label="Version" value={`v${record.version}`} /><Fact label="Retention" value={record.retention.mode} /><Fact label="Updated" value={formatDate(record.updatedAt)} /></dl>
      {Object.keys(record.value.attributes).length > 0 ? <section className="memory-section"><Text size="2" weight="bold">Attributes</Text>{Object.entries(record.value.attributes).map(([key, value]) => <div className="memory-attribute" key={key}><span>{key}</span><strong>{value}</strong></div>)}</section> : null}
      <section className="memory-section"><Text size="2" weight="bold">Evidence &amp; provenance</Text>{record.evidence.map((evidence, index) => <div className="evidence-row" key={`${evidence.observedAt}-${index}`}><span className="evidence-mark" aria-hidden="true" /><div><strong>{sourceLabel(evidence.source)}</strong><small>{formatDate(evidence.observedAt)}{evidence.sourceId ? ` · ${evidence.sourceId}` : ""}</small>{evidence.excerpt ? <p>“{evidence.excerpt}”</p> : null}</div></div>)}</section>
      <Flex align="center" justify="between" gap="3" mt="5" wrap="wrap"><Text color="gray" size="2">ID {record.id.slice(0, 8)}…</Text><Button color="red" onClick={onForget} variant="soft"><Trash2 size={15} /> Forget</Button></Flex>
    </Card>
  );
}

function Fact({ label, value }: { label: string; value: string }): JSX.Element { return <div><dt>{label}</dt><dd>{value}</dd></div>; }
function kindLabel(value: string): string { return value.split(".").map((part) => part.replaceAll("_", " ")).join(" / "); }
function sourceLabel(value: string): string { return value.replaceAll("_", " ").replace(/^./, (letter) => letter.toUpperCase()); }
function formatDate(value: string): string { return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)); }
function sensitivityColor(value: string): "gray" | "amber" | "red" | "blue" { return value === "restricted" ? "red" : value === "sensitive" ? "amber" : value === "personal" ? "blue" : "gray"; }
function errorMessage(value: unknown): string { return value instanceof Error ? value.message : "Memory request failed"; }
