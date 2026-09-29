import { describe, expect, it, vi } from "vitest";
vi.mock("../env", () => ({ ADMIN_CONFIG: { apiBaseUrl: "http://api.test" } }));
import { ApiError } from "../admin-api";
import { describeError } from "./api-errors";
import { createHasPermission } from "./permissions";

describe("createHasPermission", () => {
  it("grants exact codes only", () => {
    const has = createHasPermission(["order.read"]);
    expect(has("order.read")).toBe(true);
    expect(has("order.cancel")).toBe(false);
    expect(has("")).toBe(false);
  });
  it("honours the API wildcard", () => {
    const has = createHasPermission(["*"]);
    expect(has("order.cancel")).toBe(true);
    expect(has("")).toBe(false);
  });
  it("grants nothing without a profile", () => {
    expect(createHasPermission(undefined)("order.read")).toBe(false);
  });
});

describe("describeError", () => {
  it("classifies database privilege failures as a service configuration problem", () => {
    const d = describeError(new ApiError(500, "permission denied for view admin_order_control_workbench", {}));
    expect(d.kind).toBe("backend-access");
    expect(d.title).not.toMatch(/permission denied/);
    expect(d.technical).toContain("admin_order_control_workbench");
  });
  it.each([
    [401, "AUTHENTICATION_REQUIRED", "unauthenticated"],
    [403, "PERMISSION_REQUIRED", "forbidden"],
    [404, "ORDER_NOT_FOUND", "not-found"],
    [409, "ACTION_NOT_ALLOWED", "invalid"],
    [503, "HTTP_503", "unavailable"],
    [500, "BOOM", "failed"],
  ])("maps HTTP %i to %s", (status, code, kind) => {
    expect(describeError(new ApiError(status, code, null)).kind).toBe(kind);
  });
  it("treats network failures as unavailable", () => {
    expect(describeError(new TypeError("Failed to fetch")).kind).toBe("unavailable");
  });
});
