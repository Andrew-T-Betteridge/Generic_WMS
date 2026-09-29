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
  title, count, actions, children, flush = false, id,
}: { title?: ReactNode; count?: number; actions?: ReactNode; children: ReactNode; flush?: boolean; id?: string }) {
  return (
    <section className={`ui-panel ${flush ? "ui-flush" : ""}`} aria-labelledby={id} >
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
