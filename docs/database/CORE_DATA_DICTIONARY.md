# Core Data Dictionary

Source: refined FINatics_DB_Keep_Only specification.

## SKU

| Column | Type | Required | Action | Purpose |
|---|---|---:|---|---|
| CLIENT_ID | VARCHAR(10) | Y | KEEP | Client/business identifier |
| SKU_ID | VARCHAR(50) | Y | KEEP | Single FINatics SKU/product identifier |
| EAN | VARCHAR(14) | N | KEEP | Optional barcode/product identifier |
| UPC | VARCHAR(14) | N | KEEP | Optional barcode/product identifier |
| DESCRIPTION | VARCHAR(80) | N | KEEP | Operational item description |
| PRODUCT_GROUP | VARCHAR(10) | N | KEEP | Top-level product hierarchy |
| EACH_HEIGHT | NUMERIC(15,6) | N | KEEP | Physical product dimension/weight |
| EACH_WEIGHT | NUMERIC(13,6) | N | KEEP | Physical product dimension/weight |
| EACH_VOLUME | NUMERIC(13,6) | N | KEEP | Physical product dimension/weight |
| EACH_VALUE | NUMERIC(12,3) | N | KEEP | Existing WMS field retained for FINatics |
| SHELF_LIFE | NUMERIC(5) | N | KEEP | Useful for food/dated stock |
| EXPIRY_REQD | VARCHAR(1) | N | KEEP | Useful for food/dated stock |
| OBSOLETE_PRODUCT | VARCHAR(1) | N | KEEP | Product lifecycle control |
| NEW_PRODUCT | VARCHAR(1) | N | KEEP | Product lifecycle control |
| COLOUR | VARCHAR(20) | N | KEEP | Colour/visual classification |
| SKU_SIZE | VARCHAR(10) | N | KEEP | Size sold/handled |
| EACH_WIDTH | NUMERIC(7,3) | N | KEEP | Physical product dimension/weight |
| EACH_DEPTH | NUMERIC(7,3) | N | KEEP | Physical product dimension/weight |
| REORDER_TRIGGER_QTY | NUMERIC(15,6) | N | KEEP | Stock replenishment threshold |
| LOW_TRIGGER_QTY | NUMERIC(15,6) | N | KEEP | Stock replenishment threshold |
| CREATED_BY | VARCHAR(20) | N | KEEP | Audit field |
| CREATION_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| LAST_UPDATED_BY | VARCHAR(20) | N | KEEP | Audit field |
| LAST_UPDATE_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| COMMODITY_CODE | VARCHAR(22) | N | KEEP | Existing WMS field retained for FINatics |
| FAMILY_GROUP | VARCHAR(15) | N | KEEP | Second-level product hierarchy |
| FRAGILE | VARCHAR(1) | N | KEEP | Dispatch/handling property |
| ECOMMERCE | VARCHAR(1) | N | KEEP | Existing ecommerce eligibility flag |
| PROMOTION | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| STYLE | VARCHAR(10) | N | KEEP | Existing style/variant classification field |
| DECATALOGUED | VARCHAR(1) | N | KEEP | Product lifecycle control |
| HAZMAT | VARCHAR(1) | N | KEEP | Dispatch/handling property |
| SUB_GROUP | VARCHAR(30) | N | ADD | 3rd category level |
| CATEGORY | VARCHAR(50) | N | ADD | 4th category/product family level |
| MANUFACTURER_ID | VARCHAR(30) | N | ADD | Manufacturer identifier |
| MANUFACTURER_SKU | VARCHAR(80) | N | ADD | Manufacturer's own product code |
| BRAND_NAME | VARCHAR(80) | N | ADD | Customer-facing brand |
| PREFERRED_SUPPLIER_ID | VARCHAR(30) | N | ADD | Preferred source when purchasing stock |
| SUPPLIER_SKU | VARCHAR(80) | N | ADD | Supplier product reference |
| SELL_PRICE | NUMERIC(12,2) | N | ADD | Current FINatics selling price |
| COST_PRICE | NUMERIC(12,2) | N | ADD | Current expected unit cost |
| VAT_RATE | NUMERIC(5,2) | N | ADD | VAT percentage used for web pricing |
| WEB_TITLE | VARCHAR(160) | N | ADD | SEO/customer product title; DESCRIPTION remains operational description |
| WEB_DESCRIPTION | TEXT | N | ADD | Full customer-facing product description |
| WEB_SLUG | VARCHAR(180) | N | ADD | Stable product page path |
| WEB_ACTIVE | CHAR(1) | Y | ADD | Whether the SKU appears on the website |
| WEB_FEATURED | CHAR(1) | Y | ADD | Homepage/featured product flag |
| WEB_IMAGE_1 | TEXT | N | ADD | Primary product image URL/path |
| WEB_IMAGE_2 | TEXT | N | ADD | Additional image URL/path |
| WEB_IMAGE_3 | TEXT | N | ADD | Additional image URL/path |
| WEB_IMAGE_4 | TEXT | N | ADD | Additional image URL/path |
| WEB_IMAGE_5 | TEXT | N | ADD | Additional image URL/path |
| WEB_VIDEO_URL | TEXT | N | ADD | Optional product/fish video |
| FULFILMENT_TYPE | VARCHAR(20) | N | ADD | Default fulfilment route |
| SUPPLIER_DIRECT_ENABLED | CHAR(1) | Y | ADD | Allow supplier-direct fallback |
| AFFILIATE_FALLBACK | CHAR(1) | Y | ADD | Allow affiliate route when own/supplier stock unavailable |
| AFFILIATE_URL | TEXT | N | ADD | External tracked affiliate URL |
| MIN_ORDER_QTY | NUMERIC(15,6) | N | ADD | Minimum purchasable quantity |
| MAX_ORDER_QTY | NUMERIC(15,6) | N | ADD | Maximum quantity per order if required |
| GENUS | VARCHAR(80) | N | ADD | Fish only - genus |
| SPECIES | VARCHAR(120) | N | ADD | Fish only - species/strain name |
| LINEAGE | VARCHAR(20) | N | ADD | Fish only - lineage |
| SEX | VARCHAR(20) | N | ADD | Fish only - sex where sold by sex |
| ADULT_SIZE_CM | NUMERIC(6,2) | N | ADD | Fish only - expected adult size |
| CARE_NOTES | TEXT | N | ADD | Fish only - care / compatibility notes |
| COMING_SOON | CHAR(1) | Y | ADD | Display product before stock is sellable |
| AVAILABLE_DSTAMP | TIMESTAMPTZ | N | ADD | Expected availability date/time |

