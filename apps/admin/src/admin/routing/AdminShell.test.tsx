import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, useLocation, useNavigate } from "react-router";
import type { Me } from "../control-plane";
import { fullAccessMe, hasFor, orderViewerMe, warehouseMe, wildcardMe } from "../test/me-fixtures";

// The operational screens call the live WMS API, so each one is replaced by a
// marker. This test covers the routed shell only, not the screens themselves.
vi.mock("../control-plane", () => {
  const marker = (name: string) => () => <div data-testid="screen">{name}</div>;
  return {
    PaymentsPage: marker("PaymentsPage"), ReturnsPage: marker("ReturnsPage"),
    CustomersPage: marker("CustomersPage"),
    FulfilmentPage: marker("FulfilmentPage"), CataloguePage: marker("CataloguePage"),
    PromotionsPage: marker("PromotionsPage"), GiftCardsPage: marker("GiftCardsPage"),
    InboundPage: marker("InboundPage"), DeliveryPage: marker("DeliveryPage"),
    CommunicationsPage: marker("CommunicationsPage"), InterfacesPage: marker("InterfacesPage"),
    AuditPage: marker("AuditPage"), AccessPage: marker("AccessPage"), SystemPage: marker("SystemPage"),
  };
});
vi.mock("../features/dashboard/ControlCentre", () => ({ ControlCentre: () => <div data-testid="screen">OperationsDashboard</div> }));
vi.mock("../features/orders/OrdersPage", () => ({ OrdersPage: () => <div data-testid="screen">OrdersPage</div> }));
vi.mock("../features/orders/OrderDetailPage", async () => {
  const { useParams } = await import("react-router");
  return { OrderDetailPage: () => <div data-testid="screen">OrderDetailPage:{useParams().orderId}</div> };
});
vi.mock("../features/inventory/InventoryPage", () => ({ InventoryPage: () => <div data-testid="screen">InventoryPage</div> }));
vi.mock("../features/exceptions/ExceptionsPage", () => ({ ExceptionsPage: () => <div data-testid="screen">ExceptionsPage</div> }));
vi.mock("../monitoring", () => ({ NotificationBell: () => <div data-testid="bell" /> }));

const { AdminShell } = await import("./AdminShell");

function Location() {
  const { pathname } = useLocation();
  const navigate = useNavigate();
  return <><output data-testid="path">{pathname}</output><button onClick={() => navigate(-1)}>history-back</button></>;
}

function renderAt(path: string, me: Me = fullAccessMe) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <AdminShell me={me} token={async () => "t"} has={hasFor(me)} title="WMS Admin" environment="TEST" onSignOut={() => {}} />
      <Location />
    </MemoryRouter>,
  );
}

const screenName = () => screen.getByTestId("screen").textContent;
const path = () => screen.getByTestId("path").textContent;

afterEach(cleanup);

