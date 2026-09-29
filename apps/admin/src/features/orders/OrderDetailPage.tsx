import { useState } from "react";
import { Link, useParams } from "react-router";
import { api, bool, dt, get, money, num, txt, type Obj, type Token } from "../../admin-api";
import { OrderAmendModal, OrderCancelModal, OrderNoteModal } from "../../control-plane";
import { field, fieldText, label } from "../../lib/format";
import type { HasPermission } from "../../lib/permissions";
import { useApi } from "../../lib/use-api";
import { DataTable } from "../../ui/DataTable";
import { KeyValues, PageHeader, Panel, Reference } from "../../ui/layout";
import { EmptyState, ErrorState, LoadingState } from "../../ui/states";
import { StatusBadge } from "../../ui/StatusBadge";

// Shape of GET /api/admin/orders/:orderId/actions. The WMS service decides
// whether each action is allowed and which permission it needs.
export type BackendAction = { allowed?: unknown; permission?: unknown; reason?: unknown; refundRecommended?: unknown };
export type OrderActions = Partial<Record<"amendHeader" | "amendLines" | "allocate" | "deallocate" | "createPicks" | "cancel", BackendAction>>;

/** An action is offered only when the service allows it AND the user holds the permission it names. */
export function actionAvailable(action: BackendAction | undefined, has: HasPermission): boolean {
  return !!action && bool(action.allowed) && has(txt(action.permission, ""));
}

type Detail = {
  order?: Obj; lines?: Obj[]; allocations?: Obj[]; picks?: Obj[]; containers?: Obj[];
  shipmentManifest?: Obj[]; payments?: Obj[]; notes?: Obj[]; audit?: Obj[]; notifications?: Obj[];
};

const COMMANDS = [
  { key: "allocate", label: "Allocate", path: "allocate" },
  { key: "deallocate", label: "Deallocate", path: "deallocate" },
  { key: "createPicks", label: "Create picks", path: "create-picks" },
] as const;