## LOCATION

| Column | Type | Required | Action | Purpose |
|---|---|---:|---|---|
| SITE_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| LOCATION_ID | VARCHAR(20) | Y | KEEP | Inventory/location identifier |
| ZONE_1 | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| SUBZONE_1 | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| SUBZONE_2 | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| STORAGE_CLASS | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| LOC_TYPE | VARCHAR(15) | Y | KEEP | Existing WMS field retained for FINatics |
| LOCK_STATUS | VARCHAR(20) | Y | KEEP | Inventory/location hold state |
| VOLUME | NUMERIC(13,6) | Y | KEEP | Existing WMS field retained for FINatics |
| HEIGHT | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| DEPTH | NUMERIC(7,3) | N | KEEP | Existing WMS field retained for FINatics |
| WIDTH | NUMERIC(7,3) | N | KEEP | Existing WMS field retained for FINatics |
| WEIGHT | NUMERIC(13,6) | N | KEEP | Existing WMS field retained for FINatics |
| DISALLOW_ALLOC | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| COUNT_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| PICK_FACE | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| COUNT_NEEDED | VARCHAR(1) | Y | KEEP | Existing WMS field retained for FINatics |
| AISLE | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| BAY | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| LEVELS | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| POSITION | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| LOCALITY | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| MAX_UNITS_ON_LOC | NUMERIC(10) | N | KEEP | Existing WMS field retained for FINatics |
| ID | NUMERIC | Y | KEEP | Existing WMS field retained for FINatics |
| DESCRIPTION | VARCHAR(120) | N | ADD | Friendly location/tank description |
| ACTIVE | CHAR(1) | Y | ADD | Whether location is operational |
| LIVESTOCK_ALLOWED | CHAR(1) | Y | ADD | Whether livestock can be held here |

