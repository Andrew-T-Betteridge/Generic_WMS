import { Link } from "react-router";
import { api, dt, money, num, type Obj, type Token } from "../../admin-api";
import { field, fieldText, label, relativeAge } from "../../lib/format";
import type { HasPermission } from "../../lib/permissions";
import { useApi } from "../../lib/use-api";
import { DataTable } from "../../ui/DataTable";
import { KeyValues, MetricCard, MetricGroup, PageHeader, Panel, StatusBanner } from "../../ui/layout";
import { EmptyState, ErrorState, LoadingState } from "../../ui/states";
import { EntityReference } from "../exceptions/ExceptionsPage";

// Presents GET /api/admin/operations/dashboard as returned. Every figure below
// is computed by the WMS service; nothing is re-aggregated in the browser.
type Dashboard = { summary?: Obj; topExceptions?: Obj[]; outstandingOrders?: Obj[] };

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

  const exceptionCount = n("exception_count");
  const failedNotifications = n("failed_notifications");
  const problems = [
    exceptionCount ? `${exceptionCount} open exception${exceptionCount === 1 ? "" : "s"}` : "",
    failedNotifications ? `${failedNotifications} failed notification${failedNotifications === 1 ? "" : "s"}` : "",
  ].filter(Boolean);

  return (
    <>
      <PageHeader
        title="Control centre"
        description="Operational position reported by the WMS, problems first."
        actions={<button type="button" className="btn ghost" onClick={refresh} disabled={ops.loading}>{ops.loading && ops.data ? "Refreshing…" : "Refresh"}</button>}
      />
      {ops.error ? <ErrorState error={ops.error} onRetry={ops.reload} /> : ops.loading && !ops.data ? <LoadingState label="Loading control centre" /> : (
        <>
          {problems.length
            ? <StatusBanner tone="bad" title="Attention needed" actions={has("exception.read") && exceptionCount ? <Link to="/exceptions" className="btn sm">Open exception queue</Link> : undefined}>{problems.join(" · ")}</StatusBanner>
            : <StatusBanner tone="good" title="No problems reported">The WMS reports no open exceptions or failed notifications.</StatusBanner>}
          <div className="ui-metric-groups">
            <MetricGroup label="Needs attention">
              <MetricCard label="Open exceptions" value={exceptionCount} tone={exceptionCount ? "bad" : "good"} to={link("/exceptions", has("exception.read"), "Review")} />
              <MetricCard label="Failed notifications" value={failedNotifications} tone={failedNotifications ? "bad" : "good"} to={link("/communications", has("notification.read"), "Review")} />
            </MetricGroup>
            <MetricGroup label="Work in progress">
              <MetricCard label="Open picks" value={n("open_picks")} tone={n("open_picks") ? "warn" : "neutral"} to={link("/fulfilment", has("pick.read") || has("shipment.read"), "Fulfilment")} />
              <MetricCard label="Open returns & claims" value={n("open_cases")} tone={n("open_cases") ? "warn" : "neutral"} to={link("/returns", has("return.read"), "Returns")} />
            </MetricGroup>
            <MetricGroup label="Today">
              <MetricCard label="Outstanding orders" value={n("outstanding_orders")} to={link("/orders?fulfilmentStatuses=UNALLOCATED,RESERVED,PART_ALLOCATED,ALLOCATED,PICKING,PART_PICKED,PICKED,PACKED", has("order.read"), "Orders")} />
              <MetricCard label="Payment exceptions" value={n("payment_attention")} tone={n("payment_attention") ? "warn" : "neutral"} to={link("/orders?payment=PENDING", has("order.read"), "Orders")} />
            </MetricGroup>
          </div>
          <div className="ui-grid-main">
            <Panel title="Oldest open exceptions" count={exceptions.length} flush tone={exceptions.length ? "bad" : undefined}
              actions={has("exception.read") ? <Link to="/exceptions" className="btn ghost sm">All exceptions</Link> : undefined}>
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
