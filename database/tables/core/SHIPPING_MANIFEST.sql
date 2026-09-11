-- SHIPPING_MANIFEST
-- Generated from the previously refined FINatics_DB_Keep_Only.xlsx specification.
-- Generic WMS core: no fish-specific table naming.

CREATE TABLE IF NOT EXISTS core.SHIPPING_MANIFEST (
    KEY                            NUMERIC(10) NOT NULL,
    CLIENT_ID                      VARCHAR(10) NOT NULL,
    ORDER_ID                       VARCHAR(20) NOT NULL,
    LINE_ID                        NUMERIC(6) NOT NULL,
    TAG_ID                         VARCHAR(50),
    SKU_ID                         VARCHAR(50) NOT NULL,
    BATCH_ID                       VARCHAR(50),
    EXPIRY_DSTAMP                  TIMESTAMPTZ,
    CONSIGNMENT                    VARCHAR(20),
    CONTAINER_ID                   VARCHAR(50),
    SITE_ID                        VARCHAR(10),
    LOCATION_ID                    VARCHAR(20) NOT NULL,
    OWNER_ID                       VARCHAR(10),
    QTY_PICKED                     NUMERIC(15,6),
    PICKED_DSTAMP                  TIMESTAMPTZ NOT NULL,
    QTY_SHIPPED                    NUMERIC(15,6),
    SHIPPED_DSTAMP                 TIMESTAMPTZ,
    SHIPPED                        VARCHAR(1) NOT NULL,
    QTY_DELIVERED                  NUMERIC(15,6),
    DELIVERED_DSTAMP               TIMESTAMPTZ,
    DELIVERED                      VARCHAR(1),
    POD_CONFIRMED                  VARCHAR(1),
    POD_EXCEPTION_REASON           VARCHAR(10),
    STATION_ID                     VARCHAR(256),
    USER_ID                        VARCHAR(20),
    SUPPLIER_ID                    VARCHAR(15),
    ORIGIN_ID                      VARCHAR(10),
    CONDITION_ID                   VARCHAR(10),
    LOCK_STATUS                    VARCHAR(20),
    LOCK_CODE                      VARCHAR(10),
    NOTES                          VARCHAR(80),
    CUSTOMER_ID                    VARCHAR(15),
    SHIPMENT_NUMBER                NUMERIC(10),
    CARRIER_ID                     VARCHAR(25),
    SERVICE_LEVEL                  VARCHAR(40),
    LOAD_SEQUENCE                  NUMERIC(10),
    CARRIER_CONTAINER_ID           VARCHAR(50),
    CONTAINER_WEIGHT               NUMERIC(13,6),
    CONTAINER_HEIGHT               NUMERIC(13,6),
    CONTAINER_WIDTH                NUMERIC(13,6),
    CONTAINER_DEPTH                NUMERIC(13,6),
    CONTAINER_TYPE                 VARCHAR(15),
    CONTAINER_N_OF_N               NUMERIC(5),
    STATUS                         VARCHAR(15),
    CUSTOMER_SHIPMENT_NUMBER       NUMERIC(10),
    SHIPMENT_GROUP                 VARCHAR(20),
    SHIPMENT_REF                   VARCHAR(50),
    CARRIER_CONSIGNMENT_NUM        NUMERIC(3),
    CARRIER_CONSIGNMENT_ID         VARCHAR(30),
    TOTAL_VOLUME                   NUMERIC(13,6),
    CARRIER_MANIFEST_NUMBER        VARCHAR(20),
    TRANSPORT_BOXES                NUMERIC(4),
    DISPATCH_METHOD                VARCHAR(30),
    TRACKING_NUMBER                VARCHAR(120),
    TRACKING_URL                   TEXT,
    TRACKING_STATUS                VARCHAR(30),
    TRACKING_LAST_DSTAMP           TIMESTAMPTZ,
    DISPATCH_COST                  NUMERIC(12,2),
    COLLECTED_DSTAMP               TIMESTAMPTZ,
    POD_NAME                       VARCHAR(120),
    POD_IMAGE_URL                  TEXT,
    LOCAL_DRIVER                   VARCHAR(120),
    PRIMARY KEY (KEY),
    FOREIGN KEY (CLIENT_ID, ORDER_ID, LINE_ID) REFERENCES core.ORDER_LINE (CLIENT_ID, ORDER_ID, LINE_ID),
    FOREIGN KEY (CLIENT_ID, SKU_ID) REFERENCES core.SKU (CLIENT_ID, SKU_ID),
    FOREIGN KEY (LOCATION_ID) REFERENCES core.LOCATION (LOCATION_ID)
);

