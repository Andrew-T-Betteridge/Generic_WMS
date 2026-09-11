-- ORDER_HEADER
-- Generated from the previously refined FINatics_DB_Keep_Only.xlsx specification.
-- Generic WMS core: no fish-specific table naming.

CREATE TABLE IF NOT EXISTS core.ORDER_HEADER (
    CLIENT_ID                      VARCHAR(10) NOT NULL,
    ORDER_ID                       VARCHAR(20) NOT NULL,
    ORDER_TYPE                     VARCHAR(10),
    STATUS                         VARCHAR(15),
    PRIORITY                       NUMERIC(4),
    CONSIGNMENT                    VARCHAR(20),
    DELIVERY_POINT                 VARCHAR(15),
    FROM_SITE_ID                   VARCHAR(10),
    TO_SITE_ID                     VARCHAR(10),
    OWNER_ID                       VARCHAR(10),
    CUSTOMER_ID                    VARCHAR(15),
    ORDER_DATE                     TIMESTAMPTZ NOT NULL,
    SHIP_BY_DATE                   TIMESTAMPTZ,
    DELIVER_BY_DATE                TIMESTAMPTZ,
    SHIPPED_DATE                   TIMESTAMPTZ,
    DELIVERED_DSTAMP               TIMESTAMPTZ,
    SIGNATORY                      VARCHAR(25),
    PURCHASE_ORDER                 VARCHAR(25),
    CARRIER_ID                     VARCHAR(25),
    DISPATCH_METHOD                VARCHAR(40),
    SERVICE_LEVEL                  VARCHAR(40),
    INV_ADDRESS_ID                 VARCHAR(15),
    INV_CONTACT                    VARCHAR(25),
    INV_CONTACT_PHONE              VARCHAR(25),
    INV_CONTACT_MOBILE             VARCHAR(25),
    INV_CONTACT_EMAIL              VARCHAR(256),
    INV_NAME                       VARCHAR(50),
    INV_ADDRESS1                   VARCHAR(60),
    INV_ADDRESS2                   VARCHAR(60),
    INV_TOWN                       VARCHAR(60),
    INV_COUNTY                     VARCHAR(60),
    INV_POSTCODE                   VARCHAR(20),
    INV_COUNTRY                    VARCHAR(25),
    INSTRUCTIONS                   VARCHAR(180),
    ORDER_VOLUME                   NUMERIC(15,6),
    ORDER_WEIGHT                   NUMERIC(15,6),
    CONTACT                        VARCHAR(25),
    CONTACT_PHONE                  VARCHAR(25),
    CONTACT_MOBILE                 VARCHAR(25),
    CONTACT_EMAIL                  VARCHAR(256),
    NAME                           VARCHAR(50),
    ADDRESS1                       VARCHAR(60),
    ADDRESS2                       VARCHAR(60),
    TOWN                           VARCHAR(60),
    COUNTY                         VARCHAR(60),
    POSTCODE                       VARCHAR(20),
    COUNTRY                        VARCHAR(25),
    NO_SHIPMENT_EMAIL              VARCHAR(1),
    ORDER_SOURCE                   VARCHAR(1),
    NUM_LINES                      NUMERIC(6),
    CREATED_BY                     VARCHAR(20),
    CREATION_DATE                  TIMESTAMPTZ,
    LAST_UPDATED_BY                VARCHAR(20),
    LAST_UPDATE_DATE               TIMESTAMPTZ,
    STATUS_REASON_CODE             VARCHAR(10),
    ARCHIVED                       VARCHAR(1),
    CLOSURE_DATE                   TIMESTAMPTZ,
    ORDER_CLOSED                   VARCHAR(1),
    ORDER_VALUE                    NUMERIC(12,3),
    EXPECTED_VOLUME                NUMERIC(15,6),
    EXPECTED_WEIGHT                NUMERIC(15,6),
    EXPECTED_VALUE                 NUMERIC(12,3),
    LANGUAGE                       VARCHAR(8),
    VAT_NUMBER                     VARCHAR(20),
    INV_VAT_NUMBER                 VARCHAR(20),
    INV_REFERENCE                  VARCHAR(35),
    INV_DSTAMP                     TIMESTAMPTZ,
    INV_CURRENCY                   VARCHAR(3),
    PAYMENT_TERMS                  VARCHAR(35),
    SUBTOTAL_1                     NUMERIC(12,3),
    FREIGHT_COST                   NUMERIC(12,3),
    DISCOUNT                       NUMERIC(12,3),
    TAX_RATE_1                     NUMERIC(12,3),
    TAX_AMOUNT_1                   NUMERIC(12,3),
    ORDER_REFERENCE                VARCHAR(35),
    PACKING_NOTES                  VARCHAR(200),
    PAYMENT_STATUS                 VARCHAR(20),
    PAYMENT_METHOD                 VARCHAR(30),
    PAYMENT_REFERENCE              VARCHAR(120),
    PAYMENT_DSTAMP                 TIMESTAMPTZ,
    FULFILMENT_STATUS              VARCHAR(30),
    PROMO_CODE                     VARCHAR(50),
    FREE_DELIVERY                  CHAR(1) NOT NULL,
    DELIVERY_DISTANCE_MILES        NUMERIC(8,2),
    PRIMARY KEY (CLIENT_ID, ORDER_ID),
    FOREIGN KEY (CLIENT_ID) REFERENCES core.CLIENT (CLIENT_ID)
);