## ADDRESS

| Column | Type | Required | Action | Purpose |
|---|---|---:|---|---|
| CLIENT_ID | VARCHAR(10) | Y | KEEP | Client/business identifier |
| ADDRESS_ID | VARCHAR(15) | Y | KEEP | Customer/billing/delivery address snapshot |
| ADDRESS_TYPE | VARCHAR(10) | N | KEEP | Customer/billing/delivery address snapshot |
| CONTACT | VARCHAR(25) | N | KEEP | Customer/billing/delivery address snapshot |
| CONTACT_PHONE | VARCHAR(25) | N | KEEP | Existing WMS field retained for FINatics |
| CONTACT_MOBILE | VARCHAR(25) | N | KEEP | Existing WMS field retained for FINatics |
| CONTACT_EMAIL | VARCHAR(256) | N | KEEP | Existing WMS field retained for FINatics |
| NAME | VARCHAR(50) | N | KEEP | Customer/billing/delivery address snapshot |
| ADDRESS1 | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| ADDRESS2 | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| TOWN | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| COUNTY | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| POSTCODE | VARCHAR(20) | N | KEEP | Customer/billing/delivery address snapshot |
| COUNTRY | VARCHAR(25) | N | KEEP | Customer/billing/delivery address snapshot |
| DIRECTIONS | VARCHAR(180) | N | KEEP | Existing WMS field retained for FINatics |
| URL | VARCHAR(250) | N | KEEP | Existing WMS field retained for FINatics |
| VAT_NUMBER | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_OPEN_TIME | TIMESTAMPTZ | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_CLOSE_TIME | TIMESTAMPTZ | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_OPEN_MON | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_OPEN_TUE | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_OPEN_WED | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_OPEN_THUR | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_OPEN_FRI | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_OPEN_SAT | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| DELIVERY_OPEN_SUN | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| FASTEST_CARRIER | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| CHEAPEST_CARRIER | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| FREIGHT_CHARGES | VARCHAR(10) | N | KEEP | Delivery/freight charge/cost |
| CUSTOMER_TYPE | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| CREDIT_STATUS | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| CREDIT_DAYS | NUMERIC(4) | N | KEEP | Existing WMS field retained for FINatics |
| RETAILER_ID | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| LATITUDE | NUMERIC(10,7) | N | ADD | Cached latitude for distance-based delivery |
| LONGITUDE | NUMERIC(10,7) | N | ADD | Cached longitude for distance-based delivery |
| ACTIVE | CHAR(1) | Y | ADD | Whether address record is active |
| DEFAULT_BILLING | CHAR(1) | Y | ADD | Default billing address flag |
| DEFAULT_DELIVERY | CHAR(1) | Y | ADD | Default delivery address flag |

## INVENTORY

