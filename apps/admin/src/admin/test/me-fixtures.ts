import type { Me } from "../control-plane";
import { createHasPermission } from "../lib/permissions";

// Shapes match GET /api/admin/me in the WMS API (admin-rbac.ts):
// { adminUserId, email, displayName, roles, permissions, bootstrap }

export const fullAccessMe: Me = {
  adminUserId: "8c3f7a52-1d2e-4b7a-9d7e-5b1f0c2a9e11",
  email: "ops.lead@example.com",
  displayName: "Ops Lead",
  roles: ["OWNER"],
  permissions: [
    "admin.access", "dashboard.read", "order.read", "payment.read", "return.read", "inventory.read",
    "pick.read", "shipment.read", "product.read", "config.read", "giftcard.read", "supplier.read",
    "pre_advice.read", "carrier.read", "notification.read", "interface.read", "exception.read",
    "audit.read", "user.read", "system.read",
  ],
  bootstrap: false,
};

export const warehouseMe: Me = {
  adminUserId: "2b9d4e61-7a3c-4f0e-8b12-9c6d5e4f3a21",
  email: "picker@example.com",
  displayName: null,
  roles: ["WAREHOUSE"],
  permissions: ["admin.access", "inventory.read", "pick.read"],
  bootstrap: false,
};

/** Operator allowed to read orders and exceptions, but not act on them. */
export const orderViewerMe: Me = {
  adminUserId: "5e1a2c3d-4b5f-4a6e-9c7d-8e9f0a1b2c3d",
  email: "support@example.com",
  displayName: "Support",
  roles: ["SUPPORT"],
  permissions: ["admin.access", "order.read", "exception.read"],
  bootstrap: false,
};

/** The API grants everything to a principal holding "*" (admin-rbac.ts requirePermission). */
export const wildcardMe: Me = {
  adminUserId: "9f8e7d6c-5b4a-4392-8170-6f5e4d3c2b1a",
  email: "owner@example.com",
  displayName: "Owner",
  roles: ["OWNER"],
  permissions: ["*"],
  bootstrap: false,
};

export const hasFor = (me: Me) => createHasPermission(me.permissions);
