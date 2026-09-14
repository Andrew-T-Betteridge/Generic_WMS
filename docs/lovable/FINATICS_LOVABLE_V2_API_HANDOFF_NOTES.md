# Lovable V2 API handoff notes

Do not hand this to Lovable as the final production contract until clean build/test 014 is green and Stripe/auth are integrated.

Lovable may design against these routes immediately, but must respect these rules:
- WMS/API is source of truth for price and stock.
- `AVAILABLE` means purchasable now. `GROWING`/`COMING_SOON` means interest/reservation request, not normal checkout. `OUT_OF_STOCK` means waitlist.
- Reviews returned by the API are real approved reviews only.
- Do not invent viewer counts or scarcity.
- Affiliate click API must be called before navigating to merchant URL.
- Reservation routes are for limited stock when delivery needs arranging.
- Delivery choices come from `/api/delivery/options` or `/api/checkout/quote`, never hard-coded.
- Payment provider is not live until API returns a real provider integration rather than `providerIntegrated:false`.