| Column | Type | Required | Action | Purpose |
|---|---|---:|---|---|
| KEY | NUMERIC(10) | Y | KEEP | Existing WMS field retained for FINatics |
| TAG_ID | VARCHAR(50) | N | KEEP | Existing WMS field retained for FINatics |
| CONTAINER_ID | VARCHAR(50) | N | KEEP | Existing WMS field retained for FINatics |
| CLIENT_ID | VARCHAR(10) | Y | KEEP | Client/business identifier |
| SKU_ID | VARCHAR(50) | Y | KEEP | Single FINatics SKU/product identifier |
| SITE_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| LOCATION_ID | VARCHAR(20) | Y | KEEP | Inventory/location identifier |
| OWNER_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| QTY_ON_HAND | NUMERIC(15,6) | Y | KEEP | Physical quantity currently held |
| QTY_ALLOCATED | NUMERIC(15,6) | Y | KEEP | Quantity allocated/reserved to demand |
| ORIGIN_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| CONDITION_ID | VARCHAR(10) | N | KEEP | Inventory condition, useful for AVAILABLE/QUARANTINE etc. |
| LOCK_STATUS | VARCHAR(20) | Y | KEEP | Inventory/location hold state |
| LOCK_CODE | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| RECEIPT_DSTAMP | TIMESTAMPTZ | Y | KEEP | Audit/operational timestamp |
| MOVE_DSTAMP | TIMESTAMPTZ | Y | KEEP | Audit/operational timestamp |
| RECEIPT_TYPE | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| RECEIPT_ID | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| LINE_ID | NUMERIC(6) | N | KEEP | Order line number |
| QC_STATUS | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| BATCH_ID | VARCHAR(50) | N | KEEP | Batch/spawn/lot identifier |
| EXPIRY_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| MANUF_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| COUNT_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| COUNT_NEEDED | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| SUPPLIER_ID | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| DESCRIPTION | VARCHAR(80) | N | KEEP | Operational item description |
| NOTES | VARCHAR(80) | N | KEEP | Existing WMS field retained for FINatics |
| DISALLOW_ALLOC | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| UNIT_COST | NUMERIC(12,2) | N | ADD | Actual unit cost for this stock/batch |

## ORDER_HEADER