COMMENT ON COLUMN core.SHIPPING_MANIFEST.KEY IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CLIENT_ID IS 'KEEP: Client/business identifier';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.ORDER_ID IS 'KEEP: Order identifier';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.LINE_ID IS 'KEEP: Order line number';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.TAG_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SKU_ID IS 'KEEP: Single FINatics SKU/product identifier';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.BATCH_ID IS 'KEEP: Batch/spawn/lot identifier';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.EXPIRY_DSTAMP IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONSIGNMENT IS 'KEEP: Internal consignment reference';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONTAINER_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SITE_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.LOCATION_ID IS 'KEEP: Inventory/location identifier';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.OWNER_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.QTY_PICKED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.PICKED_DSTAMP IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.QTY_SHIPPED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SHIPPED_DSTAMP IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SHIPPED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.QTY_DELIVERED IS 'KEEP: Quantity/status measure retained from WMS';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.DELIVERED_DSTAMP IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.DELIVERED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.POD_CONFIRMED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.POD_EXCEPTION_REASON IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.STATION_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.USER_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SUPPLIER_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.ORIGIN_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONDITION_ID IS 'KEEP: Inventory condition, useful for AVAILABLE/QUARANTINE etc.';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.LOCK_STATUS IS 'KEEP: Inventory/location hold state';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.LOCK_CODE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.NOTES IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CUSTOMER_ID IS 'KEEP: Customer identifier';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SHIPMENT_NUMBER IS 'KEEP: Shipment identifier';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CARRIER_ID IS 'KEEP: Carrier identifier';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SERVICE_LEVEL IS 'KEEP: Carrier/service level';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.LOAD_SEQUENCE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CARRIER_CONTAINER_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONTAINER_WEIGHT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONTAINER_HEIGHT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONTAINER_WIDTH IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONTAINER_DEPTH IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONTAINER_TYPE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CONTAINER_N_OF_N IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.STATUS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CUSTOMER_SHIPMENT_NUMBER IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SHIPMENT_GROUP IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.SHIPMENT_REF IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CARRIER_CONSIGNMENT_NUM IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CARRIER_CONSIGNMENT_ID IS 'KEEP: Carrier consignment reference';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.TOTAL_VOLUME IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.CARRIER_MANIFEST_NUMBER IS 'KEEP: Carrier manifest reference';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.TRANSPORT_BOXES IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.DISPATCH_METHOD IS 'ADD: Dispatch route for this shipment/container';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.TRACKING_NUMBER IS 'ADD: Carrier tracking number';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.TRACKING_URL IS 'ADD: Carrier/customer tracking link';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.TRACKING_STATUS IS 'ADD: Latest tracking state';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.TRACKING_LAST_DSTAMP IS 'ADD: When tracking state was last refreshed';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.DISPATCH_COST IS 'ADD: Actual cost to FINatics to dispatch this shipment';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.COLLECTED_DSTAMP IS 'ADD: Customer collection timestamp when method is collection';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.POD_NAME IS 'ADD: Name of recipient/collector';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.POD_IMAGE_URL IS 'ADD: Optional proof-of-delivery image/reference';
COMMENT ON COLUMN core.SHIPPING_MANIFEST.LOCAL_DRIVER IS 'ADD: Driver/user for FINatics local deliveries';
