# FINatics / Lovable V3 API handoff rules

Lovable builds UI. DYNETIC WMS owns catalogue, stock, pricing, delivery eligibility,
reservations, orders, payments and operational state.

Hard rules:

1. Never connect Lovable/Supabase directly to PostgreSQL operational tables.
2. Never create a second product/order/payment source of truth in Supabase.
3. Use only the documented DYNETIC WMS HTTP API.
4. Never trust a browser payment-success redirect as proof of payment.
   Display status returned by DYNETIC WMS after Stripe webhook processing.
5. Never submit an arbitrary payment amount. `POST /api/payments/prepare`
   accepts a reference and DYNETIC WMS calculates the amount.
6. Registered-user routes use Bearer JWT from the selected OIDC provider.
7. Guest checkout remains supported. Store the returned `orderAccessToken`
   securely for the order-confirmation/status flow and send it only as
   `X-Order-Access-Token`.
8. Do not invent stock, prices, delivery availability, reviews, genetics,
   scarcity, viewer counts, payment state or fulfilment state.
9. Admin endpoints are not customer UI endpoints.
10. Stripe client secret may be used by Stripe's client component; Stripe secret
    key and webhook secret are server-only and never exposed to Lovable.