| Column | Type | Required | Action | Purpose |
|---|---|---:|---|---|
| CLIENT_ID | VARCHAR(10) | Y | KEEP | Client/business identifier |
| ORDER_ID | VARCHAR(20) | Y | KEEP | Order identifier |
| ORDER_TYPE | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| STATUS | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| PRIORITY | NUMERIC(4) | N | KEEP | Existing WMS field retained for FINatics |
| CONSIGNMENT | VARCHAR(20) | N | KEEP | Internal consignment reference |
| DELIVERY_POINT | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| FROM_SITE_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| TO_SITE_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| OWNER_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| CUSTOMER_ID | VARCHAR(15) | N | KEEP | Customer identifier |
| ORDER_DATE | TIMESTAMPTZ | Y | KEEP | Audit/operational timestamp |
| SHIP_BY_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| DELIVER_BY_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| SHIPPED_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| DELIVERED_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| SIGNATORY | VARCHAR(25) | N | KEEP | Existing WMS field retained for FINatics |
| PURCHASE_ORDER | VARCHAR(25) | N | KEEP | Existing WMS field retained for FINatics |
| CARRIER_ID | VARCHAR(25) | N | KEEP | Carrier identifier |
| DISPATCH_METHOD | VARCHAR(40) | N | KEEP | Dispatch method |
| SERVICE_LEVEL | VARCHAR(40) | N | KEEP | Carrier/service level |
| INV_ADDRESS_ID | VARCHAR(15) | N | KEEP | Customer/billing/delivery address snapshot |
| INV_CONTACT | VARCHAR(25) | N | KEEP | Invoice/billing information |
| INV_CONTACT_PHONE | VARCHAR(25) | N | KEEP | Invoice/billing information |
| INV_CONTACT_MOBILE | VARCHAR(25) | N | KEEP | Invoice/billing information |
| INV_CONTACT_EMAIL | VARCHAR(256) | N | KEEP | Invoice/billing information |
| INV_NAME | VARCHAR(50) | N | KEEP | Invoice/billing information |
| INV_ADDRESS1 | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| INV_ADDRESS2 | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| INV_TOWN | VARCHAR(60) | N | KEEP | Invoice/billing information |
| INV_COUNTY | VARCHAR(60) | N | KEEP | Invoice/billing information |
| INV_POSTCODE | VARCHAR(20) | N | KEEP | Invoice/billing information |
| INV_COUNTRY | VARCHAR(25) | N | KEEP | Invoice/billing information |
| INSTRUCTIONS | VARCHAR(180) | N | KEEP | Existing WMS field retained for FINatics |
| ORDER_VOLUME | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| ORDER_WEIGHT | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| CONTACT | VARCHAR(25) | N | KEEP | Customer/billing/delivery address snapshot |
| CONTACT_PHONE | VARCHAR(25) | N | KEEP | Existing WMS field retained for FINatics |
| CONTACT_MOBILE | VARCHAR(25) | N | KEEP | Existing WMS field retained for FINatics |
| CONTACT_EMAIL | VARCHAR(256) | N | KEEP | Existing WMS field retained for FINatics |
| NAME | VARCHAR(50) | N | KEEP | Customer/billing/delivery address snapshot |
| ADDRESS1 | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| ADDRESS2 | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| TOWN | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| COUNTY | VARCHAR(60) | N | KEEP | Customer/billing/delivery address snapshot |
| POSTCODE | VARCHAR(20) | N | KEEP | Customer/billing/delivery address snapshot |
| COUNTRY | VARCHAR(25) | N | KEEP | Customer/billing/delivery address snapshot |
| NO_SHIPMENT_EMAIL | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| ORDER_SOURCE | VARCHAR(1) | N | KEEP | Order source e.g. WEB/FACEBOOK/MANUAL |
| NUM_LINES | NUMERIC(6) | N | KEEP | Existing WMS field retained for FINatics |
| CREATED_BY | VARCHAR(20) | N | KEEP | Audit field |
| CREATION_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| LAST_UPDATED_BY | VARCHAR(20) | N | KEEP | Audit field |
| LAST_UPDATE_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| STATUS_REASON_CODE | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| ARCHIVED | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| CLOSURE_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| ORDER_CLOSED | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| ORDER_VALUE | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| EXPECTED_VOLUME | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| EXPECTED_WEIGHT | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| EXPECTED_VALUE | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| LANGUAGE | VARCHAR(8) | N | KEEP | Existing WMS field retained for FINatics |
| VAT_NUMBER | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| INV_VAT_NUMBER | VARCHAR(20) | N | KEEP | Invoice/billing information |
| INV_REFERENCE | VARCHAR(35) | N | KEEP | Invoice/billing information |
| INV_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| INV_CURRENCY | VARCHAR(3) | N | KEEP | Invoice/billing information |
| PAYMENT_TERMS | VARCHAR(35) | N | KEEP | Existing WMS field retained for FINatics |
| SUBTOTAL_1 | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| FREIGHT_COST | NUMERIC(12,3) | N | KEEP | Delivery/freight charge/cost |
| DISCOUNT | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| TAX_RATE_1 | NUMERIC(12,3) | N | KEEP | Existing WMS field retained for FINatics |
| TAX_AMOUNT_1 | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| ORDER_REFERENCE | VARCHAR(35) | N | KEEP | Existing WMS field retained for FINatics |
| PACKING_NOTES | VARCHAR(200) | N | KEEP | Existing WMS field retained for FINatics |
| PAYMENT_STATUS | VARCHAR(20) | N | ADD | Payment state |
| PAYMENT_METHOD | VARCHAR(30) | N | ADD | Payment method |
| PAYMENT_REFERENCE | VARCHAR(120) | N | ADD | Stripe/provider payment reference |
| PAYMENT_DSTAMP | TIMESTAMPTZ | N | ADD | When payment completed |
| FULFILMENT_STATUS | VARCHAR(30) | N | ADD | Overall fulfilment state |
| PROMO_CODE | VARCHAR(50) | N | ADD | Promotion code used |
| FREE_DELIVERY | CHAR(1) | Y | ADD | Whether delivery charge was waived |
| DELIVERY_DISTANCE_MILES | NUMERIC(8,2) | N | ADD | Calculated distance used for local delivery pricing |

