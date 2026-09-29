import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { mockApi, on, token } from "../test/http";
import { createHasPermission } from "../lib/permissions";

vi.mock("../env", () => ({ ADMIN_CONFIG: { apiBaseUrl: "http://api.test", environment: "TEST", adminTitle: "WMS Admin" } }));

const { OrdersPage } = await import("./orders/OrdersPage");
const { OrderDetailPage } = await import("./orders/OrderDetailPage");
const { ExceptionsPage } = await import("./exceptions/ExceptionsPage");
const { InventoryPage } = await import("./inventory/InventoryPage");
const { ControlCentre } = await import("./dashboard/ControlCentre");

afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

function Where() { const l = useLocation(); return <output data-testid="loc">{l.pathname + l.search}</output>; }
function at(path: string, pattern: string, el: React.ReactNode) {
  return render(<MemoryRouter initialEntries={[path]}><Routes><Route path={pattern} element={el} /><Route path="*" element={null} /></Routes><Where /></MemoryRouter>);
}
const loc = () => screen.getByTestId("loc").textContent;

const ORDER = { order_id: "ORD-1", order_date: "2026-09-01T10:00:00Z", contact_email: "a@example.com", customer_id: "C1", payment_status: "PAID", fulfilment_status: "ALLOCATED", qty_ordered: 2, qty_picked: 1, open_pick_tasks: 1, order_value: 12.5 };
const GRANT_ERROR = { error: "permission denied for view admin_order_control_workbench" };

describe("Orders list", () => {
  it("renders orders from the API", async () => {
    mockApi(on(/^\/api\/admin\/orders\?/, 200, [ORDER]));
    at("/orders", "/orders", <OrdersPage token={token} />);
    const table = await screen.findByRole("table", { name: "Orders" });
    expect(within(table).getByText("ORD-1")).toBeTruthy();
    expect(within(table).getByText("PAID")).toBeTruthy();
    expect(within(table).getByText("1/2")).toBeTruthy();
  });

  it("sends filters to the API and keeps them in the address", async () => {
    const { calls } = mockApi(on(/^\/api\/admin\/orders\?/, 200, []));
    at("/orders?payment=PAID", "/orders", <OrdersPage token={token} />);
    await screen.findByText("No orders match these filters");
    expect(calls[0].path).toContain("paymentStatus=PAID");
    await userEvent.selectOptions(screen.getByLabelText("Fulfilment status"), "SHIPPED");
    await waitFor(() => expect(calls.at(-1)!.path).toContain("fulfilmentStatus=SHIPPED"));
    expect(loc()).toContain("fulfilment=SHIPPED");
    await userEvent.type(screen.getByLabelText("Search orders"), "a@example.com{enter}");
    await waitFor(() => expect(calls.at(-1)!.path).toContain("q=a%40example.com"));
  });

  it("distinguishes an empty dataset from filtered no-results", async () => {
    mockApi(on(/^\/api\/admin\/orders\?/, 200, []));
    at("/orders", "/orders", <OrdersPage token={token} />);
    expect(await screen.findByText("No orders yet")).toBeTruthy();
  });

  it("opens the order record when a row is chosen", async () => {
    mockApi(on(/^\/api\/admin\/orders\?/, 200, [ORDER]));
    at("/orders", "/orders", <OrdersPage token={token} />);
    await userEvent.click(await screen.findByRole("row", { name: "Open order ORD-1" }));
    expect(loc()).toBe("/orders/ORD-1");
  });

  it("regression: workbench database grant errors are not shown as raw permission errors or empty lists", async () => {
    mockApi(on(/^\/api\/admin\/orders\?/, 500, GRANT_ERROR));
    at("/orders", "/orders", <OrdersPage token={token} />);
    const alert = await screen.findByRole("alert");
    expect(alert.dataset.kind).toBe("backend-access");
    expect(alert.querySelector("strong")!.textContent).not.toMatch(/permission denied/);
    expect(screen.queryByText("No orders yet")).toBeNull();
  });

  it("presents an API 403 as an access state", async () => {
    mockApi(on(/^\/api\/admin\/orders\?/, 403, { error: "PERMISSION_REQUIRED" }));
    at("/orders", "/orders", <OrdersPage token={token} />);
    expect((await screen.findByRole("alert")).dataset.kind).toBe("forbidden");
  });
});

