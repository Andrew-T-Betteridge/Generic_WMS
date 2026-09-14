# Website API V1

## Current endpoints

### GET /health

Checks API + PostgreSQL connectivity.

### GET /api/catalog/products

Optional query:

`?category=breeding-equipment`

Returns active products with prices and aggregate available stock.

### GET /api/catalog/products/:slug

Returns:

- product content;
- category;
- delivery class;
- media metadata;
- specifications;
- active variants;
- variant options;
- live available-to-sell quantity from WMS inventory.

## Security rule

The browser does not connect to PostgreSQL directly.

The storefront only talks to the API service.

The API uses parameterised queries and only calls deliberate API database
functions/views.

## Next API block

After the catalogue is visible in-browser, implement:

- POST /api/checkout/quote
- POST /api/orders
- GET /api/orders/:orderId
- payment provider webhook
- customer/account endpoints later

The order endpoint should write through the existing order-interface workflow
rather than directly into operational ORDER_HEADER / ORDER_LINE.