## ORDER_LINE

| Column | Type | Required | Action | Purpose |
|---|---|---:|---|---|
| CLIENT_ID | VARCHAR(10) | Y | KEEP | Client/business identifier |
| ORDER_ID | VARCHAR(20) | Y | KEEP | Order identifier |
| LINE_ID | NUMERIC(6) | Y | KEEP | Order line number |
| SKU_ID | VARCHAR(50) | Y | KEEP | Single FINatics SKU/product identifier |
| BATCH_ID | VARCHAR(50) | N | KEEP | Batch/spawn/lot identifier |
| CONDITION_ID | VARCHAR(10) | N | KEEP | Inventory condition, useful for AVAILABLE/QUARANTINE etc. |
| QTY_ORDERED | NUMERIC(15,6) | Y | KEEP | Quantity/status measure retained from WMS |
| QTY_TASKED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| QTY_PICKED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| QTY_SHIPPED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| QTY_DELIVERED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| QTY_RETURNED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| QTY_SOFT_ALLOCATED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| ALLOCATE | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| BACK_ORDERED | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| CREATED_BY | VARCHAR(20) | N | KEEP | Audit field |
| CREATION_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| LAST_UPDATED_BY | VARCHAR(20) | N | KEEP | Audit field |
| LAST_UPDATE_DATE | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| LINE_VALUE | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| NOTES | VARCHAR(80) | N | KEEP | Existing WMS field retained for FINatics |
| MIN_QTY_ORDERED | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| MAX_QTY_ORDERED | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| EXPECTED_VOLUME | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| EXPECTED_WEIGHT | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| EXPECTED_VALUE | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| PRODUCT_PRICE | NUMERIC(12,3) | N | KEEP | Unit sell price captured on the order line |
| PRODUCT_CURRENCY | VARCHAR(3) | N | KEEP | Existing WMS field retained for FINatics |
| EXTENDED_PRICE | NUMERIC(12,3) | N | KEEP | Existing WMS field retained for FINatics |
| TAX_1 | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| TAX_2 | NUMERIC(12,3) | N | KEEP | Commercial value captured for order |
| OWNER_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| LOCATION_ID | VARCHAR(20) | N | KEEP | Inventory/location identifier |
| FULFILMENT_TYPE | VARCHAR(20) | N | ADD | Actual fulfilment route for this line |
| SUPPLIER_ID | VARCHAR(30) | N | ADD | Supplier used for direct fulfilment |
| UNIT_COST | NUMERIC(12,2) | N | ADD | Cost snapshot at order time |
| DISCOUNT_VALUE | NUMERIC(12,2) | N | ADD | Line discount amount |
| VAT_RATE | NUMERIC(5,2) | N | ADD | VAT rate snapshot |
| EXTERNAL_FULFILMENT_REF | VARCHAR(120) | N | ADD | Supplier/external reference where applicable |

## INVENTORY_TRANSACTION

