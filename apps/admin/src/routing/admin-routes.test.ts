import { describe, expect, it } from "vitest";
import { ADMIN_ROUTES, findRouteByPath, firstAccessibleRoute, matchRoute, visibleNavSections } from "./admin-routes";
import { fullAccessMe, hasFor, warehouseMe, wildcardMe } from "../test/me-fixtures";

describe("route resolution", () => {
  it("resolves every existing screen to a unique path", () => {
    const paths = ADMIN_ROUTES.map((r) => r.path);
    expect(new Set(paths).size).toBe(paths.length);
    expect(ADMIN_ROUTES).toHaveLength(19);
    for (const route of ADMIN_ROUTES) expect(findRouteByPath(route.path)?.id).toBe(route.id);
  });

  it("tolerates a trailing slash and rejects unknown paths", () => {
    expect(findRouteByPath("/orders/")?.id).toBe("orders");
    expect(findRouteByPath("/gift-cards")?.id).toBe("giftcards");
    expect(findRouteByPath("/orders/123")?.id).toBe("orderDetail");
    expect(findRouteByPath("/orders/123/extra")).toBeUndefined();
    expect(findRouteByPath("/nope")).toBeUndefined();
  });
});

describe("permission-driven navigation", () => {
  it("shows all sections to a user holding every read permission", () => {
    const sections = visibleNavSections(hasFor(fullAccessMe));
    expect(sections.map((s) => s.label)).toEqual(["Operations", "Commercial", "Supply & delivery", "Platform"]);
    expect(sections.flatMap((s) => s.routes)).toHaveLength(18);
  });

  it("keeps the existing ANY-of semantics and hides empty sections", () => {
    const sections = visibleNavSections(hasFor(warehouseMe));
    expect(sections.map((s) => s.label)).toEqual(["Operations"]);
    // fulfilment needs pick.read OR shipment.read
    expect(sections[0].routes.map((r) => r.id)).toEqual(["inventory", "fulfilment"]);
  });

  it("does not infer permissions: customers still needs order.read", () => {
    const ids = visibleNavSections(hasFor(warehouseMe)).flatMap((s) => s.routes.map((r) => r.id));
    expect(ids).not.toContain("customers");
    expect(ids).not.toContain("dashboard");
  });

  it("falls back to the first accessible screen when the dashboard is not permitted", () => {
    expect(firstAccessibleRoute(hasFor(fullAccessMe))?.id).toBe("dashboard");
    expect(firstAccessibleRoute(hasFor(warehouseMe))?.id).toBe("inventory");
    expect(firstAccessibleRoute(() => false)).toBeUndefined();
  });
});

describe("record-detail routes", () => {
  it("exposes the order reference and keeps the order permission", () => {
    const m = matchRoute("/orders/ORD-1001");
    expect(m?.route.id).toBe("orderDetail");
    expect(m?.params.orderId).toBe("ORD-1001");
    expect(m?.route.permissions).toEqual(["order.read"]);
  });

  it("never lists record-detail routes in navigation", () => {
    const ids = visibleNavSections(hasFor(fullAccessMe)).flatMap((s) => s.routes.map((r) => r.id));
    expect(ids).not.toContain("orderDetail");
    expect(ids).toHaveLength(18);
  });

  it("gives a wildcard administrator the same navigation as full access", () => {
    expect(visibleNavSections(hasFor(wildcardMe))).toEqual(visibleNavSections(hasFor(fullAccessMe)));
  });
});
