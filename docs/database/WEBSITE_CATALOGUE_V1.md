# Website Catalogue V1

## Why PRODUCT is separate from SKU

SKU remains the warehouse/inventory identity.

PRODUCT is what a customer sees.

One PRODUCT may expose many SKU variants. This avoids duplicating product pages
while still allowing precise stock control.

## Tables

### core.PRODUCT_CATEGORY
Customer-facing catalogue navigation.

### core.PRODUCT
One sellable product page.

### core.PRODUCT_VARIANT
Maps one selectable variation to one real SKU.

`OPTION_VALUES` is JSONB in V1 so size/colour and future product option types do
not require extra attribute tables before they are genuinely needed.

## Availability

`api.CATALOG_VARIANT_AVAILABILITY`

Website availability is not marketplace stock and is not manually duplicated.

It derives:

`QTY_ON_HAND - QTY_ALLOCATED`

from the WMS inventory for the actual SKU.

## Fry Tray

Loaded as:

`FRYTRAY001`

Current website sizes:

- Small — 22 cm x 35 cm
- Medium — 34.5 cm x 46 cm

Large is recorded as `NOT_YET_RELEASED` and is not a variant.

There are 11 current colour combinations per size, producing 22 SKU variants.

Website price in the initial seed:

`£26.99`

Inventory is deliberately not seeded. The user can create inventory manually
against the required variant SKU and the website API will then expose it.