| Column | Type | Required | Action | Purpose |
|---|---|---:|---|---|
| KEY | NUMERIC(10) | Y | KEEP | Existing WMS field retained for FINatics |
| CODE | VARCHAR(40) | Y | KEEP | Inventory transaction code |
| SITE_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| FROM_SITE_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| TO_SITE_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| FROM_LOC_ID | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| TO_LOC_ID | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| FINAL_LOC_ID | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| OWNER_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| CLIENT_ID | VARCHAR(10) | N | KEEP | Client/business identifier |
| SKU_ID | VARCHAR(50) | N | KEEP | Single FINatics SKU/product identifier |
| TAG_ID | VARCHAR(50) | N | KEEP | Existing WMS field retained for FINatics |
| CONTAINER_ID | VARCHAR(50) | N | KEEP | Existing WMS field retained for FINatics |
| BATCH_ID | VARCHAR(50) | N | KEEP | Batch/spawn/lot identifier |
| QC_STATUS | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| EXPIRY_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| MANUF_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| ORIGIN_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| CONDITION_ID | VARCHAR(10) | N | KEEP | Inventory condition, useful for AVAILABLE/QUARANTINE etc. |
| LOCK_STATUS | VARCHAR(20) | N | KEEP | Inventory/location hold state |
| DSTAMP | TIMESTAMPTZ | Y | KEEP | Existing WMS field retained for FINatics |
| CONSIGNMENT | VARCHAR(20) | N | KEEP | Internal consignment reference |
| SUPPLIER_ID | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| REFERENCE_ID | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| LINE_ID | NUMERIC(6) | N | KEEP | Order line number |
| REASON_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| STATION_ID | VARCHAR(256) | Y | KEEP | Existing WMS field retained for FINatics |
| USER_ID | VARCHAR(20) | Y | KEEP | Existing WMS field retained for FINatics |
| UPDATE_QTY | NUMERIC(15,6) | Y | KEEP | Quantity change caused by transaction |
| ORIGINAL_QTY | NUMERIC(15,6) | N | KEEP | Existing WMS field retained for FINatics |
| COMPLETE_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| NOTES | VARCHAR(400) | N | KEEP | Existing WMS field retained for FINatics |
| LOCK_CODE | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| CUSTOMER_ID | VARCHAR(15) | N | KEEP | Customer identifier |
| SHIPMENT_NUMBER | NUMERIC(10) | N | KEEP | Shipment identifier |
| FROM_STATUS | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| TO_STATUS | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| SOURCE | VARCHAR(30) | N | ADD | Origin of transaction |
| REFERENCE_TYPE | VARCHAR(30) | N | ADD | Meaning of REFERENCE_ID |

## SHIPPING_MANIFEST

