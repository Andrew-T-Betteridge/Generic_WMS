import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import { api, dt, money, num, query, type Obj, type Token } from "../../admin-api";
import { field, fieldText } from "../../lib/format";
import { useApi } from "../../lib/use-api";
import { DataTable, Pager, type Column } from "../../ui/DataTable";
import { PageHeader, Panel, Reference } from "../../ui/layout";
import { EmptyState, ErrorState, SkeletonRows } from "../../ui/states";
import { StatusBadge, toneFor } from "../../ui/StatusBadge";

// Filters accepted by GET /api/admin/orders (admin-operations.ts):
//   q (order ID / customer ID / email, partial), paymentStatus, fulfilmentStatus, limit, offset.
// The option lists are the values the previous Admin already offered.
export const PAYMENT_STATUSES = ["PAID", "PENDING", "AUTHORISED", "PART_REFUNDED", "REFUNDED", "FAILED"];
export const FULFILMENT_STATUSES = ["UNALLOCATED", "RESERVED", "PART_ALLOCATED", "ALLOCATED", "PICKING", "PART_PICKED", "PICKED", "PACKED", "SHIPPED", "DELIVERED", "CANCELLED"];
const OPEN_STATUSES = ["UNALLOCATED","RESERVED","PART_ALLOCATED","ALLOCATED","PICKING","PART_PICKED","PICKED","PACKED"];
const ORDER_PRESETS: Record<string,string[]> = {
  OPEN: OPEN_STATUSES,
  READY_TO_PICK: ["ALLOCATED"],
  IN_PROGRESS: ["PICKING","PART_PICKED","PICKED","PACKED"],
  COMPLETED: ["SHIPPED","DELIVERED"],
  CANCELLED: ["CANCELLED"],
  ALL: []
};
export const ORDERS_PAGE_SIZE = 50;

export function orderPath(orderId: string) {
  return `/orders/${encodeURIComponent(orderId)}`;
}

