import type { ReactNode } from "react";

export function PageHeader({
  title, description, actions, meta,
}: { title: ReactNode; description?: ReactNode; actions?: ReactNode; meta?: ReactNode }) {
  return (
    <header className="ui-page-header">
      <div className="ui-page-title">
        <h1>{title}</h1>
        {meta && <div className="ui-page-meta">{meta}</div>}
        {description && <p>{description}</p>}
      </div>
      {actions && <div className="ui-page-actions">{actions}</div>}
    </header>
  );
}

export function Panel({
  title, count, actions, children, flush = false, id, tone,
}: { title?: ReactNode; count?: number; actions?: ReactNode; children: ReactNode; flush?: boolean; id?: string; tone?: "bad" }) {
  return (
    <section className={`ui-panel ${flush ? "ui-flush" : ""} ${tone ? `ui-tone-${tone}` : ""}`} aria-labelledby={id}>
      {(title || actions) && (
        <div className="ui-panel-head">
          {title && <h2 id={id}>{title}{count !== undefined && <span className="ui-count">{count}</span>}</h2>}
          {actions && <div className="ui-panel-actions">{actions}</div>}
        </div>
      )}
      <div className="ui-panel-body">{children}</div>
    </section>
  );
}

export type Tone = "neutral" | "good" | "warn" | "bad" | "info";

export function MetricCard({
  label, value, tone = "neutral", hint, to,
}: { label: string; value: ReactNode; tone?: Tone; hint?: ReactNode; to?: ReactNode }) {
  return (
    <div className={`ui-metric ui-tone-${tone}`}>
      <span className="ui-metric-label">{label}</span>
      <strong className="ui-metric-value">{value}</strong>
      {hint && <span className="ui-metric-hint">{hint}</span>}
      {to}
    </div>
  );
}

/** Label/value pairs for record summaries. Empty values render as an em dash. */
export function KeyValues({ items }: { items: [string, ReactNode][] }) {
  return (
    <dl className="ui-kv">
      {items.map(([k, v]) => (
        <div key={k}><dt>{k}</dt><dd>{v === "" || v === null || v === undefined ? "—" : v}</dd></div>
      ))}
    </dl>
  );
}

export function Reference({ children }: { children: ReactNode }) {
  return <code className="ui-ref">{children}</code>;
}

/** Named group of metrics, e.g. "Needs attention" or "Today". */
export function MetricGroup({ label, children }: { label: string; children: ReactNode }) {
  return (
    <section className="ui-metric-group" aria-label={label}>
      <h2 className="ui-section-label">{label}</h2>
      <div className="ui-metrics">{children}</div>
    </section>
  );
}

/** One-line operational status. Tone is chosen by the caller from backend-supplied counts. */
export function StatusBanner({ tone, title, children, actions }: { tone: Tone; title: string; children?: ReactNode; actions?: ReactNode }) {
  return (
    <div className={`ui-banner ui-tone-${tone}`} role="status">
      <i className="ui-banner-dot" aria-hidden="true" />
      <div><strong>{title}</strong>{children && <> <span>{children}</span></>}</div>
      {actions && <div className="ui-banner-actions">{actions}</div>}
    </div>
  );
}

export type TabItem = { id: string; label: string; count?: number };

/** Accessible tab strip; the caller renders the selected panel. */
export function Tabs({ tabs, value, onChange, label }: { tabs: TabItem[]; value: string; onChange: (id: string) => void; label: string }) {
  return (
    <div className="ui-tabs" role="tablist" aria-label={label}
      onKeyDown={(e) => {
        if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
        const i = tabs.findIndex((t) => t.id === value);
        const next = tabs[(i + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length];
        onChange(next.id);
        (e.currentTarget.querySelector(`[data-tab="${next.id}"]`) as HTMLElement | null)?.focus();
      }}>
      {tabs.map((t) => (
        <button key={t.id} type="button" role="tab" data-tab={t.id} className="ui-tab" aria-selected={t.id === value} tabIndex={t.id === value ? 0 : -1} onClick={() => onChange(t.id)}>
          {t.label}{t.count !== undefined && <span className="ui-count">{t.count}</span>}
        </button>
      ))}
    </div>
  );
}

/**
 * Confirmation for actions that change operational state. `danger` uses the
 * destructive button treatment. Escape and the backdrop cancel.
 */
export function ConfirmDialog({
  title, children, confirmLabel, danger = false, onConfirm, onCancel,
}: { title: string; children?: ReactNode; confirmLabel: string; danger?: boolean; onConfirm: () => void; onCancel: () => void }) {
  return (
    <div className="ui-dialog-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onCancel(); }}
      onKeyDown={(e) => { if (e.key === "Escape") onCancel(); }}>
      <div className="ui-dialog" role="alertdialog" aria-modal="true" aria-labelledby="ui-confirm-title">
        <h2 id="ui-confirm-title">{title}</h2>
        {children && <p>{children}</p>}
        <footer>
          <button type="button" className="btn ghost" onClick={onCancel} autoFocus>Keep as is</button>
          <button type="button" className={`btn ${danger ? "danger-solid" : ""}`} onClick={onConfirm}>{confirmLabel}</button>
        </footer>
      </div>
    </div>
  );
}
