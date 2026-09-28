# Lovable Admin API Contract — DYNETIC WMS 0.3.14

Canonical admin operations are owned by `admin-operations.ts`.

Important: HTTP method + path together identify a route. It is valid to have:

- `GET /api/admin/orders/:orderId`
- `PATCH /api/admin/orders/:orderId`

because these are distinct Fastify routes.

Lovable must call backend operations rather than setting WMS status directly.

Primary route families:

- Dashboard and exceptions
- Orders, order actions, amendments, allocation/deallocation/cancel
- Inventory lookup, adjustment and movement
- Picks and shipments
- Payments and refunds
- Returns / DOA / claims
- Notification and interface recovery
- Suppliers / pre-advice
- Promotions / gift cards
- Carrier/delivery data
- Audit and system health

Legacy v0.3.13 order/inventory GET endpoints are namespaced beneath:

`/api/admin/legacy-v0313/*`

and should not be used for new frontend work.
