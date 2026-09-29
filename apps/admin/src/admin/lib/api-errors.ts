import { ApiError } from "../admin-api";

// Turns any failure from the WMS API into an operator-facing description.
// The technical detail is always kept so it can be shown on request; it is
// never discarded and a failure is never reported as "no results".

export type ErrorKind =
  | "unauthenticated" // 401 — the session is missing or expired
  | "forbidden" //       403 — the API refused this account (RBAC)
  | "backend-access" //  the API itself could not read its data (database grant / role problem)
  | "not-found" //       404 — the requested record does not exist
  | "invalid" //         400/409 — the request or action was rejected
  | "unavailable" //     network failure or 502/503/504
  | "failed"; //         anything else

export type DescribedError = {
  kind: ErrorKind;
  title: string;
  message: string;
  status?: number;
  code?: string;
  technical: string;
};

// PostgreSQL privilege errors surface as e.g.
// "permission denied for view admin_order_control_workbench". The API returns
// them as HTTP 500 because its mapping only recognises upper-case codes.
const DB_PRIVILEGE = /^permission denied for (view|table|relation|schema|function|sequence)\s+(\S+)/i;

export function describeError(error: unknown): DescribedError {
  if (error instanceof ApiError) {
    const technical = `HTTP ${error.status} · ${error.code}`;
    const base = { status: error.status, code: error.code, technical };
    const privilege = DB_PRIVILEGE.exec(error.code);
    if (privilege) {
      return {
        ...base,
        kind: "backend-access",
        title: "This data is not available right now",
        message:
          "Your account is allowed to use this area, but the WMS service could not read the underlying data. " +
          "This is a service configuration problem, not something you can fix from here. Please report it to your system administrator.",
      };
    }
    if (error.status === 401 || error.code === "AUTHENTICATION_REQUIRED" || error.code.startsWith("AUTH_")) {
      return { ...base, kind: "unauthenticated", title: "Your session has ended", message: "Sign in again to continue." };
    }
    if (error.status === 403) {
      return {
        ...base,
        kind: "forbidden",
        title: "Access not available",
        message: "The WMS service did not allow your account to perform this request. Ask an Admin administrator to review your access if you need it.",
      };
    }
    if (error.status === 404) {
      return { ...base, kind: "not-found", title: "Record not found", message: "The WMS service has no record at this reference. It may have been mistyped or removed." };
    }
    if (error.status === 400 || error.status === 409) {
      return { ...base, kind: "invalid", title: "The WMS service rejected this request", message: humanise(error.code) };
    }
    if (error.status === 502 || error.status === 503 || error.status === 504) {
      return { ...base, kind: "unavailable", title: "The WMS service is unavailable", message: "The service did not respond. Try again in a moment." };
    }
    return { ...base, kind: "failed", title: "The request failed", message: "The WMS service reported an error while handling this request. Try again, and report it if it keeps happening." };
  }
  if (error instanceof TypeError) {
    return {
      kind: "unavailable",
      title: "The WMS service could not be reached",
      message: "Check your connection and try again.",
      technical: `${error.name}: ${error.message}`,
    };
  }
  const text = error instanceof Error ? error.message : String(error);
  if (text === "AUTH_TOKEN_MISSING" || /login required|consent required/i.test(text)) {
    return { kind: "unauthenticated", title: "Your session has ended", message: "Sign in again to continue.", technical: text };
  }
  return { kind: "failed", title: "Something went wrong", message: "The request could not be completed.", technical: text };
}

function humanise(code: string) {
  const words = code.replace(/[:_]+/g, " ").trim().toLowerCase();
  return words ? words.charAt(0).toUpperCase() + words.slice(1) + "." : "The request was not accepted.";
}
