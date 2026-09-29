import { Link } from "react-router";
import { api, dt, money, num, type Obj, type Token } from "../../admin-api";
import { field, fieldText, label, relativeAge } from "../../lib/format";
import type { HasPermission } from "../../lib/permissions";
import { useApi } from "../../lib/use-api";
import { DataTable } from "../../ui/DataTable";
import { KeyValues, MetricCard, PageHeader, Panel } from "../../ui/layout";
import { EmptyState, ErrorState, LoadingState } from "../../ui/states";
import { EntityReference } from "../exceptions/ExceptionsPage";

// Presents GET /api/admin/operations/dashboard as returned. Every figure below
// is computed by the WMS service; nothing is re-aggregated in the browser.
type Dashboard = { summary?: Obj; topExceptions?: Obj[] };

export function ControlCentre({ token, has, environment }: { token: Token; has: HasPermission; environment: string }) {
  const ops = useApi(() => api<Dashboard>(token, "/api/admin/operations/dashboard"), "ops");
  const health = useApi(
    () => (has("system.read") ? api<Obj>(token, "/api/admin/system/health") : Promise.resolve(null)),
    `health-${has("system.read")}`,
  );

  const refresh = () => { ops.reload(); health.reload(); };
  const summary = ops.data?.summary ?? {};
  const exceptions = ops.data?.topExceptions ?? [];
  const n = (k: string) => num(field(summary, k));
  const link = (to: string, allowed: boolean, text: string) => (allowed ? <Link className="ui-metric-link" to={to}>{text} →</Link> : undefined);

  return (
    <>
      <PageHeader
        title="Control centre"
        description="Today's operational position and the oldest open problems."
        actions={<button type="button" className="btn ghost" onClick={refresh}>Refresh</button>}
      />
      {ops.error ? <ErrorState error={ops.error} onRetry={ops.reload} /> : ops.loading && !ops.data ? <LoadingState label="Loading control centre" /> : (
        <>
          <div className="ui-metrics">
            <MetricCard label="Open exceptions" value={n("exception_count")} tone={n("exception_count") ? "bad" : "good"} to={link("/exceptions", has("exception.read"), "Review")} />
            <MetricCard label="Failed notifications" value={n("failed_notifications")} tone={n("failed_notifications") ? "bad" : "good"} to={link("/communications", has("notification.read"), "Review")} />
            <MetricCard label="Open picks" value={n("open_picks")} tone={n("open_picks") ? "warn" : "neutral"} to={link("/fulfilment", has("pick.read") || has("shipment.read"), "Fulfilment")} />
            <MetricCard label="Open returns & claims" value={n("open_cases")} tone={n("open_cases") ? "warn" : "neutral"} to={link("/returns", has("return.read"), "Returns")} />
            <MetricCard label="Orders today" value={n("orders_today")} to={link("/orders", has("order.read"), "Orders")} />
            <MetricCard label="Paid revenue today" value={money(field(summary, "revenue_today"))} />
          </div>
          <div className="ui-grid-main">
            <Panel title="Oldest open exceptions" count={exceptions.length} flush
              actions={has("exception.read") ? <Link to="/exceptions" className="btn ghost">All exceptions</Link> : undefined}>
              {exceptions.length ? (
                <DataTable caption="Oldest open exceptions" rows={exceptions} rowKey={(r, i) => `${fieldText(r, "entity_id", "")}-${i}`} columns={[
                  { key: "age", header: "Age", width: "80px", cell: (r) => <strong className="ui-age">{relativeAge(field(r, "age_minutes"))}</strong> },
                  { key: "type", header: "Problem", cell: (r) => <span className="ui-badge ui-tone-bad">{label(field(r, "exception_type"))}</span> },
                  { key: "entity", header: "Record", cell: (r) => <EntityReference row={r} /> },
                  { key: "message", header: "What happened", cell: (r) => fieldText(r, "message") },
                ]} />
              ) : <EmptyState title="All clear">No open exceptions.</EmptyState>}
            </Panel>
            <Panel title="Service">
              {health.error ? <ErrorState error={health.error} onRetry={health.reload} compact />
                : !has("system.read") ? <KeyValues items={[["Environment", environment]]} />
                : health.loading ? <LoadingState />
                : <KeyValues items={[
                    ["Environment", environment],
                    ["Database time", dt(field(health.data, "databaseTime"))],
                    ["Exceptions", num(field((field(health.data, "operational") ?? {}) as Obj, "exceptions"))],
                    ["Processing errors (24h)", num(field((field(health.data, "operational") ?? {}) as Obj, "processing_errors_24h"))],
                  ]} />}
              {has("system.read") && <Link className="ui-metric-link" to="/system">System details →</Link>}
            </Panel>
          </div>
        </>
      )}
    </>
  );
}
