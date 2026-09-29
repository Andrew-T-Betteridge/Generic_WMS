import type { Me } from "../control-plane";

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

export const hasFor = (me: Me) => (permission: string) => me.permissions.includes(permission);
