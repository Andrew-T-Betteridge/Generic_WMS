import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
vi.mock("../env", () => ({ ADMIN_CONFIG: { apiBaseUrl: "http://api.test" } }));
import { ApiError } from "../admin-api";
import { EmptyState, ErrorState, LoadingState } from "./states";
import { StatusBadge } from "./StatusBadge";
import { Pager } from "./DataTable";

afterEach(cleanup);
const wrap = (ui: React.ReactNode) => render(<MemoryRouter>{ui}</MemoryRouter>);

describe("shared states", () => {
  it("loading is announced", () => {
    wrap(<LoadingState label="Loading orders" />);
    expect(screen.getByRole("status").textContent).toContain("Loading orders");
  });
  it("empty distinguishes no data from no results", () => {
    wrap(<><EmptyState title="A" /><EmptyState kind="no-results" title="B" /></>);
    expect(screen.getByText("A").parentElement?.dataset.kind).toBe("empty");
    expect(screen.getByText("B").parentElement?.dataset.kind).toBe("no-results");
  });
  it("error shows a plain message, keeps technical detail, and retries", async () => {
    const retry = vi.fn();
    wrap(<ErrorState error={new ApiError(500, "BOOM", null)} onRetry={retry} />);
    const alert = screen.getByRole("alert");
    expect(alert.dataset.kind).toBe("failed");
    expect(screen.getByText("HTTP 500 · BOOM")).toBeTruthy();
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(retry).toHaveBeenCalled();
  });
  it("forbidden errors offer no retry", () => {
    wrap(<ErrorState error={new ApiError(403, "PERMISSION_REQUIRED", null)} onRetry={() => {}} />);
    expect(screen.queryByRole("button", { name: "Try again" })).toBeNull();
    expect(screen.getByText("Access not available")).toBeTruthy();
  });
});

describe("StatusBadge and Pager", () => {
  it("renders status codes readably with a tone", () => {
    wrap(<StatusBadge status="PART_ALLOCATED" />);
    const b = screen.getByText("PART ALLOCATED");
    expect(b.className).toContain("ui-tone-warn");
  });
  it("hides pagination when everything fits on one page", () => {
    const { container } = wrap(<Pager page={0} pageSize={50} rowCount={10} onPage={() => {}} />);
    expect(container.querySelector(".ui-pager")).toBeNull();
  });
});
