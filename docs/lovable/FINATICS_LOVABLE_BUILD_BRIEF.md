# FINatics Aquatics — Lovable Build Brief

## Mission

Build the production-quality customer storefront for FINatics Aquatics.

The backend/WMS already exists. Do **not** recreate, replace or directly connect to PostgreSQL.

All business data and order transactions must use the supplied HTTP API.

## Technical boundary

Use:

`VITE_API_URL`

Local development:

`http://localhost:3001`

Never:
- connect directly to PostgreSQL;
- create Supabase product/order tables;
- duplicate inventory;
- invent stock quantities;
- invent delivery eligibility;
- calculate trusted prices in the browser;
- bypass the API and write WMS tables.

The API is the source of truth.

## Brand direction

FINatics Aquatics should feel:
- premium but accessible;
- specialist rather than generic pet-shop;
- modern aquatics / clean water / fish-room credibility;
- photography-led;
- strong mobile experience;
- trustworthy enough for livestock purchases;
- practical, not luxury-fashion.

Avoid:
- cartoon fish everywhere;
- neon aquarium-shop styling;
- cluttered marketplace appearance;
- generic SaaS cards;
- huge empty hero areas;
- fake reviews or fake stock urgency.

Use the existing FINatics Aquatics wordmark/logo if supplied as an asset.

## Site structure

### Home
- strong visual hero using real fish/product photography;
- clear routes to Shop Fish, Breeding Equipment, Food, Offers;
- featured products;
- "bred / tested in our own fish room" credibility;
- delivery information;
- latest/featured livestock;
- concise trust section;
- WhatsApp/contact CTA where appropriate.

### Shop
- product grid from `GET /api/catalog/products`;
- category filtering;
- price;
- stock state;
- delivery-class messaging where relevant;
- search/filter UX that can expand later.

### Product
Use `GET /api/catalog/products/{slug}`.

Must support:
- gallery;
- product title/brand;
- description;
- price;
- variant selectors from returned `options`;
- stock availability per variant;
- quantity;
- add to basket;
- SKU hidden from primary UX but available in detail/diagnostic area;
- delivery-class information.

Do not assume every product uses size + colour. Build variant selectors dynamically from `options`.

### Basket
Persist locally until accounts are implemented.

Before showing checkout as ready, call:

`POST /api/checkout/validate`

Always replace browser-computed pricing/availability with the API response.

Show actionable errors such as changed stock.

### Checkout
Collect:
- name;
- email;
- mobile/phone;
- delivery address;
- postcode;
- country.

Call:

`POST /api/checkout/quote`

Render only the returned `fulfilmentOptions`.

For mixed live + non-live orders make the difference very clear:

**Consolidate / wait**
Live and non-live goods stay together where operationally suitable.

**Send non-live items first**
Non-live products may arrive on a different day from livestock.

Never imply livestock and dry goods will definitely arrive together.

If an option has:
`requiresManualConfirmation: true`

show a clear message that FINatics will confirm the final delivery day/charge.

### Order submission

Generate a stable UUID once when checkout submission begins and use it as:

`idempotencyKey`

Keep the same key if the request is retried.

POST to:

`/api/orders`

Successful response includes `orderId`.

Navigate to an order confirmation page.

### Order confirmation
Show:
- order number;
- payment state;
- chosen fulfilment route;
- clear next-step text.

Payment is not yet integrated. Build the page so a payment step/provider can be inserted without redesigning checkout.

### Order tracking
API exists:

`GET /api/orders/{orderId}`

Do not expose an unrestricted public order-ID search page yet. Production access will later be protected by customer account/session or signed reference.

## Existing real launch product

Product ID:
`FRYTRAY001`

Name:
`Finatics Aquatics Air-Driven Fry Tray`

Current released sizes:
- Small — 22 cm x 35 cm
- Medium — 34.5 cm x 46 cm

Large is not yet released and must not be invented.

Current variants and availability come entirely from API data.

## Responsive requirements

Design mobile-first.

Critical flows must work comfortably at:
- 360 px;
- 390 px;
- tablet;
- desktop.

Mobile:
- sticky add-to-basket on product pages where useful;
- basket accessible from header;
- variant controls easy to tap;
- no horizontal overflow;
- checkout inputs optimised for phone entry.

## Accessibility
- semantic HTML;
- keyboard usable;
- visible focus states;
- form labels;
- sufficient contrast;
- alt text;
- errors announced clearly.

## API endpoints

- `GET /health`
- `GET /api/catalog/products`
- `GET /api/catalog/products/{slug}`
- `POST /api/checkout/validate`
- `POST /api/checkout/quote`
- `POST /api/orders`
- `GET /api/orders/{orderId}`

See the supplied OpenAPI file for payloads.

## State rules

### Catalogue
Backend data wins.

### Basket
Local state is fine, but validate before checkout.

### Prices
Never trust local price values during checkout/order submission.

### Stock
Never claim availability unless API says it is available.

### Delivery
Never create delivery options not returned by `/api/checkout/quote`.

## Not in first Lovable release

Do not block launch on:
- WMS/admin console;
- receiving;
- supplier portals;
- affiliate system;
- advanced account management;
- weather automation;
- advanced carrier-label integration;
- large Fry Tray variant;
- CMS complexity.

## First delivery expected from Lovable

Produce:
1. polished homepage;
2. category/shop page;
3. dynamic product page;
4. basket;
5. checkout;
6. fulfilment-choice UI;
7. order confirmation;
8. responsive header/footer;
9. API client layer;
10. loading/error/empty states.

Keep the implementation modular so customer accounts, payments, gift cards and additional catalogue types can be added later.
