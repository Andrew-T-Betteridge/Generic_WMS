import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
vi.mock("../env", () => ({ ADMIN_CONFIG: { apiBaseUrl: "http://api.test" } }));
import { ConfirmDialog, StatusBanner, Tabs } from "./layout";
import { DataTable } from "./DataTable";
import { ageTone } from "../features/exceptions/ExceptionsPage";

afterEach(cleanup);

describe("ConfirmDialog", () => {
  it("confirms, cancels and closes on Escape", async () => {
    const onConfirm = vi.fn(), onCancel = vi.fn();
    render(<ConfirmDialog title="Deallocate?" confirmLabel="Deallocate order" danger onConfirm={onConfirm} onCancel={onCancel}>Body</ConfirmDialog>);
    expect(screen.getByRole("alertdialog", { name: "Deallocate?" })).toBeTruthy();
    await userEvent.click(screen.getByRole("button", { name: "Keep as is" }));
    expect(onCancel).toHaveBeenCalledTimes(1);
    await userEvent.keyboard("{Escape}");
    expect(onCancel).toHaveBeenCalledTimes(2);
    await userEvent.click(screen.getByRole("button", { name: "Deallocate order" }));
    expect(onConfirm).toHaveBeenCalledTimes(1);
  });
});

describe("Tabs", () => {
  function Harness() {
    const [v, setV] = useState("a");
    return <><Tabs label="T" value={v} onChange={setV} tabs={[{ id: "a", label: "Alpha", count: 1 }, { id: "b", label: "Beta" }]} /><p data-testid="v">{v}</p></>;
  }
  it("selects by click and arrow keys", async () => {
    render(<Harness />);
    expect(screen.getByRole("tab", { name: /Alpha/ }).getAttribute("aria-selected")).toBe("true");
    await userEvent.click(screen.getByRole("tab", { name: "Beta" }));
    expect(screen.getByTestId("v").textContent).toBe("b");
    await userEvent.keyboard("{ArrowRight}");
    expect(screen.getByTestId("v").textContent).toBe("a");
  });
});

describe("row emphasis and banners", () => {
  it("marks rows with the tone supplied by the caller", () => {
    render(<DataTable caption="x" rows={[{ id: "1", s: "FAILED" }, { id: "2", s: "PAID" }]} rowKey={(r) => r.id}
      rowTone={(r) => (r.s === "FAILED" ? "bad" : undefined)} columns={[{ key: "id", header: "ID", cell: (r) => r.id }]} />);
    const rows = screen.getAllByRole("row").slice(1);
    expect(rows[0].className).toContain("ui-row-bad");
    expect(rows[1].className).not.toContain("ui-row-bad");
  });
  it("renders a status banner with its tone", () => {
    render(<StatusBanner tone="bad" title="Attention needed">2 open exceptions</StatusBanner>);
    expect(screen.getByRole("status").className).toContain("ui-tone-bad");
  });
  it("emphasises exception age only by elapsed time", () => {
    expect(ageTone(30)).toBeUndefined();
    expect(ageTone(300)).toBe("warn");
    expect(ageTone(2000)).toBe("bad");
    expect(ageTone(undefined)).toBeUndefined();
  });
});