export function OrderDetailPage({ token, has }: { token: Token; has: HasPermission }) {
  const orderId = useParams().orderId ?? "";
  const base = `/api/admin/orders/${encodeURIComponent(orderId)}`;
  const { data, error, loading, reload } = useApi(
    () => Promise.all([api<Detail>(token, base), api<OrderActions>(token, `${base}/actions`)]),
    base,
  );
  const [working, setWorking] = useState("");
  const [commandError, setCommandError] = useState<unknown>(null);
  const [dialog, setDialog] = useState<"note" | "cancel" | "amend" | null>(null);

  const back = <Link className="ui-back" to="/orders">← Orders</Link>;
  if (error) return <>{back}<PageHeader title={<>Order <Reference>{orderId}</Reference></>} /><ErrorState error={error} onRetry={reload} /></>;
  if (loading && !data) return <>{back}<PageHeader title={<>Order <Reference>{orderId}</Reference></>} /><LoadingState label="Loading order" /></>;
  if (!data) return null;

  const [detail, actions] = data;
  const order = detail.order ?? {};
  const lines = detail.lines ?? [];
  const currency = txt(get(order, "inv_currency", "INV_CURRENCY", "currency", "CURRENCY"), "GBP");

  async function command(path: string, name: string) {
    setWorking(name); setCommandError(null);
    try { await api(token, `${base}/${path}`, { method: "POST", body: "{}" }); reload(); }
    catch (e) { setCommandError(e); }
    finally { setWorking(""); }
  }

  const available = COMMANDS.filter((c) => actionAvailable(actions[c.key], has));
  const canAmend = actionAvailable(actions.amendHeader, has);
  const canCancel = actionAvailable(actions.cancel, has);
  const canNote = has("order.note");
  const noActions = !available.length && !canAmend && !canCancel && !canNote;
  const cancelBlocked = actions.cancel && !bool(actions.cancel.allowed) ? txt(actions.cancel.reason, "") : "";

  return (
    <>
      {back}
      <PageHeader
        title={<>Order <Reference>{fieldText(order, "order_id", orderId)}</Reference></>}
        meta={<>
          <StatusBadge status={field(order, "payment_status")} />
          <StatusBadge status={field(order, "fulfilment_status")} />
          <span className="ui-muted">Ordered {dt(field(order, "order_date"))}</span>
        </>}
        actions={<button type="button" className="btn ghost" onClick={reload} disabled={loading}>Refresh</button>}
      />

      <section className="ui-actionbar" aria-label="Order actions">
        {available.map((c) => (
          <button key={c.key} type="button" className="btn" disabled={!!working} onClick={() => void command(c.path, c.label)}>
            {working === c.label ? "Working…" : c.label}
          </button>
        ))}
        {canAmend && <button type="button" className="btn ghost" onClick={() => setDialog("amend")}>Amend details</button>}
        {canNote && <button type="button" className="btn ghost" onClick={() => setDialog("note")}>Add note</button>}
        {canCancel && <button type="button" className="btn danger" onClick={() => setDialog("cancel")}>Cancel order</button>}
        {noActions && <span className="ui-muted">No actions are available for this order with your access.</span>}
        {cancelBlocked && <span className="ui-muted">Cancel unavailable: {cancelBlocked}</span>}
      </section>
      {commandError ? <ErrorState error={commandError} compact /> : null}

      <div className="ui-summary">
        <div><span>Order value</span><strong>{money(field(order, "order_value"), currency)}</strong></div>
        <div><span>Lines</span><strong>{lines.length}</strong></div>
        <div><span>Priority</span><strong>{fieldText(order, "priority")}</strong></div>
        <div><span>Ship by</span><strong>{dt(field(order, "ship_by_date"))}</strong></div>
      </div>

      <div className="ui-grid-3">
        <Panel title="Customer">
          <KeyValues items={[
            ["Name", fieldText(order, "name", fieldText(order, "contact", ""))],
            ["Email", fieldText(order, "contact_email", "")],
            ["Phone", txt(get(order, "contact_phone", "CONTACT_PHONE", "contact_mobile", "CONTACT_MOBILE"), "")],
            ["Customer ID", fieldText(order, "customer_id", "")],
          ]} />
        </Panel>
        <Panel title="Delivery address">
          <address className="ui-address">
            {["address1", "address2", "town", "county", "postcode", "country"].map((k) => fieldText(order, k, "")).filter(Boolean).map((l, i) => <span key={i}>{l}</span>)}
          </address>
        </Panel>
        <Panel title="Shipping">
          <KeyValues items={[
            ["Dispatch method", fieldText(order, "dispatch_method", "")],
            ["Carrier", fieldText(order, "carrier_id", "")],
            ["Service", fieldText(order, "service_level", "")],
          ]} />
        </Panel>
      </div>

      <Panel title="Order lines" count={lines.length} flush>
        {lines.length ? (
          <DataTable caption="Order lines" rows={lines} rowKey={(l, i) => fieldText(l, "line_id", String(i))} columns={[
            { key: "line", header: "Line", cell: (l) => fieldText(l, "line_id") },
            { key: "sku", header: "SKU", cell: (l) => <Reference>{fieldText(l, "sku_id")}</Reference> },
            { key: "ordered", header: "Ordered", align: "right", cell: (l) => num(field(l, "qty_ordered")) },
            { key: "picked", header: "Picked", align: "right", cell: (l) => num(field(l, "qty_picked")) },
            { key: "shipped", header: "Shipped", align: "right", cell: (l) => num(field(l, "qty_shipped")) },
            { key: "notes", header: "Notes", cell: (l) => fieldText(l, "notes", "") },
          ]} />
        ) : <EmptyState title="No lines on this order" />}
      </Panel>

      <div className="ui-grid-2">
        <RecordPanel title="Payments" rows={detail.payments} />
        <RecordPanel title="Allocations" rows={detail.allocations} />
        <RecordPanel title="Pick tasks" rows={detail.picks} />
        <RecordPanel title="Containers" rows={detail.containers} />
        <RecordPanel title="Shipment manifest" rows={detail.shipmentManifest} />
        <RecordPanel title="Notifications" rows={detail.notifications} />
      </div>

      <div className="ui-grid-2">
        <Panel title="Notes" count={(detail.notes ?? []).length}>
          {(detail.notes ?? []).length ? (
            <ol className="ui-feed">
              {(detail.notes ?? []).map((n, i) => (
                <li key={i}>
                  <div><strong>{label(field(n, "note_type"))}</strong>{bool(field(n, "important")) && <span className="ui-badge ui-tone-warn">Important</span>}</div>
                  <p>{fieldText(n, "note_text", "")}</p>
                  <small>{fieldText(n, "created_by")} · {dt(field(n, "created_dstamp"))}</small>
                </li>
              ))}
            </ol>
          ) : <EmptyState title="No notes" />}
        </Panel>
        <Panel title="Audit history" count={(detail.audit ?? []).length}>
          {(detail.audit ?? []).length ? (
            <ol className="ui-feed">
              {(detail.audit ?? []).slice(0, 50).map((a, i) => (
                <li key={i}>
                  <div><strong>{label(field(a, "action"))}</strong></div>
                  {fieldText(a, "reason", "") && <p>{fieldText(a, "reason", "")}</p>}
                  <small>{fieldText(a, "changed_by")} · {dt(field(a, "created_dstamp"))}</small>
                </li>
              ))}
            </ol>
          ) : <EmptyState title="No audit events recorded" />}
        </Panel>
      </div>

      {dialog === "note" && <OrderNoteModal token={token} orderId={orderId} onClose={() => setDialog(null)} onDone={() => { setDialog(null); reload(); }} />}
      {dialog === "amend" && <OrderAmendModal token={token} order={order} onClose={() => setDialog(null)} onDone={() => { setDialog(null); reload(); }} />}
      {dialog === "cancel" && <OrderCancelModal token={token} orderId={orderId} refundRecommended={bool(actions.cancel?.refundRecommended)} onClose={() => setDialog(null)} onDone={() => { setDialog(null); reload(); }} />}
    </>
  );
}

const HIDDEN_KEYS = new Set(["client_id"]);

/** Shows related rows exactly as the API returns them; columns come from the data, not assumptions. */
function RecordPanel({ title, rows }: { title: string; rows?: Obj[] }) {
  const list = rows ?? [];
  const keys = list.length ? Object.keys(list[0]).filter((k) => !HIDDEN_KEYS.has(k.toLowerCase())).slice(0, 6) : [];
  return (
    <Panel title={title} count={list.length} flush>
      {list.length ? (
        <DataTable caption={title} rows={list} rowKey={(_, i) => String(i)} columns={keys.map((k) => ({
          key: k,
          header: label(k.toLowerCase()),
          cell: (r: Obj) => {
            const v = r[k];
            if (v === null || v === undefined || v === "") return <span className="ui-muted">—</span>;
            if (typeof v === "object") return <code className="ui-ref">{JSON.stringify(v)}</code>;
            if (/status$/i.test(k)) return <StatusBadge status={v} />;
            if (/(dstamp|date|_at)$/i.test(k)) return dt(v);
            return String(v);
          },
        }))} />
      ) : <EmptyState title={`No ${title.toLowerCase()}`} />}
    </Panel>
  );
}
