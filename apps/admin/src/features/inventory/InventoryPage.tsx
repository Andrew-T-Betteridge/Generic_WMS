import { useEffect, useState } from "react";
import { useSearchParams } from "react-router";
import { api, num, query, type Obj, type Token } from "../../admin-api";
import { InventoryModal } from "../../control-plane";
import { field, fieldText } from "../../lib/format";
import type { HasPermission } from "../../lib/permissions";
import { useApi } from "../../lib/use-api";
import { DataTable } from "../../ui/DataTable";
import { PageHeader, Panel, Reference } from "../../ui/layout";
import { EmptyState, ErrorState, SkeletonRows } from "../../ui/states";

// GET /api/admin/inventory accepts q (SKU or batch) and locationId, capped at 250 rows.
export const INVENTORY_LIMIT = 250;

export function InventoryPage({ token, has }: { token: Token; has: HasPermission }) {
  const [params, setParams] = useSearchParams();
  const q = params.get("q") ?? "";
  const location = params.get("location") ?? "";
  const [draftQ, setDraftQ] = useState(q);
  const [draftLocation, setDraftLocation] = useState(location);
  const [selected, setSelected] = useState<Obj | null>(null);

  useEffect(() => { setDraftQ(q); setDraftLocation(location); }, [q, location]);
  useEffect(() => {
    if (draftQ === q && draftLocation === location) return;
    const t = setTimeout(() => {
      const p: Record<string, string> = {};
      if (draftQ.trim()) p.q = draftQ.trim();
      if (draftLocation.trim()) p.location = draftLocation.trim();
      setParams(p);
    }, 350);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draftQ, draftLocation]);

  const path = "/api/admin/inventory" + query({ q: q || undefined, locationId: location || undefined, limit: INVENTORY_LIMIT });
  const { data, error, loading, reload } = useApi(() => api<Obj[]>(token, path), path);
  const rows = data ?? [];
  const filtered = !!(q || location);
  const truncated = rows.length === INVENTORY_LIMIT;

  return (
    <>
      <PageHeader
        title="Inventory"
        description="Stock rows by SKU and location. Select a row to adjust or move stock where your access allows."
        actions={<button type="button" className="btn ghost" onClick={reload}>Refresh</button>}
      />
      <Panel flush>
        <div className="ui-toolbar" role="search">
          <label className="ui-field ui-grow"><span>SKU or batch</span>
            <input className="input" type="search" aria-label="Search SKU or batch" value={draftQ} onChange={(e) => setDraftQ(e.target.value)} placeholder="e.g. SKU code or batch reference" />
          </label>
          <label className="ui-field"><span>Location</span>
            <input className="input" aria-label="Location" value={draftLocation} onChange={(e) => setDraftLocation(e.target.value)} placeholder="Location ID" />
          </label>
          {!loading && !error && <span className="ui-muted ui-push">{rows.length}{truncated ? "+" : ""} rows{truncated ? " — refine the search to see all" : ""}</span>}
        </div>
        {error ? <ErrorState error={error} onRetry={reload} />
          : loading ? <SkeletonRows columns={7} />
          : rows.length === 0 ? (
            filtered
              ? <EmptyState kind="no-results" title="No stock matches this search">Check the SKU, batch or location.</EmptyState>
              : <EmptyState title="No inventory recorded">Stock appears here once it is received into the WMS.</EmptyState>
          ) : (
            <DataTable caption="Inventory" rows={rows}
              rowKey={(r, i) => fieldText(r, "inventory_key", String(i))}
              rowLabel={(r) => `Open stock ${fieldText(r, "sku_id")} at ${fieldText(r, "location_id")}`}
              onRowClick={setSelected}
              columns={[
                { key: "sku", header: "SKU", cell: (r) => <div className="ui-cell-stack"><Reference>{fieldText(r, "sku_id")}</Reference><small>Key {fieldText(r, "inventory_key")}</small></div> },
                { key: "location", header: "Location", cell: (r) => fieldText(r, "location_id") },
                { key: "onhand", header: "On hand", align: "right", cell: (r) => num(field(r, "qty_on_hand")) },
                { key: "allocated", header: "Allocated", align: "right", cell: (r) => num(field(r, "qty_allocated")) },
                {
                  key: "available", header: "Available", align: "right", cell: (r) => {
                    const n = num(field(r, "qty_available"));
                    return <strong className={n <= 0 ? "ui-text-bad" : ""}>{n}</strong>;
                  },
                },
                { key: "batch", header: "Batch", cell: (r) => fieldText(r, "batch_id") },
                { key: "condition", header: "Condition", cell: (r) => fieldText(r, "condition_id") },
              ]} />
          )}
      </Panel>
      {selected && (
        <InventoryModal token={token} row={selected} canAdjust={has("inventory.adjust")} canMove={has("inventory.move")}
          onClose={() => setSelected(null)} onDone={() => { setSelected(null); reload(); }} />
      )}
    </>
  );
}
