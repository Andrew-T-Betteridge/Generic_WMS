import { get, txt, type Obj } from "../admin-api";

// The API returns Postgres rows whose keys may arrive lower- or upper-case.
// `field(row, "order_id")` reads either spelling.
export function field(row: Obj | undefined | null, name: string): unknown {
  return get(row, name, name.toUpperCase());
}

export function fieldText(row: Obj | undefined | null, name: string, fallback = "—"): string {
  return txt(field(row, name), fallback);
}

export function label(code: unknown): string {
  const s = txt(code, "");
  return s ? s.replaceAll("_", " ") : "—";
}

export function relativeAge(minutes: unknown): string {
  const m = Number(minutes);
  if (!Number.isFinite(m)) return "—";
  if (m < 60) return `${Math.max(0, Math.round(m))}m`;
  if (m < 60 * 24) return `${Math.floor(m / 60)}h ${Math.round(m % 60)}m`;
  return `${Math.floor(m / 1440)}d ${Math.floor((m % 1440) / 60)}h`;
}
