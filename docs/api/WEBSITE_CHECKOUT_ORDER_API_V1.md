# Website Checkout & Order API V1

## Boundary

The browser never writes operational WMS tables.

Storefront -> Fastify API -> `api.*` functions -> `interface.ORDER_*_IF` -> `interface.PROCESS_ORDER_INTERFACE` -> `core.ORDER_*`.

## Basket validation

`POST /api/checkout/validate`

Reprices every line from `core.PRODUCT_VARIANT.WEB_PRICE`.

The client/browser price is never trusted.

Availability is calculated from the live catalogue availability view.

## Checkout quote

`POST /api/checkout/quote`

Returns available fulfilment choices without hard-coding FINatics into the WMS engine.

V1 intentionally leaves parcel/local delivery price as `null` where a real carrier/distance calculation is not yet available. The UI must say that the charge/date will be confirmed, rather than inventing a price.

Livestock carrier availability respects `config.DELIVERY_CLASS_CONTROL`.

Mixed STANDARD + LIVESTOCK baskets expose `SPLIT_WHEN_REQUIRED`.

## Order submission

`POST /api/orders`

Requires an `idempotencyKey`.

The backend:
1. revalidates stock and prices;
2. creates a delivery-address snapshot;
3. creates `interface.ORDER_HEADER_IF`;
4. creates `interface.ORDER_LINE_IF`;
5. calls `interface.PROCESS_ORDER_INTERFACE`;
6. returns the WMS order ID.

The source system is `WEBSITE`.

Payment remains `PENDING`. A payment provider/webhook is the next integration and should update payment state before automated release/allocation policy is finalised.

## Order status

`GET /api/orders/{orderId}`

Returns a customer-safe projection of:
- order state;
- payment state;
- fulfilment state;
- lines;
- shipment/container tracking.

## Important V1 limitation

Order lookup is currently by order ID and does not include customer authentication. Do not expose arbitrary order-status lookup publicly in production until account/session or signed-reference security is added.
