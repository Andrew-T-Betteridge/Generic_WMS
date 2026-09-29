import { vi } from "vitest";

// Test-only HTTP boundary. Each handler matches a request path (without the
// API base URL) and returns [status, body]. Unmatched requests fail loudly.
export type Handler = (path: string, init: RequestInit) => [number, unknown] | undefined;

export const TEST_API = "http://api.test";

export function mockApi(...handlers: Handler[]) {
  const calls: { path: string; method: string; body?: string }[] = [];
  const fetchMock = vi.fn(async (url: string, init: RequestInit = {}) => {
    const path = String(url).replace(TEST_API, "");
    calls.push({ path, method: init.method ?? "GET", body: init.body as string | undefined });
    for (const h of handlers) {
      const r = h(path, init);
      if (r) return new Response(JSON.stringify(r[1]), { status: r[0], headers: { "Content-Type": "application/json" } });
    }
    return new Response(JSON.stringify({ error: `UNMOCKED:${path}` }), { status: 599 });
  });
  vi.stubGlobal("fetch", fetchMock);
  return { calls, fetchMock };
}

export const on = (match: string | RegExp, status: number, body: unknown, method = "GET"): Handler =>
  (path, init) => ((init.method ?? "GET") === method && (typeof match === "string" ? path === match : match.test(path)) ? [status, body] : undefined);

export const token = async () => "test-token";
