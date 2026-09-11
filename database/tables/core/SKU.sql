-- SKU
-- Generated from the previously refined FINatics_DB_Keep_Only.xlsx specification.
-- Generic WMS core: no fish-specific table naming.

CREATE TABLE IF NOT EXISTS core.SKU (
    CLIENT_ID                      VARCHAR(10) NOT NULL,
    SKU_ID                         VARCHAR(50) NOT NULL,
    EAN                            VARCHAR(14),
    UPC                            VARCHAR(14),
    DESCRIPTION                    VARCHAR(80),
    PRODUCT_GROUP                  VARCHAR(10),
    EACH_HEIGHT                    NUMERIC(15,6),
    EACH_WEIGHT                    NUMERIC(13,6),
    EACH_VOLUME                    NUMERIC(13,6),
    EACH_VALUE                     NUMERIC(12,3),
    SHELF_LIFE                     NUMERIC(5),
    EXPIRY_REQD                    VARCHAR(1),
    OBSOLETE_PRODUCT               VARCHAR(1),
    NEW_PRODUCT                    VARCHAR(1),
    COLOUR                         VARCHAR(20),
    SKU_SIZE                       VARCHAR(10),
    EACH_WIDTH                     NUMERIC(7,3),
    EACH_DEPTH                     NUMERIC(7,3),
    REORDER_TRIGGER_QTY            NUMERIC(15,6),
    LOW_TRIGGER_QTY                NUMERIC(15,6),
    CREATED_BY                     VARCHAR(20),
    CREATION_DATE                  TIMESTAMPTZ,
    LAST_UPDATED_BY                VARCHAR(20),
    LAST_UPDATE_DATE               TIMESTAMPTZ,
    COMMODITY_CODE                 VARCHAR(22),
    FAMILY_GROUP                   VARCHAR(15),
    FRAGILE                        VARCHAR(1),
    ECOMMERCE                      VARCHAR(1),
    PROMOTION                      VARCHAR(1),
    STYLE                          VARCHAR(10),
    DECATALOGUED                   VARCHAR(1),
    HAZMAT                         VARCHAR(1),
    SUB_GROUP                      VARCHAR(30),
    CATEGORY                       VARCHAR(50),
    MANUFACTURER_ID                VARCHAR(30),
    MANUFACTURER_SKU               VARCHAR(80),
    BRAND_NAME                     VARCHAR(80),
    PREFERRED_SUPPLIER_ID          VARCHAR(30),
    SUPPLIER_SKU                   VARCHAR(80),
    SELL_PRICE                     NUMERIC(12,2),
    COST_PRICE                     NUMERIC(12,2),
    VAT_RATE                       NUMERIC(5,2),
    WEB_TITLE                      VARCHAR(160),
    WEB_DESCRIPTION                TEXT,
    WEB_SLUG                       VARCHAR(180),
    WEB_ACTIVE                     CHAR(1) NOT NULL,
    WEB_FEATURED                   CHAR(1) NOT NULL,
    WEB_IMAGE_1                    TEXT,
    WEB_IMAGE_2                    TEXT,
    WEB_IMAGE_3                    TEXT,
    WEB_IMAGE_4                    TEXT,
    WEB_IMAGE_5                    TEXT,
    WEB_VIDEO_URL                  TEXT,
    FULFILMENT_TYPE                VARCHAR(20),
    SUPPLIER_DIRECT_ENABLED        CHAR(1) NOT NULL,
    AFFILIATE_FALLBACK             CHAR(1) NOT NULL,
    AFFILIATE_URL                  TEXT,
    MIN_ORDER_QTY                  NUMERIC(15,6),
    MAX_ORDER_QTY                  NUMERIC(15,6),
    GENUS                          VARCHAR(80),
    SPECIES                        VARCHAR(120),
    LINEAGE                        VARCHAR(20),
    SEX                            VARCHAR(20),
    ADULT_SIZE_CM                  NUMERIC(6,2),
    CARE_NOTES                     TEXT,
    COMING_SOON                    CHAR(1) NOT NULL,
    AVAILABLE_DSTAMP               TIMESTAMPTZ,
    PRIMARY KEY (CLIENT_ID, SKU_ID),
    FOREIGN KEY (CLIENT_ID) REFERENCES core.CLIENT (CLIENT_ID)
);

