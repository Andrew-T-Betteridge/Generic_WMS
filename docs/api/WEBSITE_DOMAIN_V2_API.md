# Website Domain V2 API

This layer extends the existing catalogue/checkout/order API without making Lovable or a browser a second system of record.

## Public/customer routes
- GET `/health`
- GET `/api/catalog/categories`
- GET `/api/catalog/products`
- GET `/api/catalog/search`
- GET `/api/catalog/products/:slug`
- GET `/api/catalog/products/:slug/media`
- GET `/api/catalog/products/:slug/affiliate-links`
- GET `/api/catalog/products/:slug/reviews`
- POST `/api/catalog/products/:slug/reviews` (moderated/PENDING)
- POST `/api/checkout/validate`
- POST `/api/delivery/options`
- POST `/api/checkout/quote`
- POST `/api/promotions/validate`
- POST `/api/gift-cards/balance`
- POST `/api/interests`
- POST `/api/reservations`
- POST `/api/reservations/:reservationId/convert`
- GET `/api/reservations/:reservationId`
- DELETE `/api/reservations/:reservationId`
- POST `/api/affiliate/click`
- POST `/api/preferences`
- POST `/api/payments/prepare`
- POST `/api/orders`
- GET `/api/orders/:orderId`

## Important security boundary
The current local-development server exposes reservation/order lookups without customer authentication. Do not publish arbitrary identifier lookup in production. Before internet launch, bind order/reservation/account routes to authenticated customer identity or a signed short-lived order reference.

`/api/payments/prepare` persists and tests the provider-neutral payment contract only. It deliberately does not fake Stripe/PayPal integration and returns `providerIntegrated:false` until provider adapters/webhooks are implemented.

## Operational/admin functions not exposed as anonymous HTTP
- `api.GET_INTEREST_SUMMARY`
- `api.EXPIRE_STOCK_RESERVATIONS`
- review approval/rejection remains an authenticated admin operation
- waitlist notification sending remains an authenticated admin operation

This is intentional: public API coverage does not mean internal controls should be anonymous endpoints.
