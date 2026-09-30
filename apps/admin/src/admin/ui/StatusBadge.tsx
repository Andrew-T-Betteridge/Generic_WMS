import { txt } from "../admin-api";
import type { Tone } from "./layout";

// Presentation-only colour mapping for status codes returned by the API.
// Unknown codes render neutrally; this never decides what an operator may do.
const TONES: Record<string, Tone> = {};
const assign = (tone: Tone, codes: string[]) => codes.forEach((c) => (TONES[c] = tone));
assign("good", ["PAID", "READY", "SHIPPED", "DELIVERED", "COMPLETE", "COMPLETED", "RESOLVED", "CLOSED", "SUBMITTED", "REQUEUED", "ACTIVE", "ALLOCATED", "SENT", "SUCCESS", "REFUNDED"]);
assign("bad", ["FAILED", "ERROR", "CANCELLED", "REJECTED", "DEAD", "DECLINED"]);
assign("warn", ["PENDING", "OPEN", "STARTED", "PART_ALLOCATED", "PART_REFUNDED", "HOLD", "AWAITING_CUSTOMER", "REQUESTED", "UNALLOCATED", "RETRY", "QUEUED"]);
assign("info", ["AUTHORISED", "RESERVED", "PICKING", "PACKED", "IN_PROGRESS", "PROCESSING"]);

export function toneFor(status: unknown): Tone {
  return TONES[txt(status, "").toUpperCase()] ?? "neutral";
}

export function StatusBadge({ status, children }: { status: unknown; children?: string }) {
  const code = txt(status, "");
  if (!code) return <span className="ui-badge ui-tone-neutral">—</span>;
  return <span className={`ui-badge ui-tone-${toneFor(code)}`} data-status={code.toUpperCase()}>{children ?? code.replaceAll("_", " ")}</span>;
}
