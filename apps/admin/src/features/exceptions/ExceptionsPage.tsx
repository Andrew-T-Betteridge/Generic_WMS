import { Link, useSearchParams } from "react-router";
import { api, query, type Obj, type Token } from "../../admin-api";
import { field, fieldText, label, relativeAge } from "../../lib/format";
import { useApi } from "../../lib/use-api";
import { DataTable } from "../../ui/DataTable";
import { PageHeader, Panel, Reference } from "../../ui/layout";
import { EmptyState, ErrorState, SkeletonRows } from "../../ui/states";
import { orderPath } from "../orders/OrdersPage";

// Types the previous Admin offered as filters for GET /api/admin/exceptions?type=.
export const EXCEPTION_TYPES = ["PAID_NOT_ALLOCATED", "OPEN_PICK", "FAILED_NOTIFICATION", "FAILED_ORDER_INTERFACE"];

/** Links an exception to the record page when one exists in the Admin. */
export function EntityReference({ row }: { row: Obj }) {
  const type = fieldText(row, "entity_type", "").toUpperCase();
  const id = fieldText(row, "entity_id", "");
  const ref = <Reference>{id || "—"}</Reference>;
  return (
    <div className="ui-cell-stack">
      {type === "ORDER" && id ? <Link to={orderPath(id)}>{ref}</Link> : ref}
      <small>{label(type)}</small>
    </div>
  );
}

export function ExceptionsPage({ token }: { token: Token }) {
  const [params, setParams] = useSearchParams();
  const type = params.get("type") ?? "";
  const path = "/api/admin/exceptions" + query({ type: type || undefined, limit: 250 });
  const { data, error, loading, reload } = useApi(() => api<Obj[]>(token, path), path);
  const rows = data ?? [];

  return (
    <>
      <PageHeader
        title="Exceptions"
        description="Operational problems reported by the WMS, oldest first. Resolve them in the area that owns the record."
        actions={<button type="button" className="btn ghost" onClick={reload}>Refresh</button>}
      />
      <Panel flush>
        <div className="ui-toolbar">
          <div className="ui-chips" role="group" aria-label="Exception type">
            {["", ...EXCEPTION_TYPES].map((t) => (
              <button key={t || "all"} type="button" aria-pressed={type === t} className={`ui-chip ${type === t ? "active" : ""}`}
                onClick={() => setParams(t ? { type: t } : {})}>
                {t ? label(t) : "All"}
              </button>
            ))}
          </div>
          {!loading && !error && <span className="ui-muted ui-push">{rows.length}{rows.length === 250 ? "+" : ""} open</span>}
        </div>
        {error ? <ErrorState error={error} onRetry={reload} />
          : loading ? <SkeletonRows columns={4} />
          : rows.length === 0 ? (
            type
              ? <EmptyState kind="no-results" title={`No ${label(type).toLowerCase()} exceptions`}>Choose another type or view all.</EmptyState>
              : <EmptyState title="No open exceptions">The WMS is not reporting any operational problems.</EmptyState>
          ) : (
            <DataTable caption="Exceptions" rows={rows}
              rowKey={(r, i) => `${fieldText(r, "exception_type")}-${fieldText(r, "entity_id", "")}-${i}`}
              columns={[
                { key: "age", header: "Age", width: "90px", cell: (r) => <strong className="ui-age">{relativeAge(field(r, "age_minutes"))}</strong> },
                { key: "type", header: "Problem", cell: (r) => <span className="ui-badge ui-tone-bad">{label(field(r, "exception_type"))}</span> },
                { key: "entity", header: "Affected record", cell: (r) => <EntityReference row={r} /> },
                {
                  key: "message", header: "What happened", cell: (r) => {
                    const detail = field(r, "detail");
                    const hasDetail = detail && typeof detail === "object" && Object.keys(detail as object).length > 0;
                    return (
                      <div className="ui-cell-stack">
                        <span>{fieldText(r, "message")}</span>
                        {hasDetail ? <details className="ui-technical"><summary>Detail</summary><code>{JSON.stringify(detail)}</code></details> : null}
                      </div>
                    );
                  },
                },
              ]} />
          )}
      </Panel>
    </>
  );
}
