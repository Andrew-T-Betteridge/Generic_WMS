import type { ReactElement } from "react";
import type { Token } from "../admin-api";
import {
  AccessPage, AuditPage, CataloguePage, CommunicationsPage, CustomersPage, DeliveryPage,
  FulfilmentPage, GiftCardsPage, InboundPage, InterfacesPage,
  PaymentsPage, PromotionsPage, ReturnsPage, SystemPage,
  type Me,
} from "../control-plane";
import { ControlCentre } from "../features/dashboard/ControlCentre";
import { ExceptionsPage } from "../features/exceptions/ExceptionsPage";
import { InventoryPage } from "../features/inventory/InventoryPage";
import { OrderDetailPage } from "../features/orders/OrderDetailPage";
import { OrdersPage } from "../features/orders/OrdersPage";
import type { AdminRouteId, HasPermission } from "./admin-routes";

export type PageContext = { token: Token; has: HasPermission; me: Me; environment: string };

export const ROUTE_PAGES: Record<AdminRouteId, (ctx: PageContext) => ReactElement> = {
  dashboard: ({ token, has, environment }) => <ControlCentre token={token} has={has} environment={environment} />,
  orders: ({ token }) => <OrdersPage token={token} />,
  orderDetail: ({ token, has }) => <OrderDetailPage token={token} has={has} />,
  payments: ({ token, has }) => <PaymentsPage token={token} has={has} />,
  returns: ({ token, has }) => <ReturnsPage token={token} has={has} />,
  customers: ({ token }) => <CustomersPage token={token} />,
  inventory: ({ token, has }) => <InventoryPage token={token} has={has} />,
  fulfilment: ({ token, has }) => <FulfilmentPage token={token} has={has} />,
  catalogue: ({ token, has }) => <CataloguePage token={token} has={has} />,
  promotions: ({ token, has }) => <PromotionsPage token={token} has={has} />,
  giftcards: ({ token, has }) => <GiftCardsPage token={token} has={has} />,
  inbound: ({ token, has }) => <InboundPage token={token} has={has} />,
  delivery: ({ token }) => <DeliveryPage token={token} />,
  communications: ({ token, has }) => <CommunicationsPage token={token} has={has} />,
  interfaces: ({ token, has }) => <InterfacesPage token={token} has={has} />,
  exceptions: ({ token }) => <ExceptionsPage token={token} />,
  audit: ({ token }) => <AuditPage token={token} />,
  access: ({ token, has }) => <AccessPage token={token} has={has} />,
  system: ({ token }) => <SystemPage token={token} />,
};