COMMENT ON COLUMN core.ORDER_HEADER.CLIENT_ID IS 'KEEP: Client/business identifier';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_ID IS 'KEEP: Order identifier';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_TYPE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.STATUS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.PRIORITY IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.CONSIGNMENT IS 'KEEP: Internal consignment reference';
COMMENT ON COLUMN core.ORDER_HEADER.DELIVERY_POINT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.FROM_SITE_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.TO_SITE_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.OWNER_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.CUSTOMER_ID IS 'KEEP: Customer identifier';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.SHIP_BY_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.DELIVER_BY_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.SHIPPED_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.DELIVERED_DSTAMP IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.SIGNATORY IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.PURCHASE_ORDER IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.CARRIER_ID IS 'KEEP: Carrier identifier';
COMMENT ON COLUMN core.ORDER_HEADER.DISPATCH_METHOD IS 'KEEP: Dispatch method';
COMMENT ON COLUMN core.ORDER_HEADER.SERVICE_LEVEL IS 'KEEP: Carrier/service level';
COMMENT ON COLUMN core.ORDER_HEADER.INV_ADDRESS_ID IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.INV_CONTACT IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_CONTACT_PHONE IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_CONTACT_MOBILE IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_CONTACT_EMAIL IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_NAME IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_ADDRESS1 IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.INV_ADDRESS2 IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.INV_TOWN IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_COUNTY IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_POSTCODE IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_COUNTRY IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INSTRUCTIONS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_VOLUME IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_WEIGHT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.CONTACT IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.CONTACT_PHONE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.CONTACT_MOBILE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.CONTACT_EMAIL IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.NAME IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.ADDRESS1 IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.ADDRESS2 IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.TOWN IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.COUNTY IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.POSTCODE IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.COUNTRY IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ORDER_HEADER.NO_SHIPMENT_EMAIL IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_SOURCE IS 'KEEP: Order source e.g. WEB/FACEBOOK/MANUAL';
COMMENT ON COLUMN core.ORDER_HEADER.NUM_LINES IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.CREATED_BY IS 'KEEP: Audit field';
COMMENT ON COLUMN core.ORDER_HEADER.CREATION_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.LAST_UPDATED_BY IS 'KEEP: Audit field';
COMMENT ON COLUMN core.ORDER_HEADER.LAST_UPDATE_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.STATUS_REASON_CODE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.ARCHIVED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.CLOSURE_DATE IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_CLOSED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_VALUE IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_HEADER.EXPECTED_VOLUME IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.EXPECTED_WEIGHT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.EXPECTED_VALUE IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_HEADER.LANGUAGE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.VAT_NUMBER IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.INV_VAT_NUMBER IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_REFERENCE IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.INV_DSTAMP IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.ORDER_HEADER.INV_CURRENCY IS 'KEEP: Invoice/billing information';
COMMENT ON COLUMN core.ORDER_HEADER.PAYMENT_TERMS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.SUBTOTAL_1 IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_HEADER.FREIGHT_COST IS 'KEEP: Delivery/freight charge/cost';
COMMENT ON COLUMN core.ORDER_HEADER.DISCOUNT IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_HEADER.TAX_RATE_1 IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.TAX_AMOUNT_1 IS 'KEEP: Commercial value captured for order';
COMMENT ON COLUMN core.ORDER_HEADER.ORDER_REFERENCE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.PACKING_NOTES IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ORDER_HEADER.PAYMENT_STATUS IS 'ADD: Payment state';
COMMENT ON COLUMN core.ORDER_HEADER.PAYMENT_METHOD IS 'ADD: Payment method';
COMMENT ON COLUMN core.ORDER_HEADER.PAYMENT_REFERENCE IS 'ADD: Stripe/provider payment reference';
COMMENT ON COLUMN core.ORDER_HEADER.PAYMENT_DSTAMP IS 'ADD: When payment completed';
COMMENT ON COLUMN core.ORDER_HEADER.FULFILMENT_STATUS IS 'ADD: Overall fulfilment state';
COMMENT ON COLUMN core.ORDER_HEADER.PROMO_CODE IS 'ADD: Promotion code used';
COMMENT ON COLUMN core.ORDER_HEADER.FREE_DELIVERY IS 'ADD: Whether delivery charge was waived';
COMMENT ON COLUMN core.ORDER_HEADER.DELIVERY_DISTANCE_MILES IS 'ADD: Calculated distance used for local delivery pricing';