COMMENT ON COLUMN core.SKU.CLIENT_ID IS 'KEEP: Client/business identifier';
COMMENT ON COLUMN core.SKU.SKU_ID IS 'KEEP: Single FINatics SKU/product identifier';
COMMENT ON COLUMN core.SKU.EAN IS 'KEEP: Optional barcode/product identifier';
COMMENT ON COLUMN core.SKU.UPC IS 'KEEP: Optional barcode/product identifier';
COMMENT ON COLUMN core.SKU.DESCRIPTION IS 'KEEP: Operational item description';
COMMENT ON COLUMN core.SKU.PRODUCT_GROUP IS 'KEEP: Top-level product hierarchy';
COMMENT ON COLUMN core.SKU.EACH_HEIGHT IS 'KEEP: Physical product dimension/weight';
COMMENT ON COLUMN core.SKU.EACH_WEIGHT IS 'KEEP: Physical product dimension/weight';
COMMENT ON COLUMN core.SKU.EACH_VOLUME IS 'KEEP: Physical product dimension/weight';
COMMENT ON COLUMN core.SKU.EACH_VALUE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SKU.SHELF_LIFE IS 'KEEP: Useful for food/dated stock';
COMMENT ON COLUMN core.SKU.EXPIRY_REQD IS 'KEEP: Useful for food/dated stock';
COMMENT ON COLUMN core.SKU.OBSOLETE_PRODUCT IS 'KEEP: Product lifecycle control';
COMMENT ON COLUMN core.SKU.NEW_PRODUCT IS 'KEEP: Product lifecycle control';
COMMENT ON COLUMN core.SKU.COLOUR IS 'KEEP: Colour/visual classification';
COMMENT ON COLUMN core.SKU.SKU_SIZE IS 'KEEP: Size sold/handled';
COMMENT ON COLUMN core.SKU.EACH_WIDTH IS 'KEEP: Physical product dimension/weight';
COMMENT ON COLUMN core.SKU.EACH_DEPTH IS 'KEEP: Physical product dimension/weight';
COMMENT ON COLUMN core.SKU.REORDER_TRIGGER_QTY IS 'KEEP: Stock replenishment threshold';
COMMENT ON COLUMN core.SKU.LOW_TRIGGER_QTY IS 'KEEP: Stock replenishment threshold';
COMMENT ON COLUMN core.SKU.CREATED_BY IS 'KEEP: Audit field';
COMMENT ON COLUMN core.SKU.CREATION_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.SKU.LAST_UPDATED_BY IS 'KEEP: Audit field';
COMMENT ON COLUMN core.SKU.LAST_UPDATE_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.SKU.COMMODITY_CODE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SKU.FAMILY_GROUP IS 'KEEP: Second-level product hierarchy';
COMMENT ON COLUMN core.SKU.FRAGILE IS 'KEEP: Dispatch/handling property';
COMMENT ON COLUMN core.SKU.ECOMMERCE IS 'KEEP: Existing ecommerce eligibility flag';
COMMENT ON COLUMN core.SKU.PROMOTION IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SKU.STYLE IS 'KEEP: Existing style/variant classification field';
COMMENT ON COLUMN core.SKU.DECATALOGUED IS 'KEEP: Product lifecycle control';
COMMENT ON COLUMN core.SKU.HAZMAT IS 'KEEP: Dispatch/handling property';
COMMENT ON COLUMN core.SKU.SUB_GROUP IS 'ADD: 3rd category level';
COMMENT ON COLUMN core.SKU.CATEGORY IS 'ADD: 4th category/product family level';
COMMENT ON COLUMN core.SKU.MANUFACTURER_ID IS 'ADD: Manufacturer identifier';
COMMENT ON COLUMN core.SKU.MANUFACTURER_SKU IS 'ADD: Manufacturer''s own product code';
COMMENT ON COLUMN core.SKU.BRAND_NAME IS 'ADD: Customer-facing brand';
COMMENT ON COLUMN core.SKU.PREFERRED_SUPPLIER_ID IS 'ADD: Preferred source when purchasing stock';
COMMENT ON COLUMN core.SKU.SUPPLIER_SKU IS 'ADD: Supplier product reference';
COMMENT ON COLUMN core.SKU.SELL_PRICE IS 'ADD: Current FINatics selling price';
COMMENT ON COLUMN core.SKU.COST_PRICE IS 'ADD: Current expected unit cost';
COMMENT ON COLUMN core.SKU.VAT_RATE IS 'ADD: VAT percentage used for web pricing';
COMMENT ON COLUMN core.SKU.WEB_TITLE IS 'ADD: SEO/customer product title; DESCRIPTION remains operational description';
COMMENT ON COLUMN core.SKU.WEB_DESCRIPTION IS 'ADD: Full customer-facing product description';
COMMENT ON COLUMN core.SKU.WEB_SLUG IS 'ADD: Stable product page path';
COMMENT ON COLUMN core.SKU.WEB_ACTIVE IS 'ADD: Whether the SKU appears on the website';
COMMENT ON COLUMN core.SKU.WEB_FEATURED IS 'ADD: Homepage/featured product flag';
COMMENT ON COLUMN core.SKU.WEB_IMAGE_1 IS 'ADD: Primary product image URL/path';
COMMENT ON COLUMN core.SKU.WEB_IMAGE_2 IS 'ADD: Additional image URL/path';
COMMENT ON COLUMN core.SKU.WEB_IMAGE_3 IS 'ADD: Additional image URL/path';
COMMENT ON COLUMN core.SKU.WEB_IMAGE_4 IS 'ADD: Additional image URL/path';
COMMENT ON COLUMN core.SKU.WEB_IMAGE_5 IS 'ADD: Additional image URL/path';
COMMENT ON COLUMN core.SKU.WEB_VIDEO_URL IS 'ADD: Optional product/fish video';
COMMENT ON COLUMN core.SKU.FULFILMENT_TYPE IS 'ADD: Default fulfilment route';
COMMENT ON COLUMN core.SKU.SUPPLIER_DIRECT_ENABLED IS 'ADD: Allow supplier-direct fallback';
COMMENT ON COLUMN core.SKU.AFFILIATE_FALLBACK IS 'ADD: Allow affiliate route when own/supplier stock unavailable';
COMMENT ON COLUMN core.SKU.AFFILIATE_URL IS 'ADD: External tracked affiliate URL';
COMMENT ON COLUMN core.SKU.MIN_ORDER_QTY IS 'ADD: Minimum purchasable quantity';
COMMENT ON COLUMN core.SKU.MAX_ORDER_QTY IS 'ADD: Maximum quantity per order if required';
COMMENT ON COLUMN core.SKU.GENUS IS 'ADD: Fish only - genus';
COMMENT ON COLUMN core.SKU.SPECIES IS 'ADD: Fish only - species/strain name';
COMMENT ON COLUMN core.SKU.LINEAGE IS 'ADD: Fish only - lineage';
COMMENT ON COLUMN core.SKU.SEX IS 'ADD: Fish only - sex where sold by sex';
COMMENT ON COLUMN core.SKU.ADULT_SIZE_CM IS 'ADD: Fish only - expected adult size';
COMMENT ON COLUMN core.SKU.CARE_NOTES IS 'ADD: Fish only - care / compatibility notes';
COMMENT ON COLUMN core.SKU.COMING_SOON IS 'ADD: Display product before stock is sellable';
COMMENT ON COLUMN core.SKU.AVAILABLE_DSTAMP IS 'ADD: Expected availability date/time';
