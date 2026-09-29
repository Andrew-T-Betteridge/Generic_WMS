import type { ReactNode } from "react";

export type Column<T> = {
  key: string;
  header: ReactNode;
  cell: (row: T) => ReactNode;
  align?: "left" | "right";
  width?: string;
};

/**
 * Dense operational table. Rows can link to a record (`rowHref` + `renderLink`)
 * or trigger an action (`onRowClick`); keyboard users get the same behaviour.
 */
export function DataTable<T>({
  rows, columns, rowKey, onRowClick, rowLabel, caption, rowTone,
}: {
  rows: T[];
  columns: Column<T>[];
  rowKey: (row: T, index: number) => string;
  onRowClick?: (row: T) => void;
  rowLabel?: (row: T) => string;
  caption?: string;
  /** Presentation-only row emphasis, e.g. a failed status returned by the API. */
  rowTone?: (row: T) => "bad" | "warn" | undefined;
}) {
  return (
    <div className="ui-table-wrap">
      <table className="ui-table">
        {caption && <caption className="ui-sr">{caption}</caption>}
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} scope="col" style={{ width: c.width, textAlign: c.align }}>{c.header}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr
              key={rowKey(row, i)}
              className={[onRowClick ? "ui-row-action" : "", rowTone?.(row) ? `ui-row-${rowTone(row)}` : ""].join(" ").trim() || undefined}
              tabIndex={onRowClick ? 0 : undefined}
              aria-label={onRowClick && rowLabel ? rowLabel(row) : undefined}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
              onKeyDown={onRowClick ? (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onRowClick(row); } } : undefined}
            >
              {columns.map((c) => <td key={c.key} style={{ textAlign: c.align }}>{c.cell(row)}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Offset pagination for endpoints that accept `limit`/`offset` but return no total. */
export function Pager({
  page, pageSize, rowCount, onPage,
}: { page: number; pageSize: number; rowCount: number; onPage: (page: number) => void }) {
  const from = rowCount ? page * pageSize + 1 : 0;
  const to = page * pageSize + rowCount;
  const hasNext = rowCount === pageSize;
  if (page === 0 && !hasNext) return null;
  return (
    <nav className="ui-pager" aria-label="Pagination">
      <span>Showing {from}–{to}</span>
      <button type="button" className="btn ghost sm" disabled={page === 0} onClick={() => onPage(page - 1)}>Previous</button>
      <button type="button" className="btn ghost sm" disabled={!hasNext} onClick={() => onPage(page + 1)}>Next</button>
    </nav>
  );
}
