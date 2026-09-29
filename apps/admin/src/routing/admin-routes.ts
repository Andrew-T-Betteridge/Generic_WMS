import { matchPath } from "react-router";
import type { HasPermission } from "../lib/permissions";

// Route table for the existing Admin screens.
// Permissions are copied unchanged from the previous state-based navigation:
// a route is available when the user holds ANY of the listed permissions.
// These checks only control presentation; the WMS API remains authoritative.

export type AdminRouteId =
  | "orderDetail"
  | "dashboard" | "orders" | "payments" | "returns" | "customers" | "inventory" | "fulfilment"
  | "catalogue" | "promotions" | "giftcards"
  | "inbound" | "delivery"
  | "communications" | "interfaces" | "exceptions" | "audit" | "access" | "system";

export type AdminRoute = {
  id: AdminRouteId;
  path: string;
  label: string;
  section: string;
  permissions: string[];
  /** Record-detail routes are reachable by link only and never appear in navigation. */
  parent?: AdminRouteId;
};

export const ADMIN_ROUTES: AdminRoute[] = [
  { id: "dashboard", path: "/", label: "Control centre", section: "Operations", permissions: ["dashboard.read"] },
  { id: "orders", path: "/orders", label: "Orders", section: "Operations", permissions: ["order.read"] },
  { id: "orderDetail", path: "/orders/:orderId", label: "Order", section: "Operations", permissions: ["order.read"], parent: "orders" },
  { id: "payments", path: "/payments", label: "Payments", section: "Operations", permissions: ["payment.read"] },
  { id: "returns", path: "/returns", label: "Returns & claims", section: "Operations", permissions: ["return.read"] },
  { id: "customers", path: "/customers", label: "Customers", section: "Operations", permissions: ["order.read"] },
  { id: "inventory", path: "/inventory", label: "Inventory", section: "Operations", permissions: ["inventory.read"] },
  { id: "fulfilment", path: "/fulfilment", label: "Fulfilment", section: "Operations", permissions: ["pick.read", "shipment.read"] },
  { id: "catalogue", path: "/catalogue", label: "Catalogue", section: "Commercial", permissions: ["product.read"] },
  { id: "promotions", path: "/promotions", label: "Promotions", section: "Commercial", permissions: ["config.read"] },
  { id: "giftcards", path: "/gift-cards", label: "Gift cards", section: "Commercial", permissions: ["giftcard.read"] },
  { id: "inbound", path: "/inbound", label: "Inbound", section: "Supply & delivery", permissions: ["supplier.read", "pre_advice.read"] },
  { id: "delivery", path: "/delivery", label: "Delivery", section: "Supply & delivery", permissions: ["carrier.read"] },
  { id: "communications", path: "/communications", label: "Communications", section: "Platform", permissions: ["notification.read"] },
  { id: "interfaces", path: "/interfaces", label: "Interfaces", section: "Platform", permissions: ["interface.read"] },
  { id: "exceptions", path: "/exceptions", label: "Exceptions", section: "Platform", permissions: ["exception.read"] },
  { id: "audit", path: "/audit", label: "Audit", section: "Platform", permissions: ["audit.read"] },
  { id: "access", path: "/access", label: "Users & roles", section: "Platform", permissions: ["user.read"] },
  { id: "system", path: "/system", label: "System", section: "Platform", permissions: ["system.read"] },
];

export type { HasPermission } from "../lib/permissions";

export function canAccessRoute(route: AdminRoute, has: HasPermission): boolean {
  return route.permissions.some(has);
}

export type RouteMatch = { route: AdminRoute; params: Record<string, string | undefined> };

export function matchRoute(pathname: string): RouteMatch | undefined {
  const normalised = pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;
  for (const route of ADMIN_ROUTES) {
    const m = matchPath({ path: route.path, end: true }, normalised);
    if (m) return { route, params: m.params };
  }
  return undefined;
}

export function findRouteByPath(pathname: string): AdminRoute | undefined {
  return matchRoute(pathname)?.route;
}

export function routeById(id: AdminRouteId): AdminRoute {
  return ADMIN_ROUTES.find((r) => r.id === id)!;
}

/** Routes that belong in the sidebar (excludes record-detail routes). */
export const NAV_ROUTES = ADMIN_ROUTES.filter((r) => !r.parent);

export type NavSection = { label: string; routes: AdminRoute[] };

export function visibleNavSections(has: HasPermission): NavSection[] {
  const sections: NavSection[] = [];
  for (const route of NAV_ROUTES) {
    if (!canAccessRoute(route, has)) continue;
    let section = sections.find((s) => s.label === route.section);
    if (!section) {
      section = { label: route.section, routes: [] };
      sections.push(section);
    }
    section.routes.push(route);
  }
  return sections;
}

/** First route the user may open; mirrors the previous "dashboard, else first available" fallback. */
export function firstAccessibleRoute(has: HasPermission): AdminRoute | undefined {
  return NAV_ROUTES.find((route) => canAccessRoute(route, has));
}