const DETAIL = { order: { ...ORDER, name: "Ada", address1: "1 Road", postcode: "AB1 2CD" }, lines: [{ line_id: 1, sku_id: "SKU-9", qty_ordered: 2, qty_picked: 1, qty_shipped: 0 }], allocations: [], picks: [], containers: [], shipmentManifest: [], payments: [], notes: [], audit: [], notifications: [] };
const actions = (o: Record<string, unknown>) => ({
  allocate: { allowed: false, permission: "order.allocate" },
  deallocate: { allowed: true, permission: "order.deallocate" },
  createPicks: { allowed: true, permission: "order.pick.create" },
  amendHeader: { allowed: false, permission: "order.amend" },
  cancel: { allowed: false, permission: "order.cancel", reason: "Order contains shipped containers." },
  ...o,
});

describe("Order detail", () => {
  it("renders sections from the API record", async () => {
    mockApi(on("/api/admin/orders/ORD-1", 200, DETAIL), on("/api/admin/orders/ORD-1/actions", 200, actions({})));
    at("/orders/ORD-1", "/orders/:orderId", <OrderDetailPage token={token} has={createHasPermission(["order.read"])} />);
    expect(await screen.findByText("SKU-9")).toBeTruthy();
    expect(screen.getByText("Ada")).toBeTruthy();
    expect(screen.getByText("AB1 2CD")).toBeTruthy();
  });

  it("offers only actions the backend allows AND the user holds", async () => {
    mockApi(on("/api/admin/orders/ORD-1", 200, DETAIL), on("/api/admin/orders/ORD-1/actions", 200, actions({})));
    at("/orders/ORD-1", "/orders/:orderId", <OrderDetailPage token={token} has={createHasPermission(["order.read", "order.allocate", "order.deallocate"])} />);
    const bar = await screen.findByRole("region", { name: "Order actions" });
    expect(within(bar).queryByRole("button", { name: "Allocate" })).toBeNull(); // backend says no
    expect(within(bar).getByRole("button", { name: "Deallocate" })).toBeTruthy(); // allowed + held
    expect(within(bar).queryByRole("button", { name: "Create picks" })).toBeNull(); // allowed, not held
    expect(within(bar).queryByRole("button", { name: "Cancel order" })).toBeNull();
    expect(bar.textContent).toContain("Order contains shipped containers.");
  });

  it("posts the backend action and reloads", async () => {
    const { calls } = mockApi(
      on("/api/admin/orders/ORD-1/deallocate", 200, {}, "POST"),
      on("/api/admin/orders/ORD-1", 200, DETAIL), on("/api/admin/orders/ORD-1/actions", 200, actions({})),
    );
    at("/orders/ORD-1", "/orders/:orderId", <OrderDetailPage token={token} has={createHasPermission(["*"])} />);
    await userEvent.click(await screen.findByRole("button", { name: "Deallocate" }));
    await waitFor(() => expect(calls.some((c) => c.method === "POST" && c.path.endsWith("/deallocate"))).toBe(true));
    await waitFor(() => expect(calls.filter((c) => c.path === "/api/admin/orders/ORD-1").length).toBe(2));
  });

  it("shows Record not found for an unknown order", async () => {
    mockApi(on(/^\/api\/admin\/orders\/NOPE/, 404, { error: "ORDER_NOT_FOUND" }));
    at("/orders/NOPE", "/orders/:orderId", <OrderDetailPage token={token} has={createHasPermission(["order.read"])} />);
    expect((await screen.findByRole("alert")).dataset.kind).toBe("not-found");
  });
});

