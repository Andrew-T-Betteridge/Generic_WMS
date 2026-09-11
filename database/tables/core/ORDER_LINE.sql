-- ORDER_LINE
-- Generated from the previously refined FINatics_DB_Keep_Only.xlsx specification.
-- Generic WMS core: no fish-specific table naming.

CREATE TABLE IF NOT EXISTS core.ORDER_LINE (
    CLIENT_ID                      VARCHAR(10) NOT NULL,
    ORDER_ID                       VARCHAR(20) NOT NULL,
    LINE_ID                        NUMERIC(6) NOT NULL,
    SKU_ID                         VARCHAR(50) NOT NULL,
    BATCH_ID                       VARCHAR(50),
    CONDITION_ID                   VARCHAR(10),
    QTY_ORDERED                    NUMERIC(15,6) NOT NULL,
    QTY_TASKED                     NUMERIC(15,6),
    QTY_PICKED                     NUMERIC(15,6),
    QTY_SHIPPED                    NUMERIC(15,6),
    QTY_DELIVERED                  NUMERIC(15,6),
    QTY_RETURNED                   NUMERIC(15,6),
    QTY_SOFT_ALLOCATED             NUMERIC(15,6),
    ALLOCATE                       VARCHAR(1),
    BACK_ORDERED                   VARCHAR(1),
    CREATED_BY                     VARCHAR(20),
    CREATION_DATE                  TIMESTAMPTZ,
    LAST_UPDATED_BY                VARCHAR(20),
    LAST_UPDATE_DATE               TIMESTAMPTZ,
    LINE_VALUE                     NUMERIC(12,3),
    NOTES                          VARCHAR(80),
    MIN_QTY_ORDERED                NUMERIC(15,6),
    MAX_QTY_ORDERED                NUMERIC(15,6),
    EXPECTED_VOLUME                NUMERIC(15,6),
    EXPECTED_WEIGHT                NUMERIC(15,6),
    EXPECTED_VALUE                 NUMERIC(12,3),
    PRODUCT_PRICE                  NUMERIC(12,3),
    PRODUCT_CURRENCY               VARCHAR(3),
    EXTENDED_PRICE                 NUMERIC(12,3),
    TAX_1                          NUMERIC(12,3),
    TAX_2                          NUMERIC(12,3),
    OWNER_ID                       VARCHAR(10),
    LOCATION_ID                    VARCHAR(20),
    FULFILMENT_TYPE                VARCHAR(20),
    SUPPLIER_ID                    VARCHAR(30),
    UNIT_COST                      NUMERIC(12,2),
    DISCOUNT_VALUE                 NUMERIC(12,2),
    VAT_RATE                       NUMERIC(5,2),
    EXTERNAL_FULFILMENT_REF        VARCHAR(120),
    PRIMARY KEY (CLIENT_ID, ORDER_ID, LINE_ID),
    FOREIGN KEY (CLIENT_ID, ORDER_ID) REFERENCES core.ORDER_HEADER (CLIENT_ID, ORDER_ID),
    FOREIGN KEY (CLIENT_ID, SKU_ID) REFERENCES core.SKU (CLIENT_ID, SKU_ID)
);

COMMENT ON COLUMN core.ORDER_LINE.CLIENT_ID IS 'KEEP: Client/business identifier';
COMMENT ON COLUMN core.ORDER_LINE.ORDER_ID IS 'KEEP: Order identifier';
COMMENT ON COLUMN core.ORDER_LINE.LINE_ID IS 'KEEP: Order line number';
COMMENT ON COLUMN core.ORDER_LINE.SKU_ID IS 'KEEP: Single FINatics SKU/product identifier';
COMMENT ON COLUMN core.ORDER_LINE.BATCH_ID IS 'KEEP: Batch/spawn/lot identifier';
COMMENT ON COLUMN core.ORDER_LINE.CONDITION_ID IS 'KEEP: Inventory condition, useful for AVAILABLE/QUARANTINE etc.';
COMMENT ON COLUMN core.ORDER_LINE.QTY_ORDERED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.ORDER_LINE.QTY_TASKED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.ORDER_LINE.QTY_PICKED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.ORDER_LINE.QTY_SHIPPED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.ORDER_LINE.QTY_DELIVERED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.ORDER_LINE.QTY_RETURNED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.ORDER_LINE.QTY_SOFT_ALLOCATED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.ORDER_LINE.ALLOCATE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.BACK_ORDERED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.CREATED_BY IS 'KEEP: Audit field';
COMMENT ON COLUMN core.ORDER_LINE.CREATION_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_LINE.LAST_UPDATED_BY IS 'KEEP: Audit field';
COMMENT ON COLUMN core.ORDER_LINE.LAST_UPDATE_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_LINE.LINE_VALUE IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_LINE.NOTES IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.MIN_QTY_ORDERED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.MAX_QTY_ORDERED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.EXPECTED_VOLUME IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.EXPECTED_WEIGHT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.EXPECTED_VALUE IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_LINE.PRODUCT_PRICE IS 'KEEP: Unit sell price captured on the order line';
COMMENT ON COLUMN core.ORDER_LINE.PRODUCT_CURRENCY IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.EXTENDED_PRICE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.TAX_1 IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_LINE.TAX_2 IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_LINE.OWNER_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_LINE.LOCATION_ID IS 'KEEP: Inventory/location identifier';
COMMENT ON COLUMN core.ORDER_LINE.FULFILMENT_TYPE IS 'ADD: Actual fulfilment route for this line';
COMMENT ON COLUMN core.ORDER_LINE.SUPPLIER_ID IS 'ADD: Supplier used for direct fulfilment';
COMMENT ON COLUMN core.ORDER_LINE.UNIT_COST IS 'ADD: Cost snapshot at order time';
COMMENT ON COLUMN core.ORDER_LINE.DISCOUNT_VALUE IS 'ADD: Line discount amount';
COMMENT ON COLUMN core.ORDER_LINE.VAT_RATE IS 'ADD: VAT rate snapshot';
COMMENT ON COLUMN core.ORDER_LINE.EXTERNAL_FULFILMENT_REF IS 'ADD: Supplier/external reference where applicable';
