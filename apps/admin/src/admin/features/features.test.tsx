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
const { ReturnsPage, AuditPage, CataloguePage } = await import("../control-plane");

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
    await userEvent.click(screen.getByRole("checkbox", { name: "SHIPPED" }));
    await waitFor(() => expect(calls.at(-1)!.path).toContain("fulfilmentStatuses="));
    expect(calls.at(-1)!.path).toContain("SHIPPED");
    expect(loc()).toContain("fulfilmentStatuses=");
    expect(loc()).toContain("SHIPPED");
    await userEvent.type(screen.getByLabelText("Search orders"), "a@example.com{enter}");
    await waitFor(() => expect(calls.at(-1)!.path).toContain("q=a%40example.com"));
  });

  it("distinguishes an empty dataset from filtered no-results", async () => {
    mockApi(on(/^\/api\/admin\/orders\?/, 200, []));
    at("/orders", "/orders", <OrdersPage token={token} />);
    expect(await screen.findByText("No orders match these filters")).toBeTruthy();
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
    expect(calls.some((c) => c.method === "POST")).toBe(false); // confirmation first
    await userEvent.click(await screen.findByRole("button", { name: "Deallocate order" }));
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
    mockApi(on("/api/admin/operations/dashboard", 200, { summary: { outstanding_orders: 4, payment_attention: 1, exception_count: 3, open_picks: 2, failed_notifications: 0, open_cases: 1 }, topExceptions: [] }));
    at("/", "/", <ControlCentre token={token} has={createHasPermission(["dashboard.read", "exception.read"])} environment="TEST" />);
    expect(await screen.findByText("Open exceptions")).toBeTruthy();
    expect(screen.getByText("3")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Review →" }).getAttribute("href")).toBe("/exceptions");
    expect(screen.getByText("All clear")).toBeTruthy();
  });
});

describe("Returns & audit functional pass", () => {
  it("starts case creation from an outbound order search", async () => {
    mockApi(
      on(/^\/api\/admin\/returns\?/, 200, []),
      on(/^\/api\/admin\/orders\?q=/, 200, [{
        ...ORDER,
        customer_name: "Ada Customer",
        status: "ALLOCATED",
        fulfilment_status: "ALLOCATED",
        payment_status: "PAID"
      }]),
      on(/^\/api\/admin\/config\/reason-codes\?/, 200, [])
    );

    render(<ReturnsPage token={token} has={createHasPermission(["return.read","return.create"])} />);

    await userEvent.type(screen.getByPlaceholderText("Order ID, customer ID or email"), "ORD-1");
    const create = await screen.findByRole("button", { name: "Create return / claim" });
    await userEvent.click(create);

    expect(await screen.findByRole("heading", { name: "New return / claim" })).toBeTruthy();
    expect(screen.getByText(/Selected order:/)).toBeTruthy();
    expect(screen.getAllByText("ORD-1").length).toBeGreaterThan(0);
  });

  it("loads audit metadata and renders field-level changes", async () => {
    mockApi(
      on("/api/admin/audit/meta", 200, { entityTypes: ["ORDER"], actions: ["UPDATE"] }),
      on(/^\/api\/admin\/audit\?/, 200, [{
        audit_id: "A1",
        entity_type: "ORDER",
        entity_id: "ORD-1",
        action: "UPDATE",
        changed_by: "ops@example.com",
        created_dstamp: "2026-09-30T12:00:00Z",
        before_data: { STATUS: "PENDING" },
        after_data: { STATUS: "PAID" }
      }])
    );

    render(<AuditPage token={token} />);

    expect(await screen.findByRole("option", { name: "ORDER" })).toBeTruthy();
    expect(screen.getByRole("option", { name: "UPDATE" })).toBeTruthy();
    expect(await screen.findByText("1 field changed")).toBeTruthy();
    expect(screen.getByText(/PENDING/).textContent).toContain("PAID");
  });
});

describe("Catalogue create contract", () => {
  it("loads categories and requires one before product creation", async () => {
    mockApi(
      on(/^\/api\/admin\/products\?/, 200, []),
      on("/api/admin/product-categories", 200, [
        {category_code:"FISH",category_name:"Fish"},
        {category_code:"EQUIPMENT",category_name:"Equipment"}
      ])
    );

    render(<CataloguePage token={token} has={createHasPermission(["product.read","product.create"])} />);

    await userEvent.click(await screen.findByRole("button",{name:"Create product"}));

    expect(await screen.findByRole("option",{name:"Fish (FISH)"})).toBeTruthy();
    expect(screen.getByRole("option",{name:"Equipment (EQUIPMENT)"})).toBeTruthy();
    expect(screen.getByLabelText("Category")).toBeTruthy();
  });
});

describe("Return case lifecycle statuses", () => {
  it("exposes the awaiting-customer status used by the return-case contract", async () => {
    mockApi(on(/^\/api\/admin\/returns\?/, 200, []));

    render(<ReturnsPage
      token={token}
      has={createHasPermission(["return.read"])}
    />);

    expect(
      await screen.findByRole("option", { name: "AWAITING_CUSTOMER" })
    ).toBeTruthy();
  });
});

describe("Return item-level intake", () => {
  it("selects an outbound order line and posts its quantity", async () => {
    const { calls } = mockApi(
      on(/^\/api\/admin\/returns\?/, 200, []),
      on(/^\/api\/admin\/orders\?q=/, 200, [{
        ...ORDER,
        customer_name: "Ada Customer"
      }]),
      on("/api/admin/orders/ORD-1", 200, {
        order: ORDER,
        lines: [{
          line_id: 1,
          sku_id: "SKU-9",
          qty_ordered: 2
        }]
      }),
      on(/^\/api\/admin\/config\/reason-codes\?/, 200, [{
        reason_code: "DOA",
        description: "Dead on arrival"
      }]),
      on("/api/admin/returns", 201, {
        return_case_id: "R1",
        order_id: "ORD-1"
      }, "POST")
    );

    render(<ReturnsPage
      token={token}
      has={createHasPermission(["return.read","return.create"])}
    />);

    await userEvent.type(
      screen.getByPlaceholderText("Order ID, customer ID or email"),
      "ORD-1"
    );

    await userEvent.click(
      await screen.findByRole("button",{name:"Create return / claim"})
    );

    const qty=await screen.findByLabelText("Qty for SKU-9");
    await userEvent.clear(qty);
    await userEvent.type(qty,"1");

    await userEvent.type(
      screen.getByLabelText("Expected resolution"),
      "Replacement"
    );

    await userEvent.click(
      screen.getByRole("button",{name:"Create case"})
    );

    await waitFor(()=>{
      expect(calls.some(c=>c.path==="/api/admin/returns"&&c.method==="POST")).toBe(true);
    });

    const call=calls.find(c=>c.path==="/api/admin/returns"&&c.method==="POST");
    const body=JSON.parse(call?.body??"{}");

    expect(body.orderId).toBe("ORD-1");
    expect(body.lines).toEqual([{
      lineId:1,
      qty:1,
      issueType:"DOA",
      resolution:"Replacement"
    }]);
    expect(body.operationId).toBeTruthy();
  });
});