| Column | Type | Required | Action | Purpose |
|---|---|---:|---|---|
| KEY | NUMERIC(10) | Y | KEEP | Existing WMS field retained for FINatics |
| CLIENT_ID | VARCHAR(10) | Y | KEEP | Client/business identifier |
| ORDER_ID | VARCHAR(20) | Y | KEEP | Order identifier |
| LINE_ID | NUMERIC(6) | Y | KEEP | Order line number |
| TAG_ID | VARCHAR(50) | N | KEEP | Existing WMS field retained for FINatics |
| SKU_ID | VARCHAR(50) | Y | KEEP | Single FINatics SKU/product identifier |
| BATCH_ID | VARCHAR(50) | N | KEEP | Batch/spawn/lot identifier |
| EXPIRY_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| CONSIGNMENT | VARCHAR(20) | N | KEEP | Internal consignment reference |
| CONTAINER_ID | VARCHAR(50) | N | KEEP | Existing WMS field retained for FINatics |
| SITE_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| LOCATION_ID | VARCHAR(20) | Y | KEEP | Inventory/location identifier |
| OWNER_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| QTY_PICKED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| PICKED_DSTAMP | TIMESTAMPTZ | Y | KEEP | Audit/operational timestamp |
| QTY_SHIPPED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| SHIPPED_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| SHIPPED | VARCHAR(1) | Y | KEEP | Existing WMS field retained for FINatics |
| QTY_DELIVERED | NUMERIC(15,6) | N | KEEP | Quantity/status measure retained from WMS |
| DELIVERED_DSTAMP | TIMESTAMPTZ | N | KEEP | Audit/operational timestamp |
| DELIVERED | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| POD_CONFIRMED | VARCHAR(1) | N | KEEP | Existing WMS field retained for FINatics |
| POD_EXCEPTION_REASON | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| STATION_ID | VARCHAR(256) | N | KEEP | Existing WMS field retained for FINatics |
| USER_ID | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| SUPPLIER_ID | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| ORIGIN_ID | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| CONDITION_ID | VARCHAR(10) | N | KEEP | Inventory condition, useful for AVAILABLE/QUARANTINE etc. |
| LOCK_STATUS | VARCHAR(20) | N | KEEP | Inventory/location hold state |
| LOCK_CODE | VARCHAR(10) | N | KEEP | Existing WMS field retained for FINatics |
| NOTES | VARCHAR(80) | N | KEEP | Existing WMS field retained for FINatics |
| CUSTOMER_ID | VARCHAR(15) | N | KEEP | Customer identifier |
| SHIPMENT_NUMBER | NUMERIC(10) | N | KEEP | Shipment identifier |
| CARRIER_ID | VARCHAR(25) | N | KEEP | Carrier identifier |
| SERVICE_LEVEL | VARCHAR(40) | N | KEEP | Carrier/service level |
| LOAD_SEQUENCE | NUMERIC(10) | N | KEEP | Existing WMS field retained for FINatics |
| CARRIER_CONTAINER_ID | VARCHAR(50) | N | KEEP | Existing WMS field retained for FINatics |
| CONTAINER_WEIGHT | NUMERIC(13,6) | N | KEEP | Existing WMS field retained for FINatics |
| CONTAINER_HEIGHT | NUMERIC(13,6) | N | KEEP | Existing WMS field retained for FINatics |
| CONTAINER_WIDTH | NUMERIC(13,6) | N | KEEP | Existing WMS field retained for FINatics |
| CONTAINER_DEPTH | NUMERIC(13,6) | N | KEEP | Existing WMS field retained for FINatics |
| CONTAINER_TYPE | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| CONTAINER_N_OF_N | NUMERIC(5) | N | KEEP | Existing WMS field retained for FINatics |
| STATUS | VARCHAR(15) | N | KEEP | Existing WMS field retained for FINatics |
| CUSTOMER_SHIPMENT_NUMBER | NUMERIC(10) | N | KEEP | Existing WMS field retained for FINatics |
| SHIPMENT_GROUP | VARCHAR(20) | N | KEEP | Existing WMS field retained for FINatics |
| SHIPMENT_REF | VARCHAR(50) | N | KEEP | Existing WMS field retained for FINatics |
| CARRIER_CONSIGNMENT_NUM | NUMERIC(3) | N | KEEP | Existing WMS field retained for FINatics |
| CARRIER_CONSIGNMENT_ID | VARCHAR(30) | N | KEEP | Carrier consignment reference |
| TOTAL_VOLUME | NUMERIC(13,6) | N | KEEP | Existing WMS field retained for FINatics |
| CARRIER_MANIFEST_NUMBER | VARCHAR(20) | N | KEEP | Carrier manifest reference |
| TRANSPORT_BOXES | NUMERIC(4) | N | KEEP | Existing WMS field retained for FINatics |
| DISPATCH_METHOD | VARCHAR(30) | N | ADD | Dispatch route for this shipment/container |
| TRACKING_NUMBER | VARCHAR(120) | N | ADD | Carrier tracking number |
| TRACKING_URL | TEXT | N | ADD | Carrier/customer tracking link |
| TRACKING_STATUS | VARCHAR(30) | N | ADD | Latest tracking state |
| TRACKING_LAST_DSTAMP | TIMESTAMPTZ | N | ADD | When tracking state was last refreshed |
| DISPATCH_COST | NUMERIC(12,2) | N | ADD | Actual cost to FINatics to dispatch this shipment |
| COLLECTED_DSTAMP | TIMESTAMPTZ | N | ADD | Customer collection timestamp when method is collection |
| POD_NAME | VARCHAR(120) | N | ADD | Name of recipient/collector |
| POD_IMAGE_URL | TEXT | N | ADD | Optional proof-of-delivery image/reference |
| LOCAL_DRIVER | VARCHAR(120) | N | ADD | Driver/user for FINatics local deliveries |