describe("AdminShell routing", () => {
  it("deep links (and refreshes) straight to a screen", () => {
    renderAt("/gift-cards");
    expect(screenName()).toBe("GiftCardsPage");
    expect(screen.getByRole("link", { name: "Gift cards" }).getAttribute("aria-current")).toBe("page");
    expect(screen.getByTestId("bell")).toBeTruthy();
  });

  it("navigates with real links and supports history back", async () => {
    const user = userEvent.setup();
    renderAt("/");
    expect(screenName()).toBe("OperationsDashboard");
    const orders = screen.getByRole("link", { name: "Orders" });
    expect(orders.getAttribute("href")).toBe("/orders");
    await user.click(orders);
    expect(path()).toBe("/orders");
    expect(screenName()).toBe("OrdersPage");
    await user.click(screen.getByRole("button", { name: "history-back" }));
    expect(path()).toBe("/");
    expect(screenName()).toBe("OperationsDashboard");
  });

  it("renders breadcrumbs for the current route", () => {
    renderAt("/interfaces");
    const crumbs = screen.getByRole("navigation", { name: "Breadcrumb" });
    expect(crumbs.textContent).toBe("PlatformInterfaces");
    expect(crumbs.querySelector("[aria-current=page]")?.textContent).toBe("Interfaces");
  });

  it("only shows navigation the user is permitted to use", () => {
    renderAt("/inventory", warehouseMe);
    const nav = screen.getByRole("navigation", { name: "Admin sections" });
    const labels = Array.from(nav.querySelectorAll("a")).map((a) => a.textContent);
    expect(labels).toEqual(["Inventory", "Fulfilment"]);
  });

  it("shows Forbidden for a known route without permission, without leaking role details", () => {
    renderAt("/payments", warehouseMe);
    expect(screen.queryByTestId("screen")).toBeNull();
    const alert = screen.getByRole("alert");
    expect(alert.textContent).toContain("does not have access");
    expect(alert.textContent).not.toContain("payment.read");
    expect(alert.textContent).not.toContain("WAREHOUSE");
  });

  it("sends '/' to the first permitted screen when the Control centre is not permitted", () => {
    renderAt("/", warehouseMe);
    expect(path()).toBe("/inventory");
    expect(screenName()).toBe("InventoryPage");
  });

  it("shows Not Found for unknown routes", () => {
    renderAt("/definitely-not-a-page");
    expect(screen.getByRole("heading", { name: "Page not found" })).toBeTruthy();
    expect(screen.getByRole("navigation", { name: "Breadcrumb" }).textContent).toBe("Not found");
  });

  it("deep links to an order record with breadcrumbs back to Orders", () => {
    renderAt("/orders/ORD-1001");
    expect(screenName()).toBe("OrderDetailPage:ORD-1001");
    const crumbs = screen.getByRole("navigation", { name: "Breadcrumb" });
    expect(crumbs.textContent).toBe("OperationsOrdersOrder ORD-1001");
    expect(within(crumbs).getByRole("link", { name: "Orders" }).getAttribute("href")).toBe("/orders");
    // The Orders nav entry stays highlighted while a record is open.
    expect(screen.getByRole("link", { name: "Orders" , current: "page" })).toBeTruthy();
  });

  it("forbids an order record to a user without order.read", () => {
    renderAt("/orders/ORD-1001", warehouseMe);
    expect(screen.queryByTestId("screen")).toBeNull();
    expect(screen.getByRole("alert").textContent).toContain("does not have access");
  });

  it("still returns Not Found for addresses deeper than a record", () => {
    renderAt("/orders/ORD-1001/unknown");
    expect(screen.getByRole("heading", { name: "Page not found" })).toBeTruthy();
  });

  it("interprets the wildcard permission the same way as the API", () => {
    renderAt("/exceptions", wildcardMe);
    expect(screenName()).toBe("ExceptionsPage");
    const nav = screen.getByRole("navigation", { name: "Admin sections" });
    expect(nav.querySelectorAll("a")).toHaveLength(18);
  });

  it("lets a read-only order user open Orders and Exceptions (route and screen agree)", () => {
    renderAt("/orders", orderViewerMe);
    expect(screenName()).toBe("OrdersPage");
    cleanup();
    renderAt("/exceptions", orderViewerMe);
    expect(screenName()).toBe("ExceptionsPage");
  });

  it("uses the configured deployment title alongside the DYNETIC brand mark", () => {
    renderAt("/");
    expect(screen.getByText("WMS Admin")).toBeTruthy();
    expect(document.querySelector(".cp-mark img")).toBeTruthy();
  });

  it("flags non-production environments and hides the ribbon in production", () => {
    renderAt("/");
    expect(screen.getByRole("note").textContent).toContain("TEST environment");
    cleanup();
    render(<MemoryRouter><AdminShell me={fullAccessMe} token={async () => "t"} has={hasFor(fullAccessMe)} title="WMS Admin" environment="PRODUCTION" onSignOut={() => {}} /></MemoryRouter>);
    expect(screen.queryByRole("note")).toBeNull();
  });

  it("shows identity and signs out from the account menu", async () => {
    const onSignOut = vi.fn();
    render(<MemoryRouter><AdminShell me={fullAccessMe} token={async () => "t"} has={hasFor(fullAccessMe)} title="WMS Admin" environment="TEST" onSignOut={onSignOut} /></MemoryRouter>);
    await userEvent.click(screen.getByRole("button", { name: "Account: Ops Lead" }));
    expect(screen.getByText("ops.lead@example.com")).toBeTruthy();
    await userEvent.click(screen.getByRole("button", { name: "Sign out" }));
    expect(onSignOut).toHaveBeenCalled();
  });
});
