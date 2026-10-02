import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const operations = fs.readFileSync(
  path.resolve(process.cwd(), "../api/src/admin-operations.ts"),
  "utf8",
);

const controlPlane = fs.readFileSync(
  path.resolve(process.cwd(), "src/admin/control-plane.tsx"),
  "utf8",
);

const expiry = fs.readFileSync(
  path.resolve(
    process.cwd(),
    "../../database/functions/api/EXPIRE_PENDING_PAYMENT_ORDERS.sql",
  ),
  "utf8",
);

describe("0.3.18.2 cross-layer admin contracts", () => {
  it("honours the Admin multi-status fulfilment query", () => {
    expect(operations).toContain("q.fulfilmentStatuses");
    expect(operations).toContain("FULFILMENT_STATUS=any($4::text[])");
  });

  it("uses the actual ORDER_HEADER customer/value/date fields", () => {
    expect(operations).toContain("CONTACT_EMAIL");
    expect(operations).toContain("CONTACT_PHONE");
    expect(operations).toContain("ORDER_VALUE");
    expect(operations).toContain("ORDER_DATE");
    expect(operations).not.toContain("CUSTOMER_EMAIL");
    expect(operations).not.toContain("CUSTOMER_PHONE");
    expect(operations).not.toContain("CUSTOMER_FIRST_NAME");
    expect(operations).not.toContain("CUSTOMER_LAST_NAME");
    expect(operations).not.toContain("ORDER_TOTAL");
  });

  it("keeps physical count payload names aligned with the API", () => {
    expect(controlPlane).toContain("newQuantity:target");
    expect(controlPlane).toContain("expectedCurrentQuantity:current");
    expect(controlPlane).toContain("note:notes");
    expect(controlPlane).not.toContain("countedQty:target");
    expect(controlPlane).not.toContain("expectedQtyOnHand:current");
  });

  it("terminalises internal pending payment transactions on WMS expiry", () => {
    expect(expiry).toContain("UPDATE core.PAYMENT_TRANSACTION");
    expect(expiry).toContain("STATUS='CANCELLED'");
    expect(expiry).toContain("STATUS IN ('CREATED','PENDING')");
  });
});
