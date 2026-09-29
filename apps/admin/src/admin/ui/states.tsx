import type { ReactNode } from "react";
import { Link } from "react-router";
import { describeError } from "../lib/api-errors";

export function LoadingState({ label = "Loading" }: { label?: string }) {
  return (
    <div className="ui-state ui-loading" role="status" aria-live="polite">
      <i aria-hidden="true" />
      <span>{label}…</span>
    </div>
  );
}

/** Table-shaped placeholder so the layout does not jump while rows load. */
export function SkeletonRows({ rows = 6, columns = 5 }: { rows?: number; columns?: number }) {
  return (
    <div className="ui-skeleton" role="status" aria-label="Loading">
      {Array.from({ length: rows }, (_, r) => (
        <div className="ui-skeleton-row" key={r}>
          {Array.from({ length: columns }, (_, c) => <span key={c} />)}
        </div>
      ))}
    </div>
  );
}

/**
 * `kind="no-results"` means filters excluded everything;
 * `kind="empty"` means the dataset itself is empty.
 */
export function EmptyState({
  title, children, kind = "empty", action,
}: { title: string; children?: ReactNode; kind?: "empty" | "no-results"; action?: ReactNode }) {
  return (
    <div className={`ui-state ui-empty ui-empty-${kind}`} data-kind={kind}>
      <strong>{title}</strong>
      {children && <p>{children}</p>}
      {action}
    </div>
  );
}

export function ErrorState({ error, onRetry, compact = false }: { error: unknown; onRetry?: () => void; compact?: boolean }) {
  const d = describeError(error);
  return (
    <div className={`ui-state ui-error ui-error-${d.kind} ${compact ? "ui-compact" : ""}`} role="alert" data-kind={d.kind}>
      <strong>{d.title}</strong>
      <p>{d.message}</p>
      <div className="ui-state-actions">
        {onRetry && d.kind !== "forbidden" && d.kind !== "not-found" && (
          <button type="button" className="btn ghost" onClick={onRetry}>Try again</button>
        )}
        {d.kind === "unauthenticated" && (
          <button type="button" className="btn" onClick={() => window.location.reload()}>Sign in again</button>
        )}
        {(d.kind === "forbidden" || d.kind === "not-found") && !compact && (
          <Link className="btn ghost" to="/">Go to start</Link>
        )}
      </div>
      <details className="ui-technical">
        <summary>Technical details</summary>
        <code>{d.technical}</code>
      </details>
    </div>
  );
}
