import { describe, expect, it } from "vitest";
import { ADMIN_ROUTES, findRouteByPath, firstAccessibleRoute, visibleNavSections } from "./admin-routes";
import { fullAccessMe, hasFor, warehouseMe } from "../test/me-fixtures";

describe("route resolution", () => {
  it("resolves every existing screen to a unique path", () => {
    const paths = ADMIN_ROUTES.map((r) => r.path);
    expect(new Set(paths).size).toBe(paths.length);
    expect(ADMIN_ROUTES).toHaveLength(18);
    for (const route of ADMIN_ROUTES) expect(findRouteByPath(route.path)?.id).toBe(route.id);
  });

  it("tolerates a trailing slash and rejects unknown paths", () => {
    expect(findRouteByPath("/orders/")?.id).toBe("orders");
    expect(findRouteByPath("/gift-cards")?.id).toBe("giftcards");
    expect(findRouteByPath("/orders/123")).toBeUndefined();
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