export function OrdersPage({ token }: { token: Token }) {
  const [params, setParams] = useSearchParams();
  const navigate = useNavigate();
  const q = params.get("q") ?? "";
  const payment = params.get("payment") ?? "";
  const fulfilmentRaw = params.get("fulfilmentStatuses") ?? params.get("fulfilment") ?? "";
  const fulfilmentStatuses = fulfilmentRaw ? fulfilmentRaw.split(",").map((s) => s.trim().toUpperCase()).filter(Boolean) : OPEN_STATUSES;
  const fulfilmentKey = fulfilmentStatuses.join(",");
  const page = Math.max(0, Number(params.get("page") ?? 0) || 0);
  const [draft, setDraft] = useState(q);

  useEffect(() => setDraft(q), [q]);

  function update(next: Record<string, string>) {
    const p = new URLSearchParams(params);
    for (const [k, v] of Object.entries(next)) (v ? p.set(k, v) : p.delete(k));
    if (!("page" in next)) p.delete("page");
    setParams(p);
  }

  // Search is submitted after a short pause so typing does not flood the API.
  useEffect(() => {
    if (draft === q) return;
    const t = setTimeout(() => update({ q: draft.trim() }), 350);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draft]);

  const path = "/api/admin/orders" + query({
    q: q || undefined,
    paymentStatus: payment || undefined,
    fulfilmentStatuses: fulfilmentStatuses.length ? fulfilmentKey : undefined,
    limit: ORDERS_PAGE_SIZE,
    offset: page * ORDERS_PAGE_SIZE || undefined,
  });
  const { data, error, loading, reload } = useApi(() => api<Obj[]>(token, path), path);
  const rows = data ?? [];
  const filtered = !!(q || payment || fulfilmentKey);

  const columns: Column<Obj>[] = [
    {
      key: "order", header: "Order", cell: (r) => (
        <div className="ui-cell-stack">
          <Link to={orderPath(fieldText(r, "order_id", ""))} onClick={(e) => e.stopPropagation()}><Reference>{fieldText(r, "order_id")}</Reference></Link>
          <small>{dt(field(r, "order_date"))}</small>
        </div>
      ),
    },
    {
      key: "customer", header: "Customer", cell: (r) => (
        <div className="ui-cell-stack">
          <span className="ui-strong">{fieldText(r, "contact_email", fieldText(r, "customer_id"))}</span>
          {field(r, "contact_email") && field(r, "customer_id") ? <small>{fieldText(r, "customer_id")}</small> : null}
        </div>
      ),
    },
    { key: "payment", header: "Payment", cell: (r) => <StatusBadge status={field(r, "payment_status")} /> },
    { key: "fulfilment", header: "Fulfilment", cell: (r) => <StatusBadge status={field(r, "fulfilment_status") ?? field(r, "derived_status")} /> },
    {
      key: "progress", header: "Picked", align: "right", cell: (r) => {
        const ordered = num(field(r, "qty_ordered")), picked = num(field(r, "qty_picked"));
        const pct = ordered ? Math.min(100, (picked / ordered) * 100) : 0;
        return <span className="ui-progress" title={`${picked} of ${ordered} units picked`}><span className={`ui-bar ${ordered && picked >= ordered ? "done" : ""}`} aria-hidden="true"><i style={{ width: `${pct}%` }} /></span>{picked}/{ordered}</span>;
      },
    },
    { key: "picks", header: "Open picks", align: "right", cell: (r) => { const n = num(field(r, "open_pick_tasks")); return n ? <strong>{n}</strong> : <span className="ui-muted">0</span>; } },
    { key: "value", header: "Value", align: "right", cell: (r) => <span className="ui-strong">{money(field(r, "order_value"))}</span> },
  ];

  return (
    <>
      <PageHeader
        title="Orders"
        description="Search, filter and open orders. Orders with a failed or cancelled status are marked in red."
        actions={<button type="button" className="btn ghost" onClick={reload} disabled={loading}>Refresh</button>}
      />
      <Panel flush>
        <form className="ui-toolbar" role="search" onSubmit={(e) => { e.preventDefault(); update({ q: draft.trim() }); }}>
          <label className="ui-field ui-grow">
            <span>Search</span>
            <input className="input" type="search" value={draft} onChange={(e) => setDraft(e.target.value)} placeholder="Order ID, customer ID or email" aria-label="Search orders" />
          </label>
          <label className="ui-field">
            <span>Payment</span>
            <select className="input" aria-label="Payment status" value={payment} onChange={(e) => update({ payment: e.target.value })}>
              <option value="">Any</option>
              {PAYMENT_STATUSES.map((s) => <option key={s} value={s}>{s.replaceAll("_", " ")}</option>)}
            </select>
          </label>
          <div className="ui-filter-group">
  <span>Fulfilment</span>
  <div className="toolbar" style={{gap:6,flexWrap:"wrap"}}>
    {Object.entries(ORDER_PRESETS).map(([name,statuses])=>{
      const active=statuses.length===fulfilmentStatuses.length&&statuses.every((s)=>fulfilmentStatuses.includes(s));
      return <button
        key={name}
        type="button"
        className={`btn ${active?"btn-primary":"btn-ghost"}`}
        onClick={()=>update({fulfilmentStatuses:statuses.join(",")})}
      >{name.replaceAll("_"," ")}</button>;
    })}
  </div>
  <div className="toolbar" style={{gap:8,flexWrap:"wrap"}}>
    {FULFILMENT_STATUSES.map((status)=>{
      const checked=fulfilmentStatuses.includes(status);
      return <label key={status} style={{display:"inline-flex",alignItems:"center",gap:4,fontSize:12}}>
        <input
          type="checkbox"
          checked={checked}
          onChange={()=>{
            const next=checked?fulfilmentStatuses.filter((s)=>s!==status):[...fulfilmentStatuses,status];
            update({fulfilmentStatuses:next.join(",")});
          }}
        />
        {status.replaceAll("_"," ")}
      </label>;
    })}
  </div>
</div>
          {filtered && <button type="button" className="btn ghost ui-clear" onClick={() => { setDraft(""); setParams(new URLSearchParams()); }}>Clear all</button>}
        </form>
        {!error && (
          <div className="ui-resultbar" aria-live="polite">
            {loading ? <span>Loading orders…</span> : <span><strong>{rows.length ? `${page * ORDERS_PAGE_SIZE + 1}–${page * ORDERS_PAGE_SIZE + rows.length}` : "0"}</strong> {rows.length === 1 ? "order" : "orders"}{rows.length === ORDERS_PAGE_SIZE ? " on this page" : ""}</span>}
            {q && <FilterTag label={`Search: ${q}`} onRemove={() => { setDraft(""); update({ q: "" }); }} />}
            {payment && <FilterTag label={`Payment: ${payment.replaceAll("_", " ")}`} onRemove={() => update({ payment: "" })} />}
            {fulfilmentStatuses.length > 0 && <FilterTag label={`Fulfilment: ${fulfilmentStatuses.join(", ").replaceAll("_", " ")}`} onRemove={() => update({ fulfilmentStatuses: "" })} />}
          </div>
        )}
        {error ? <ErrorState error={error} onRetry={reload} />
          : loading ? <SkeletonRows columns={7} />
          : rows.length === 0 ? (
            filtered
              ? <EmptyState kind="no-results" title="No orders match these filters">Change the search or filters to widen the results.</EmptyState>
              : <EmptyState title="No orders yet">Orders will appear here when they are received by the WMS.</EmptyState>
          ) : (
            <>
              <DataTable
                caption="Orders"
                rows={rows}
                columns={columns}
                rowKey={(r, i) => fieldText(r, "order_id", String(i))}
                rowTone={(r) => (toneFor(field(r, "payment_status")) === "bad" || toneFor(field(r, "fulfilment_status") ?? field(r, "derived_status")) === "bad" ? "bad" : undefined)}
                rowLabel={(r) => `Open order ${fieldText(r, "order_id")}`}
                onRowClick={(r) => navigate(orderPath(fieldText(r, "order_id", "")))}
              />
              <Pager page={page} pageSize={ORDERS_PAGE_SIZE} rowCount={rows.length} onPage={(p) => update({ page: p ? String(p) : "" })} />
            </>
          )}
      </Panel>
    </>
  );
}

export function FilterTag({ label, onRemove }: { label: string; onRemove: () => void }) {
  return (
    <span className="ui-filter-tag">{label}<button type="button" aria-label={`Remove filter ${label}`} onClick={onRemove}>×</button></span>
  );
}