describe("Exceptions", () => {
  const EX = { exception_type: "PAID_NOT_ALLOCATED", entity_type: "ORDER", entity_id: "ORD-7", age_minutes: 125, message: "Paid order not allocated", detail: {} };
  it("lists exceptions and links order records", async () => {
    mockApi(on(/^\/api\/admin\/exceptions/, 200, [EX]));
    at("/exceptions", "/exceptions", <ExceptionsPage token={token} />);
    const link = await screen.findByRole("link", { name: "ORD-7" });
    expect(link.getAttribute("href")).toBe("/orders/ORD-7");
    expect(screen.getByText("2h 5m")).toBeTruthy();
  });
  it("filters by type via the API", async () => {
    const { calls } = mockApi(on(/^\/api\/admin\/exceptions/, 200, []));
    at("/exceptions", "/exceptions", <ExceptionsPage token={token} />);
    expect(await screen.findByText("No open exceptions")).toBeTruthy();
    await userEvent.click(screen.getByRole("button", { name: "OPEN PICK" }));
    await waitFor(() => expect(calls.at(-1)!.path).toContain("type=OPEN_PICK"));
    expect(await screen.findByText("No open pick exceptions")).toBeTruthy();
  });
  it("regression: exception workbench grant error is presented as a service problem", async () => {
    mockApi(on(/^\/api\/admin\/exceptions/, 500, { error: "permission denied for view admin_exception_workbench" }));
    at("/exceptions", "/exceptions", <ExceptionsPage token={token} />);
    const alert = await screen.findByRole("alert");
    expect(alert.dataset.kind).toBe("backend-access");
    expect(screen.queryByText("No open exceptions")).toBeNull();
  });
});

describe("Inventory", () => {
  const ROW = { inventory_key: 11, sku_id: "SKU-1", location_id: "A-01", qty_on_hand: 5, qty_allocated: 2, qty_available: 3 };
  it("renders stock rows", async () => {
    mockApi(on(/^\/api\/admin\/inventory/, 200, [ROW]));
    at("/inventory", "/inventory", <InventoryPage token={token} has={createHasPermission(["inventory.read"])} />);
    expect(await screen.findByText("SKU-1")).toBeTruthy();
    expect(screen.getByText("A-01")).toBeTruthy();
  });
  it("shows no-results for a search and sends it to the API", async () => {
    const { calls } = mockApi(on(/^\/api\/admin\/inventory/, 200, []));
    at("/inventory?q=ZZZ", "/inventory", <InventoryPage token={token} has={createHasPermission([])} />);
    expect(await screen.findByText("No stock matches this search")).toBeTruthy();
    expect(calls[0].path).toContain("q=ZZZ");
  });
  it("shows errors rather than an empty list", async () => {
    mockApi(on(/^\/api\/admin\/inventory/, 503, {}));
    at("/inventory", "/inventory", <InventoryPage token={token} has={createHasPermission([])} />);
    expect((await screen.findByRole("alert")).dataset.kind).toBe("unavailable");
  });
});

describe("Control centre", () => {
  it("shows backend metrics as returned, without re-aggregating", async () => {
    mockApi(on("/api/admin/operations/dashboard", 200, { summary: { orders_today: 4, revenue_today: 99, exception_count: 3, open_picks: 2, failed_notifications: 0, open_cases: 1 }, topExceptions: [] }));
    at("/", "/", <ControlCentre token={token} has={createHasPermission(["dashboard.read", "exception.read"])} environment="TEST" />);
    expect(await screen.findByText("Open exceptions")).toBeTruthy();
    expect(screen.getByText("3")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Review →" }).getAttribute("href")).toBe("/exceptions");
    expect(screen.getByText("All clear")).toBeTruthy();
  });
});
